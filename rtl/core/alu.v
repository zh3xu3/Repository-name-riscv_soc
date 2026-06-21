`timescale 1ns / 1ps

module alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [ 3:0] alu_op,
    output reg  [31:0] result,
    output wire        zero
);

  // ALU operation encoding = {funct7[5], funct3}
  // This matches what control.v generates directly
  localparam ALU_ADD  = 4'b0000;  // funct3=000, R-type funct7=0
  localparam ALU_SLL  = 4'b0001;  // funct3=001
  localparam ALU_SLT  = 4'b0010;  // funct3=010
  localparam ALU_SLTU = 4'b0011;  // funct3=011
  localparam ALU_XOR  = 4'b0100;  // funct3=100
  localparam ALU_SRL  = 4'b0101;  // funct3=101, funct7=0
  localparam ALU_OR   = 4'b0110;  // funct3=110
  localparam ALU_AND  = 4'b0111;  // funct3=111
  localparam ALU_SUB  = 4'b1000;  // funct3=000, funct7=1
  localparam ALU_SRA  = 4'b1101;  // funct3=101, funct7=1

  assign zero = (result == 32'b0);

  always @(*) begin
    case (alu_op)
      ALU_ADD:  result = a + b;
      ALU_SUB:  result = a - b;
      ALU_SLL:  result = a << b[4:0];
      ALU_SLT:  result = {31'b0, $signed(a) < $signed(b)};
      ALU_SLTU: result = {31'b0, a < b};
      ALU_XOR:  result = a ^ b;
      ALU_SRL:  result = a >> b[4:0];
      ALU_SRA:  result = $signed(a) >>> b[4:0];
      ALU_OR:   result = a | b;
      ALU_AND:  result = a & b;
      default:  result = 32'b0;
    endcase
  end

endmodule
