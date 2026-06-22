`timescale 1ns / 1ps

// DMA Controller - Simple memory/peripheral transfer engine
// Register map (word-aligned, 0x0000_8000 - 0x0000_801F):
//   0x00: CTRL      (RW: [0]=start, [2:1]=dir, [4:3]=width, [5]=irq_en)
//   0x04: SRC_ADDR  (RW: source address)
//   0x08: DST_ADDR  (RW: destination address)
//   0x0C: TRANS_LEN (RW: transfer length in bytes)
//   0x10: STATUS    (RW1C: [0]=busy, [1]=done, [2]=error)
//   0x14: IRQ_EN    (RW: interrupt enable)
module dma (
    input  wire        clk,
    input  wire        rst_n,
    // Bus interface (slave)
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    output reg  [31:0] bus_rdata,
    input  wire        bus_we,
    input  wire        bus_re,
    // Memory master interface (to data_mem)
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    input  wire [31:0] mem_rdata,
    output reg         mem_we,
    output reg         mem_re,
    // Interrupt
    output wire        dma_irq
);

  // State encoding
  localparam IDLE  = 2'd0;
  localparam FETCH = 2'd1;
  localparam WRITE = 2'd2;
  localparam DONE  = 2'd3;

  // Transfer direction encoding
  localparam DIR_MEM2MEM    = 2'b00;
  localparam DIR_PERIPH2MEM = 2'b01;
  localparam DIR_MEM2PERIPH = 2'b10;

  // Register storage
  reg        ctrl_start;
  reg [1:0]  ctrl_dir;
  reg [1:0]  ctrl_width;
  reg [31:0] src_addr;
  reg [31:0] dst_addr;
  reg [31:0] trans_len;
  reg        irq_en;

  // Status flags
  reg        status_busy;
  reg        status_done;
  reg        status_error;

  // State machine
  reg [1:0]  state;
  reg [31:0] bytes_remaining;
  reg [31:0] cur_src;
  reg [31:0] cur_dst;
  reg [31:0] fetch_data;

  // Byte enable from width
  wire [3:0] be_mask = (ctrl_width == 2'd0) ? 4'b0001 :  // byte
                        (ctrl_width == 2'd1) ? 4'b0011 :  // half
                                               4'b1111;   // word

  wire [1:0] size_shift = (ctrl_width == 2'd0) ? 2'd1 :  // 1 byte
                           (ctrl_width == 2'd1) ? 2'd2 :  // 2 bytes
                                                  2'd4;   // 4 bytes

  // ---- Bus register write ----
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_start <= 1'b0;
      ctrl_dir   <= 2'b00;
      ctrl_width <= 2'b00;
      src_addr   <= 32'h0;
      dst_addr   <= 32'h0;
      trans_len  <= 32'h0;
      irq_en     <= 1'b0;
    end else begin
      // Auto-clear start after one cycle
      if (ctrl_start)
        ctrl_start <= 1'b0;

      if (bus_we) begin
        case (bus_addr[4:2])
          3'b000: begin // CTRL
            ctrl_start <= bus_wdata[0];
            ctrl_dir   <= bus_wdata[2:1];
            ctrl_width <= bus_wdata[4:3];
            irq_en     <= bus_wdata[5];
          end
          3'b001: src_addr  <= bus_wdata;
          3'b010: dst_addr  <= bus_wdata;
          3'b011: trans_len <= bus_wdata;
          3'b100: begin // STATUS - write 1 to clear done and error
            if (bus_wdata[1]) status_done  <= 1'b0;
            if (bus_wdata[2]) status_error <= 1'b0;
          end
          3'b101: irq_en <= bus_wdata[0];
          default: ;
        endcase
      end
    end
  end

  // ---- Bus register read ----
  always @(*) begin
    if (!bus_re)
      bus_rdata = 32'h0;
    else begin
      case (bus_addr[4:2])
        3'b000: bus_rdata = {26'h0, irq_en, ctrl_width, ctrl_dir, ctrl_start};
        3'b001: bus_rdata = src_addr;
        3'b010: bus_rdata = dst_addr;
        3'b011: bus_rdata = trans_len;
        3'b100: bus_rdata = {29'h0, status_error, status_done, status_busy};
        3'b101: bus_rdata = {31'h0, irq_en};
        default: bus_rdata = 32'h0;
      endcase
    end
  end

  // ---- DMA state machine ----
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state           <= IDLE;
      status_busy     <= 1'b0;
      status_done     <= 1'b0;
      status_error    <= 1'b0;
      bytes_remaining <= 32'h0;
      cur_src         <= 32'h0;
      cur_dst         <= 32'h0;
      fetch_data      <= 32'h0;
      mem_addr        <= 32'h0;
      mem_wdata       <= 32'h0;
      mem_we          <= 1'b0;
      mem_re          <= 1'b0;
    end else begin
      // Default: deassert memory signals
      mem_we <= 1'b0;
      mem_re <= 1'b0;

      case (state)
        IDLE: begin
          if (ctrl_start && trans_len != 32'h0) begin
            status_busy     <= 1'b1;
            status_done     <= 1'b0;
            status_error    <= 1'b0;
            bytes_remaining <= trans_len;
            cur_src         <= src_addr;
            cur_dst         <= dst_addr;
            state           <= FETCH;
          end
        end

        FETCH: begin
          // Issue read from source
          mem_addr <= cur_src;
          mem_re   <= 1'b1;
          // Move to WRITE next cycle (mem_rdata available)
          state    <= WRITE;
        end

        WRITE: begin
          // Latch fetched data and write to destination
          fetch_data <= mem_rdata;
          mem_addr   <= cur_dst;
          mem_wdata  <= mem_rdata;
          mem_we     <= 1'b1;

          // Advance pointers
          cur_src         <= cur_src + {30'h0, size_shift};
          cur_dst         <= cur_dst + {30'h0, size_shift};
          bytes_remaining <= bytes_remaining - {30'h0, size_shift};

          // Check completion
          if (bytes_remaining <= {30'h0, size_shift}) begin
            state <= DONE;
          end else begin
            state <= FETCH;
          end
        end

        DONE: begin
          status_busy <= 1'b0;
          status_done <= 1'b1;
          state       <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

  // Interrupt output: done flag AND interrupt enable
  assign dma_irq = status_done & irq_en;

endmodule
