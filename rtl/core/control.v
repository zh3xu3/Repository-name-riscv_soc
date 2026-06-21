`timescale 1ns / 1ps

module control (
    input  wire [31:0] inst,
    output reg         reg_wr,
    output reg         mem_rd,
    output reg         mem_wr,
    output reg  [ 1:0] wb_sel,
    output reg  [ 3:0] alu_op,
    output reg         alu_src,
    output reg  [ 2:0] branch,
    output reg  [ 2:0] mem_size,
    // M-extension
    output reg         is_m_ext,
    // CSR
    output reg         is_system,  // SYSTEM opcode
    output reg  [ 2:0] csr_op,     // CSR operation (funct3)
    output reg         is_ecall    // ECALL instruction
);

  wire [6:0] opcode = inst[6:0];
  wire [2:0] funct3 = inst[14:12];
  wire [6:0] funct7 = inst[31:25];

  // ALU op: {funct7[5], funct3}
  wire [3:0] alu_op_r  = {funct7[5], funct3};
  wire [3:0] alu_op_i  = {(funct3 == 3'b101 ? funct7[5] : 1'b0), funct3};

  always @(*) begin
    reg_wr    = 1'b0;
    mem_rd    = 1'b0;
    mem_wr    = 1'b0;
    wb_sel    = 2'b00;
    alu_op    = 4'b0000;
    alu_src   = 1'b0;
    branch    = 3'b000;
    mem_size  = 3'b010;
    is_m_ext  = 1'b0;
    is_system = 1'b0;
    csr_op    = 3'b000;
    is_ecall  = 1'b0;

    case (opcode)
      7'b0110011: begin  // R-type (including M-extension)
        if (funct7 == 7'b0000001) begin
          // M-extension: MUL/DIV/REM
          is_m_ext = 1'b1;
          reg_wr   = 1'b1;
          alu_op   = {1'b1, funct3};  // Mark as M-ext with bit 3
        end else begin
          // Normal R-type
          reg_wr  = 1'b1;
          alu_op  = alu_op_r;
          alu_src = 1'b0;
        end
      end

      7'b0010011: begin  // I-type arithmetic
        reg_wr  = 1'b1;
        alu_op  = alu_op_i;
        alu_src = 1'b1;
      end

      7'b0000011: begin  // Load
        reg_wr   = 1'b1;
        mem_rd   = 1'b1;
        wb_sel   = 2'b01;
        alu_op   = 4'b0000;
        alu_src  = 1'b1;
        mem_size = funct3;
      end

      7'b0100011: begin  // Store
        mem_wr   = 1'b1;
        alu_op   = 4'b0000;
        alu_src  = 1'b1;
        mem_size = funct3;
      end

      7'b1100011: begin  // Branch
        alu_op  = 4'b0000;
        alu_src = 1'b0;
        case (funct3)
          3'b000: branch = 3'b001;  // BEQ
          3'b001: branch = 3'b010;  // BNE
          3'b100: branch = 3'b011;  // BLT
          3'b101: branch = 3'b100;  // BGE
          3'b110: branch = 3'b101;  // BLTU
          3'b111: branch = 3'b110;  // BGEU
          default: branch = 3'b000;
        endcase
      end

      7'b1101111: begin  // JAL
        reg_wr = 1'b1;
        wb_sel = 2'b10;
        branch = 3'b111;
      end

      7'b1100111: begin  // JALR
        reg_wr  = 1'b1;
        wb_sel  = 2'b10;
        alu_op  = 4'b0000;
        alu_src = 1'b1;
        branch  = 3'b111;
      end

      7'b0110111: begin  // LUI
        reg_wr  = 1'b1;
        alu_src = 1'b1;
        alu_op  = 4'b0000;
      end

      7'b0010111: begin  // AUIPC
        reg_wr  = 1'b1;
        alu_src = 1'b1;
        alu_op  = 4'b0000;
      end

      7'b1110011: begin  // SYSTEM (ECALL, CSR)
        is_system = 1'b1;
        if (funct3 == 3'b000) begin
          // ECALL (inst[31:20]=000000000000) or MRET (inst[31:20]=001100000010)
          if (inst[21] == 1'b0) begin
            // ECALL
            is_ecall = 1'b1;
          end
          // MRET is handled separately (just sets branch)
          if (inst[31:20] == 12'h302) begin
            // MRET: return from trap
            branch = 3'b111;  // unconditional jump to mepc
          end
        end else begin
          // CSR instructions: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
          reg_wr = 1'b1;
          wb_sel = 2'b11;  // CSR read value
          csr_op = funct3;
        end
      end

      default: begin
        // NOP
      end
    endcase
  end

endmodule
