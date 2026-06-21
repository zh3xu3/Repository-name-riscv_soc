`timescale 1ns / 1ps

module branch_comp (
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [ 2:0] branch_type,
    output reg         taken
);

  // Branch type encoding
  localparam BR_NONE = 3'b000;
  localparam BR_BEQ  = 3'b001;
  localparam BR_BNE  = 3'b010;
  localparam BR_BLT  = 3'b011;
  localparam BR_BGE  = 3'b100;
  localparam BR_BLTU = 3'b101;
  localparam BR_BGEU = 3'b110;
  localparam BR_JMP  = 3'b111;

  always @(*) begin
    case (branch_type)
      BR_BEQ:  taken = (rs1_data == rs2_data);
      BR_BNE:  taken = (rs1_data != rs2_data);
      BR_BLT:  taken = ($signed(rs1_data) < $signed(rs2_data));
      BR_BGE:  taken = ($signed(rs1_data) >= $signed(rs2_data));
      BR_BLTU: taken = (rs1_data < rs2_data);
      BR_BGEU: taken = (rs1_data >= rs2_data);
      BR_JMP:  taken = 1'b1;
      default: taken = 1'b0;
    endcase
  end

endmodule
