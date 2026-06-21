`timescale 1ns / 1ps

// Branch Predictor: 2-bit saturating counter BHT + BTB
// Predicts in IF stage using instruction bits directly
// Supports: BEQ/BNE/BLT/BGE/BLTU/BGEU (B-type) and JAL (J-type)
module branch_pred #(
    parameter BHT_SIZE = 64   // Number of BHT entries (power of 2)
)(
    input  wire        clk,
    input  wire        rst_n,
    // IF stage inputs
    input  wire [31:0] pc,
    input  wire [31:0] inst,          // instruction from IMEM (combinational read)
    // Prediction output (IF stage)
    output wire        pred_taken,
    output wire [31:0] pred_target,
    // Update from ID stage
    input  wire        update_en,     // branch/jal resolved in ID
    input  wire        update_taken,  // actual branch outcome
    input  wire [31:0] update_pc,     // PC of the branch instruction
    input  wire [31:0] update_target  // actual target address
);

  localparam IDX_W = $clog2(BHT_SIZE);

  // 2-bit saturating counter: 00=strongly_NT, 01=weakly_NT, 10=weakly_T, 11=strongly_T
  reg [1:0] bht [0:BHT_SIZE-1];

  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < BHT_SIZE; i = i + 1)
        bht[i] <= 2'b01;  // weakly not-taken
    end else if (update_en) begin
      if (update_taken) begin
        if (bht[update_pc[IDX_W+1:2]] != 2'b11)
          bht[update_pc[IDX_W+1:2]] <= bht[update_pc[IDX_W+1:2]] + 2'd1;
      end else begin
        if (bht[update_pc[IDX_W+1:2]] != 2'b00)
          bht[update_pc[IDX_W+1:2]] <= bht[update_pc[IDX_W+1:2]] - 2'd1;
      end
    end
  end

  // Instruction decode
  wire [6:0] opcode = inst[6:0];
  wire is_btype = (opcode == 7'b1100011);  // Branch
  wire is_jal   = (opcode == 7'b1101111);  // JAL

  // B-type immediate: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
  wire [31:0] b_imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};

  // JAL immediate: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
  wire [31:0] j_imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};

  // Prediction logic
  wire [1:0] counter = bht[pc[IDX_W+1:2]];
  wire predict_branch = is_btype && counter[1];  // predict taken if >= 2
  wire predict_jal    = is_jal;

  assign pred_taken  = predict_branch || predict_jal;
  assign pred_target = predict_jal ? (pc + j_imm) :
                       predict_branch ? (pc + b_imm) :
                       32'h0;

endmodule
