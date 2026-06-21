`timescale 1ns / 1ps

// CSR register file + CLINT for RV32IM
module csr (
    input  wire        clk,
    input  wire        rst_n,
    // CSR access (write port + WB-stage read)
    input  wire [11:0] addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire [ 2:0] csr_op,    // 001=CSRRW, 010=CSRRS, 011=CSRRC
    input  wire        is_mret,   // MRET instruction executed
    // Forwarding read port (EX-stage address, for pipeline forwarding)
    input  wire [11:0] fwd_addr,
    output reg  [31:0] fwd_rdata,
    // Trap interface
    input  wire        trap,       // trap taken this cycle
    input  wire [31:0] trap_pc,    // PC of trapping instruction
    input  wire [31:0] trap_cause, // cause code
    output wire [31:0] mtvec_out,  // handler address
    output wire [31:0] mepc_out,   // return address
    // Interrupt status
    output wire        irq_pending, // interrupt pending
    // External interrupt input (active-high, from PLIC)
    input  wire        ext_irq,
    // MIE output (for core to check specific enable bits)
    output wire [31:0] mie_out,
    // mstatus.MIE output
    output wire        mstatus_mie
);

  // CSR registers
  reg [31:0] mstatus;  // Machine status
  reg [31:0] mtvec;    // Trap vector base
  reg [31:0] mepc;     // Exception PC
  reg [31:0] mcause;   // Trap cause
  reg [31:0] mie;      // Interrupt enable
  reg [31:0] mip;      // Interrupt pending
  reg [31:0] mscratch; // Scratch register

  // CLINT registers
  reg [63:0] mtime;     // Current time
  reg [63:0] mtimecmp;  // Timer compare

  // CSR addresses
  localparam CSR_MSTATUS  = 12'h300;
  localparam CSR_MIE      = 12'h304;
  localparam CSR_MTVEC    = 12'h305;
  localparam CSR_MSCRATCH = 12'h340;
  localparam CSR_MEPC     = 12'h341;
  localparam CSR_MCAUSE   = 12'h342;
  localparam CSR_MIP      = 12'h344;
  localparam CSR_MCYCLE   = 12'hB00;
  localparam CSR_MTIMECMP_LO = 12'hB02;
  localparam CSR_MTIMECMP_HI = 12'hB03;
  localparam CSR_MTIME    = 12'hC01;

  // Interrupt cause codes
  localparam CAUSE_MTIMER = 32'h80000007;  // Machine timer
  localparam CAUSE_MSW    = 32'h80000003;  // Machine software

  // Timer: increment mtime, set mip.MTIP on compare
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mtime    <= 64'h0;
      mtimecmp <= 64'hFFFFFFFF_FFFFFFFF;  // No interrupt by default
    end else begin
      mtime <= mtime + 1;
      if (mtime >= mtimecmp)
        mip[7] <= 1'b1;  // MTIP
      else if (trap && trap_cause == CAUSE_MTIMER)
        mip[7] <= 1'b0;  // Clear on trap entry
    end
  end

  // External interrupt: set/clear MIP[11] (MEIP)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mip[11] <= 1'b0;
    else
      mip[11] <= ext_irq;
  end

  // Interrupt pending: timer, software, or external interrupt
  assign irq_pending = mstatus[3] &&  // MIE
                       ((mie[7] && mip[7]) ||    // Timer
                        (mie[3] && mip[3]) ||    // Software
                        (mie[11] && mip[11]));   // External

  // Trap handler address
  assign mtvec_out = mtvec;
  assign mepc_out  = mepc;
  assign mie_out     = mie;
  assign mstatus_mie = mstatus[3];

  // CSR read (WB stage)
  always @(*) begin
    case (addr)
      CSR_MSTATUS:  rdata = mstatus;
      CSR_MIE:      rdata = mie;
      CSR_MTVEC:    rdata = mtvec;
      CSR_MSCRATCH: rdata = mscratch;
      CSR_MEPC:     rdata = mepc;
      CSR_MCAUSE:   rdata = mcause;
      CSR_MIP:      rdata = mip;
      CSR_MCYCLE:      rdata = mtime[31:0];
      CSR_MTIMECMP_LO: rdata = mtimecmp[31:0];
      CSR_MTIMECMP_HI: rdata = mtimecmp[63:32];
      CSR_MTIME:       rdata = mtime[31:0];
      default:      rdata = 32'h0;
    endcase
  end

  // CSR forwarding read (EX stage — combinational, for pipeline forwarding)
  always @(*) begin
    case (fwd_addr)
      CSR_MSTATUS:  fwd_rdata = mstatus;
      CSR_MIE:      fwd_rdata = mie;
      CSR_MTVEC:    fwd_rdata = mtvec;
      CSR_MSCRATCH: fwd_rdata = mscratch;
      CSR_MEPC:     fwd_rdata = mepc;
      CSR_MCAUSE:   fwd_rdata = mcause;
      CSR_MIP:      fwd_rdata = mip;
      CSR_MCYCLE:      fwd_rdata = mtime[31:0];
      CSR_MTIMECMP_LO: fwd_rdata = mtimecmp[31:0];
      CSR_MTIMECMP_HI: fwd_rdata = mtimecmp[63:32];
      CSR_MTIME:       fwd_rdata = mtime[31:0];
      default:      fwd_rdata = 32'h0;
    endcase
  end

  // CSR write + trap entry + MRET
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus  <= 32'h0;
      mtvec    <= 32'h0;
      mepc     <= 32'h0;
      mcause   <= 32'h0;
      mie      <= 32'h0;
      mip      <= 32'h0;
      mscratch <= 32'h0;
    end else if (trap) begin
      // Trap entry: save context, disable interrupts
      mepc    <= trap_pc;
      mcause  <= trap_cause;
      mstatus[7] <= mstatus[3];  // MPIE = old MIE
      mstatus[3] <= 1'b0;        // Clear MIE
    end else if (is_mret) begin
      // MRET: restore MIE from MPIE, set MPIE=1
      mstatus[3] <= mstatus[7];  // MIE = MPIE
      mstatus[7] <= 1'b1;        // MPIE = 1
    end else if (we) begin
      case (addr)
        CSR_MSTATUS: begin
          case (csr_op)
            3'b001:  mstatus <= wdata;              // CSRRW
            3'b010:  mstatus <= rdata | wdata;      // CSRRS: set bits
            3'b011:  mstatus <= rdata & ~wdata;     // CSRRC: clear bits
            default: mstatus <= wdata;
          endcase
        end
        CSR_MIE:         mie      <= wdata;
        CSR_MTVEC:       mtvec    <= wdata;
        CSR_MSCRATCH:    mscratch <= wdata;
        CSR_MEPC:        mepc     <= wdata;
        CSR_MCAUSE:      mcause   <= wdata;
        CSR_MTIMECMP_LO: mtimecmp[31:0]  <= wdata;
        CSR_MTIMECMP_HI: mtimecmp[63:32] <= wdata;
        default: ;
      endcase
    end
  end

endmodule
