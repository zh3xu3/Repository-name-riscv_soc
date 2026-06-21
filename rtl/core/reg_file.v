`timescale 1ns / 1ps

module reg_file (
    input  wire        clk,
    input  wire        rst_n,
    // Read port 1 (rs1)
    input  wire [ 4:0] rs1_addr,
    output wire [31:0] rs1_data,
    // Read port 2 (rs2)
    input  wire [ 4:0] rs2_addr,
    output wire [31:0] rs2_data,
    // Read port 3 (CSR rs1 — async, for CSR write data)
    input  wire [ 4:0] rs3_addr,
    output wire [31:0] rs3_data,
    // Write port (rd)
    input  wire        we,
    input  wire [ 4:0] rd_addr,
    input  wire [31:0] rd_data,
    // Debug port
    output wire [31:0] dbg_x1,
    output wire [31:0] dbg_x2,
    output wire [31:0] dbg_x3,
    output wire [31:0] dbg_x4,
    output wire [31:0] dbg_x5,
    output wire [31:0] dbg_x6,
    output wire [31:0] dbg_x7,
    output wire [31:0] dbg_x8,
    output wire [31:0] dbg_x12,
    output wire [31:0] dbg_x13,
    output wire [31:0] dbg_x14,
    output wire [31:0] dbg_x15
);

  reg [31:0] regs [0:31];
  integer i;

  // Async read with write-through: if reading the same register being written
  // this cycle, forward the write data instead of the stale stored value.
  assign rs1_data = (rs1_addr == 5'b0)                    ? 32'b0 :
                    (we && rd_addr != 5'b0 && rd_addr == rs1_addr) ? rd_data :
                    regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'b0)                    ? 32'b0 :
                    (we && rd_addr != 5'b0 && rd_addr == rs2_addr) ? rd_data :
                    regs[rs2_addr];
  assign rs3_data = (rs3_addr == 5'b0)                    ? 32'b0 :
                    (we && rd_addr != 5'b0 && rd_addr == rs3_addr) ? rd_data :
                    regs[rs3_addr];

  // Debug outputs
  assign dbg_x1  = regs[1];
  assign dbg_x2  = regs[2];
  assign dbg_x3  = regs[3];
  assign dbg_x4  = regs[4];
  assign dbg_x5  = regs[5];
  assign dbg_x6  = regs[6];
  assign dbg_x7  = regs[7];
  assign dbg_x8  = regs[8];
  assign dbg_x12 = regs[12];
  assign dbg_x13 = regs[13];
  assign dbg_x14 = regs[14];
  assign dbg_x15 = regs[15];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 32; i = i + 1)
        regs[i] <= 32'b0;
    end else if (we && rd_addr != 5'b0) begin
      regs[rd_addr] <= rd_data;
    end
  end

endmodule
