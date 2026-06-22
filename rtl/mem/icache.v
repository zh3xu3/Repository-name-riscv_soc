`timescale 1ns / 1ps

// ============================================================================
// Instruction Cache - Direct-mapped, 2KB default
// ============================================================================
//
// Cache structure (default 2KB, 16B line):
//   Lines     = CACHE_SIZE / LINE_SIZE = 2048 / 16 = 128
//   Offset    = log2(LINE_SIZE)       = log2(16)   = 4  bits [3:0]
//   Index     = log2(LINES)           = log2(128)  = 7  bits [10:4]
//   Tag       = 32 - Index - Offset                = 21 bits [31:11]
//
// Each cache line stores:
//   - valid bit
//   - tag (ADDR_WIDTH - INDEX_BITS - OFFSET_BITS)
//   - data (LINE_SIZE bytes = LINE_SIZE/4 words)
//
// State machine:
//   IDLE    -> wait for CPU read request
//   COMPARE -> check tag match (hit/miss)
//   FETCH   -> request entire cache line from memory (word by word)
//   REFILL  -> write fetched data into cache, re-drive to CPU
//
// Control registers at 0x0000_9000 - 0x0000_900F:
//   0x00 CTRL     [0]=enable, [1]=flush (W1S, auto-clear)
//   0x04 STATUS   [0]=busy
//   0x08 HIT_CNT  read-only
//   0x0C MISS_CNT read-only
// ============================================================================

module icache #(
    parameter CACHE_SIZE = 2048,            // Cache size in bytes
    parameter LINE_SIZE  = 16              // Cache line size in bytes
)(
    input  wire        clk,
    input  wire        rst_n,

    // CPU interface
    input  wire [31:0] cpu_addr,
    output reg  [31:0] cpu_rdata,
    input  wire        cpu_re,
    output wire        cpu_hit,            // High when data is available (hit or refill done)
    output wire        cpu_stall,          // High when cache is fetching (CPU must hold PC)

    // Memory interface
    output reg  [31:0] mem_addr,
    input  wire [31:0] mem_rdata,
    output reg         mem_re,
    input  wire        mem_valid,

    // Bus interface (control registers)
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    output reg  [31:0] bus_rdata,
    input  wire        bus_we,
    input  wire        bus_re,

    // Status
    output wire        cache_busy
);

    // -------------------------------------------------------------------------
    // Derived parameters
    // -------------------------------------------------------------------------
    localparam LINES       = CACHE_SIZE / LINE_SIZE;
    localparam WORDS       = LINE_SIZE / 4;                // words per line
    localparam OFFSET_BITS = $clog2(LINE_SIZE);            // 4 for 16B
    localparam INDEX_BITS  = $clog2(LINES);                // 7 for 128 lines
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS; // 21 for default

    // Register base address
    localparam [31:0] REG_BASE = 32'h0000_9000;

    // Address field extraction macros
    wire [OFFSET_BITS-1:0] addr_offset = cpu_addr[OFFSET_BITS-1:0];
    wire [INDEX_BITS-1:0]  addr_index  = cpu_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0]    addr_tag    = cpu_addr[31:INDEX_BITS+OFFSET_BITS];

    // Word offset within a line (for word-aligned fetch)
    localparam WORD_OFFSET_BITS = $clog2(WORDS);
    wire [WORD_OFFSET_BITS-1:0] word_offset = addr_offset[OFFSET_BITS-1:2];

    // -------------------------------------------------------------------------
    // Cache storage
    // -------------------------------------------------------------------------
    // Valid bits
    reg                   valid_mem [0:LINES-1];

    // Tag storage
    reg [TAG_BITS-1:0]    tag_mem   [0:LINES-1];

    // Data storage (byte-addressed for simplicity)
    reg [7:0]             data_mem  [0:CACHE_SIZE-1];

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam [2:0]
        ST_IDLE    = 3'd0,
        ST_COMPARE = 3'd1,
        ST_FETCH   = 3'd2,
        ST_REFILL  = 3'd3;

    reg [2:0]              state, state_next;
    reg                    enabled;                     // Cache enable
    reg                    flush_req;                   // Flush request (pulse)
    reg                    flushing;                    // Flush in progress

    // Latched request info
    reg [31:0]             req_addr;
    reg [TAG_BITS-1:0]     req_tag;
    reg [INDEX_BITS-1:0]   req_index;
    reg [WORD_OFFSET_BITS-1:0] req_word_off;

    // Fetch counter
    reg [WORD_OFFSET_BITS-1:0] fetch_cnt;
    reg [31:0]             fetch_base_addr;             // Aligned base of cache line

    // Hit detection (combinational)
    wire                   line_valid = valid_mem[addr_index];
    wire                   tag_match  = (tag_mem[addr_index] == addr_tag);
    wire                   hit        = line_valid & tag_match;

    // Registered hit for latched address
    wire                   req_line_valid = valid_mem[req_index];
    wire                   req_tag_match  = (tag_mem[req_index] == req_tag);
    wire                   req_hit        = req_line_valid & req_tag_match;

    // -------------------------------------------------------------------------
    // Statistics counters
    // -------------------------------------------------------------------------
    reg [31:0]             hit_cnt;
    reg [31:0]             miss_cnt;

    // -------------------------------------------------------------------------
    // Flush logic
    // -------------------------------------------------------------------------
    reg [INDEX_BITS-1:0]   flush_idx;

    // -------------------------------------------------------------------------
    // CPU hit signal: asserted when cache has valid data for current request
    // -------------------------------------------------------------------------
    assign cpu_hit   = (state == ST_COMPARE) & hit |
                       (state == ST_REFILL) & (fetch_cnt == 0);

    // Stall CPU when cache miss is being handled (FETCH or miss in COMPARE)
    assign cpu_stall = enabled & ((state == ST_FETCH) |
                       ((state == ST_COMPARE) & ~hit));

    assign cache_busy = (state != ST_IDLE) | flushing;

    // -------------------------------------------------------------------------
    // Integer for initialization
    // -------------------------------------------------------------------------
    integer i;

    // =========================================================================
    // State register
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= state_next;
        end
    end

    // =========================================================================
    // Next-state logic & data output (combinational)
    // =========================================================================
    reg [31:0] cache_word;  // Word read from cache (combinational)

    always @(*) begin
        // Default: read the requested word from cache data memory
        cache_word = {data_mem[{req_index, req_word_off, 2'b00} + 3],
                      data_mem[{req_index, req_word_off, 2'b00} + 2],
                      data_mem[{req_index, req_word_off, 2'b00} + 1],
                      data_mem[{req_index, req_word_off, 2'b00}]};
    end

    always @(*) begin
        state_next = state;
        mem_addr   = 32'b0;
        mem_re     = 1'b0;
        cpu_rdata  = 32'b0;

        case (state)
            // ----------------------------------------------------------
            ST_IDLE: begin
                if (flushing) begin
                    state_next = ST_IDLE;  // Stay idle, flush runs in parallel
                end else if (cpu_re && enabled) begin
                    state_next = ST_COMPARE;
                end else if (cpu_re && !enabled) begin
                    // Bypass: pass-through to memory
                    mem_addr  = cpu_addr;
                    mem_re    = 1'b1;
                    cpu_rdata = mem_rdata;  // Pass memory data directly to CPU
                end
            end

            // ----------------------------------------------------------
            ST_COMPARE: begin
                if (req_hit) begin
                    cpu_rdata  = cache_word;
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_FETCH;
                end
            end

            // ----------------------------------------------------------
            ST_FETCH: begin
                mem_addr = fetch_base_addr + {fetch_cnt, 2'b00};
                mem_re   = 1'b1;
                if (mem_valid) begin
                    if (fetch_cnt == WORDS - 1) begin
                        state_next = ST_REFILL;
                    end
                end
            end

            // ----------------------------------------------------------
            ST_REFILL: begin
                cpu_rdata  = cache_word;
                state_next = ST_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Datapath: request latch, fetch, refill, flush, counters
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled      <= 1'b0;
            flush_req    <= 1'b0;
            flushing     <= 1'b0;
            flush_idx    <= {INDEX_BITS{1'b0}};
            fetch_cnt    <= {WORD_OFFSET_BITS{1'b0}};
            fetch_base_addr <= 32'b0;
            req_addr     <= 32'b0;
            req_tag      <= {TAG_BITS{1'b0}};
            req_index    <= {INDEX_BITS{1'b0}};
            req_word_off <= {WORD_OFFSET_BITS{1'b0}};
            hit_cnt      <= 32'b0;
            miss_cnt     <= 32'b0;

            for (i = 0; i < LINES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
            end
        end else begin
            // ----------------------------------------------------------
            // Flush logic (priority highest)
            // ----------------------------------------------------------
            if (flushing) begin
                valid_mem[flush_idx] <= 1'b0;
                if (flush_idx == LINES - 1) begin
                    flushing <= 1'b0;
                end
                flush_idx <= flush_idx + 1;
            end

            // Accept flush request from bus write (self-clearing pulse)
            if (flush_req) begin
                flushing  <= 1'b1;
                flush_idx <= {INDEX_BITS{1'b0}};
                flush_req <= 1'b0;
            end

            // ----------------------------------------------------------
            // State machine datapath
            // ----------------------------------------------------------
            case (state)
                ST_IDLE: begin
                    if (cpu_re && enabled && !flushing) begin
                        req_addr     <= cpu_addr;
                        req_tag      <= cpu_addr[31:INDEX_BITS+OFFSET_BITS];
                        req_index    <= cpu_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
                        req_word_off <= cpu_addr[OFFSET_BITS-1:2];
                        fetch_base_addr <= {cpu_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                        fetch_cnt       <= {WORD_OFFSET_BITS{1'b0}};
                    end
                end

                ST_COMPARE: begin
                    if (req_hit)
                        hit_cnt <= hit_cnt + 1;
                    else
                        miss_cnt <= miss_cnt + 1;
                end

                ST_FETCH: begin
                    if (mem_valid) begin
                        data_mem[{req_index, fetch_cnt, 2'b00}]     <= mem_rdata[7:0];
                        data_mem[{req_index, fetch_cnt, 2'b00} + 1] <= mem_rdata[15:8];
                        data_mem[{req_index, fetch_cnt, 2'b00} + 2] <= mem_rdata[23:16];
                        data_mem[{req_index, fetch_cnt, 2'b00} + 3] <= mem_rdata[31:24];
                        fetch_cnt <= fetch_cnt + 1;
                        if (fetch_cnt == WORDS - 1) begin
                            tag_mem[req_index]   <= req_tag;
                            valid_mem[req_index] <= 1'b1;
                        end
                    end
                end

                ST_REFILL: begin
                    // Data already in cache from FETCH stage
                end
            endcase

            // ----------------------------------------------------------
            // Bus write: control register
            // ----------------------------------------------------------
            if (bus_we && bus_addr[31:4] == REG_BASE[31:4]) begin
                if (bus_addr[3:0] == 4'h0) begin
                    enabled <= bus_wdata[0];
                    if (bus_wdata[1] && !flushing && !flush_req)
                        flush_req <= 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Bus interface: read-only registers at 0x0000_9000
    // =========================================================================

    always @(*) begin
        bus_rdata = 32'b0;
        if (bus_re && bus_addr[31:4] == REG_BASE[31:4]) begin
            case (bus_addr[3:0])
                4'h0: bus_rdata = {30'b0, flushing, enabled};   // CTRL
                4'h4: bus_rdata = {31'b0, cache_busy};          // STATUS
                4'h8: bus_rdata = hit_cnt;                       // HIT_CNT
                4'hC: bus_rdata = miss_cnt;                      // MISS_CNT
                default: bus_rdata = 32'b0;
            endcase
        end
    end

endmodule
