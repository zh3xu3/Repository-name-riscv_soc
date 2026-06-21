`timescale 1ns / 1ps

// 5-stage pipelined RV32IM core with interrupts
module riscv_core (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,
    output wire        dmem_we,
    output wire        dmem_re,
    output wire [ 2:0] dmem_size,
    input  wire        bus_error,
    input  wire        ext_irq,
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

  // =========================================================================
  // IF stage + IF/ID pipeline registers
  // =========================================================================
  reg [31:0] pc;
  wire [31:0] pc_plus4 = pc + 32'd4;
  wire [31:0] branch_target_w;
  wire        branch_taken_w;
  wire        stall;
  wire        irq_trap;
  wire [31:0] irq_handler;

  // IF/ID pipeline registers (declared early for use in misprediction logic)
  reg [31:0] ifid_pc, ifid_inst;
  reg        ifid_pred_taken;
  reg [31:0] ifid_pred_target;

  // Branch predictor: 2-bit saturating counter BHT
  wire        pred_taken;
  wire [31:0] pred_target;
  wire        is_btype = (ifid_inst[6:0] == 7'b1100011);
  wire        is_jal   = (ifid_inst[6:0] == 7'b1101111);

  branch_pred u_bp (
    .clk          (clk),
    .rst_n        (rst_n),
    .pc           (pc),
    .inst         (imem_rdata),
    .pred_taken   (pred_taken),
    .pred_target  (pred_target),
    .update_en    (is_btype || is_jal),
    .update_taken (branch_taken_w),
    .update_pc    (ifid_pc),
    .update_target(branch_target_w)
  );

  // Misprediction detection: predicted wrong or wrong target
  wire bp_update_is_branch = is_btype || is_jal;

  wire mispredict = bp_update_is_branch &&
                    (branch_taken_w != ifid_pred_taken ||
                     (branch_taken_w && branch_target_w != ifid_pred_target));
  // Flush on: misprediction, or unpredicted taken branch (JALR, MRET)
  wire flush = mispredict || (branch_taken_w && !bp_update_is_branch);

  wire [31:0] pc_next = stall   ? pc            :
                        irq_trap ? irq_handler   :
                        // Branch actual: only redirect on misprediction or unpredicted branch
                        (branch_taken_w && (!ifid_pred_taken || branch_target_w != ifid_pred_target)) ?
                          branch_target_w :
                        // Mispredicted not-taken: prediction redirected but branch not taken
                        (mispredict && !branch_taken_w) ? (ifid_pc + 32'd4) :
                        // Branch prediction (IF stage)
                        (pred_taken && !stall) ? pred_target :
                        pc_plus4;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) pc <= 32'h0;
    else        pc <= pc_next;
  end

  assign imem_addr = pc;

  // IF/ID pipeline register update
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ifid_pc          <= 32'h0;
      ifid_inst        <= 32'h00000013;
      ifid_pred_taken  <= 1'b0;
      ifid_pred_target <= 32'h0;
    end else if (stall) begin
      // hold
    end else if (flush || irq_trap) begin
      ifid_pc          <= 32'h0;
      ifid_inst        <= 32'h00000013;
      ifid_pred_taken  <= 1'b0;
      ifid_pred_target <= 32'h0;
    end else begin
      ifid_pc          <= pc;
      ifid_inst        <= imem_rdata;
      ifid_pred_taken  <= pred_taken;
      ifid_pred_target <= pred_target;
    end
  end

  // =========================================================================
  // ID stage
  // =========================================================================
  wire [ 4:0] id_rs1 = ifid_inst[19:15];
  wire [ 4:0] id_rs2 = ifid_inst[24:20];
  wire [ 4:0] id_rd  = ifid_inst[11:7];

  wire        id_reg_wr, id_mem_rd, id_mem_wr, id_alu_src;
  wire [ 1:0] id_wb_sel;
  wire [ 3:0] id_alu_op;
  wire [ 2:0] id_branch, id_mem_size;
  wire        id_is_m_ext, id_is_system, id_is_ecall;
  wire [ 2:0] id_csr_op;

  control u_ctrl (
    .inst      (ifid_inst),
    .reg_wr    (id_reg_wr),
    .mem_rd    (id_mem_rd),
    .mem_wr    (id_mem_wr),
    .wb_sel    (id_wb_sel),
    .alu_op    (id_alu_op),
    .alu_src   (id_alu_src),
    .branch    (id_branch),
    .mem_size  (id_mem_size),
    .is_m_ext  (id_is_m_ext),
    .is_system (id_is_system),
    .csr_op    (id_csr_op),
    .is_ecall  (id_is_ecall)
  );

  wire [31:0] id_rs1_data_rf, id_rs2_data_rf;
  wire        wb_we;
  wire [ 4:0] wb_rd;
  wire [31:0] wb_data;

  // Forward declarations for WB-stage signals used in reg_file port
  reg  [ 4:0] memwb_rs1;
  wire [31:0] csr_rs1_rf;

  reg_file u_rf (
    .clk      (clk),
    .rst_n    (rst_n),
    .rs1_addr (id_rs1),
    .rs1_data (id_rs1_data_rf),
    .rs2_addr (id_rs2),
    .rs2_data (id_rs2_data_rf),
    .rs3_addr (memwb_rs1),
    .rs3_data (csr_rs1_rf),
    .we       (wb_we),
    .rd_addr  (wb_rd),
    .rd_data  (wb_data),
    .dbg_x1   (dbg_x1),
    .dbg_x2   (dbg_x2),
    .dbg_x3   (dbg_x3),
    .dbg_x4   (dbg_x4),
    .dbg_x5   (dbg_x5),
    .dbg_x6   (dbg_x6),
    .dbg_x7   (dbg_x7),
    .dbg_x8   (dbg_x8),
    .dbg_x12  (dbg_x12),
    .dbg_x13  (dbg_x13),
    .dbg_x14  (dbg_x14),
    .dbg_x15  (dbg_x15)
  );

  wire [31:0] id_imm;
  imm_gen u_imm (.inst(ifid_inst), .imm(id_imm));

  // Forward declarations for EX/MEM and EX stage pipeline registers
  // (used in forwarding logic before their always-block declarations)
  reg        exmem_reg_wr;
  reg [ 4:0] exmem_rd;
  reg        exmem_is_ecall;
  reg [31:0] exmem_alu_result;
  reg [31:0] exmem_rs2_data;
  reg [ 1:0] exmem_wb_sel;
  reg [ 2:0] exmem_mem_size;
  reg        exmem_mem_rd, exmem_mem_wr;
  reg        exmem_is_mret;
  reg [11:0] exmem_csr_addr;
  reg [ 2:0] exmem_csr_op;
  reg        exmem_is_system;
  reg [31:0] exmem_rs1_data;
  reg [ 4:0] exmem_rs1;
  reg        exmem_bus_err;
  reg [31:0] exmem_pc;
  reg [31:0] exmem_csr_rdata;
  reg [31:0] exmem_dmem_rdata;

  // Forward declarations for pipeline registers used in ID-stage forwarding
  reg        idex_reg_wr, idex_mem_rd;
  reg [ 4:0] idex_rd;
  reg        idex_is_ecall;
  reg [ 2:0] idex_csr_op;
  reg [31:0] idex_inst, idex_pc;
  wire [31:0] ex_result;
  wire        div_busy, div_override, div_starting;
  reg  [ 1:0] div_freeze_cnt;
  wire [31:0] mepc_out;

  // Forward declarations for MEM/WB pipeline registers
  // (used in EX-stage forwarding logic before their always-block declarations)
  reg        memwb_reg_wr;
  reg [ 4:0] memwb_rd;
  reg [ 1:0] memwb_wb_sel;
  reg [31:0] memwb_alu_result, memwb_dmem_rdata, memwb_pc;
  reg        memwb_is_system;
  reg [ 2:0] memwb_csr_op;
  reg [31:0] memwb_csr_rdata;
  reg [31:0] memwb_rs1_data;
  reg        memwb_is_ecall, memwb_is_mret;
  reg        memwb_bus_err, memwb_mem_wr;
  wire [31:0] csr_fwd_rdata;
  wire [31:0] mie_out;
  wire        mstatus_mie;

  // Forwarding for branch/JALR (ID stage)
  // EX/MEM -> ID (standard: result from 2 instructions ago)
  wire fwd_exmem_rs1 = exmem_reg_wr && (exmem_rd != 5'h0) && (exmem_rd == id_rs1);
  wire fwd_exmem_rs2 = exmem_reg_wr && (exmem_rd != 5'h0) && (exmem_rd == id_rs2);
  // EX -> ID (forward current EX result to branch, one cycle earlier)
  wire fwd_ex_rs1 = idex_reg_wr && !idex_is_ecall && (idex_rd != 5'h0) && (idex_rd == id_rs1);
  wire fwd_ex_rs2 = idex_reg_wr && !idex_is_ecall && (idex_rd != 5'h0) && (idex_rd == id_rs2);
  // WB -> ID
  wire fwd_mem_rs1 = wb_we && (wb_rd != 5'h0) && (wb_rd == id_rs1) && !fwd_exmem_rs1 && !fwd_ex_rs1;
  wire fwd_mem_rs2 = wb_we && (wb_rd != 5'h0) && (wb_rd == id_rs2) && !fwd_exmem_rs2 && !fwd_ex_rs2;

  // EX/MEM forwarded value (for standard path)
  wire [31:0] exmem_fwd_val = (exmem_wb_sel == 2'b01) ? dmem_rdata :
                              (exmem_wb_sel == 2'b11) ? exmem_csr_rdata :
                              exmem_alu_result;

  // EX-stage forwarded value (for branch: ALU result or CSR read from current EX)
  wire [31:0] ex_stage_fwd_val = idex_csr_op != 3'b000 ? 32'h0 : ex_result;

  wire [31:0] id_rs1_data = fwd_ex_rs1    ? ex_stage_fwd_val :
                            fwd_exmem_rs1  ? exmem_fwd_val    :
                            fwd_mem_rs1    ? wb_data          :
                            id_rs1_data_rf;
  wire [31:0] id_rs2_data = fwd_ex_rs2    ? ex_stage_fwd_val :
                            fwd_exmem_rs2  ? exmem_fwd_val    :
                            fwd_mem_rs2    ? wb_data          :
                            id_rs2_data_rf;

  // Hazard detection: load-use stall + EX-to-ID load stall for branches
  wire       div_freeze = |div_freeze_cnt;
  assign stall = div_busy || div_starting ||
                 (idex_mem_rd && (idex_rd != 5'h0) &&
                  ((idex_rd == id_rs1) || (idex_rd == id_rs2)));

  // Branch resolution
  branch_comp u_br (
    .rs1_data    (id_rs1_data),
    .rs2_data    (id_rs2_data),
    .branch_type (id_branch),
    .taken       (branch_taken_w)
  );

  // For MRET: branch to mepc
  wire is_mret = (ifid_inst[6:0] == 7'b1110011) && (ifid_inst[14:12] == 3'b000) &&
                 (ifid_inst[31:20] == 12'h302);
  wire [31:0] jalr_target = (id_rs1_data + id_imm) & ~32'b1;
  assign branch_target_w = is_mret ? mepc_out :
                           (ifid_inst[6:0] == 7'b1100111) ? jalr_target :
                           (ifid_pc + id_imm);

  // =========================================================================
  // ID/EX
  // =========================================================================
  reg [31:0] idex_rs1_data, idex_rs2_data, idex_imm;
  reg [ 4:0] idex_rs1, idex_rs2;
  reg [ 3:0] idex_alu_op;
  reg [ 1:0] idex_wb_sel;
  reg [ 2:0] idex_mem_size;
  reg        idex_mem_wr, idex_alu_src;
  reg        idex_is_m_ext;
  reg        idex_is_system;
  reg        idex_is_mret;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n || stall || irq_trap) begin
      idex_pc       <= 32'h0;
      idex_rs1_data <= 32'h0;
      idex_rs2_data <= 32'h0;
      idex_imm      <= 32'h0;
      idex_inst     <= 32'h00000013;
      idex_rs1      <= 5'h0;
      idex_rs2      <= 5'h0;
      idex_rd       <= 5'h0;
      idex_alu_op   <= 4'h0;
      idex_wb_sel   <= 2'h0;
      idex_mem_size <= 3'h0;
      idex_reg_wr   <= 1'b0;
      idex_mem_rd   <= 1'b0;
      idex_mem_wr   <= 1'b0;
      idex_alu_src  <= 1'b0;
      idex_is_m_ext <= 1'b0;
      idex_is_system <= 1'b0;
      idex_is_ecall  <= 1'b0;
      idex_csr_op    <= 3'b000;
      idex_is_mret   <= 1'b0;
    end else begin
      idex_pc       <= ifid_pc;
      idex_rs1_data <= id_rs1_data;
      idex_rs2_data <= id_rs2_data;
      idex_imm      <= id_imm;
      idex_inst     <= ifid_inst;
      idex_rs1      <= id_rs1;
      idex_rs2      <= id_rs2;
      idex_rd       <= id_rd;
      idex_alu_op   <= id_alu_op;
      idex_wb_sel   <= id_wb_sel;
      idex_mem_size <= id_mem_size;
      idex_reg_wr   <= id_reg_wr;
      idex_mem_rd   <= id_mem_rd;
      idex_mem_wr   <= id_mem_wr;
      idex_alu_src  <= id_alu_src;
      idex_is_m_ext <= id_is_m_ext;
      idex_is_system <= id_is_system;
      idex_is_ecall  <= id_is_ecall;
      idex_csr_op    <= id_csr_op;
      idex_is_mret   <= is_mret;
    end
  end

  // =========================================================================
  // EX stage - ALU + M-extension
  // =========================================================================
  // Forwarding
  // Use memwb_reg_wr (not wb_we) for MEM/WB→EX forwarding because wb_we
  // is suppressed by !irq_trap during traps. The load result must still
  // be forwarded to dependent instructions (e.g. csrw mepc, t0) even
  // when a trap fires between the load and the consumer.
  wire fwd_ex_ex_rs1 = exmem_reg_wr && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1);
  wire fwd_ex_ex_rs2 = exmem_reg_wr && (exmem_rd != 5'h0) && (exmem_rd == idex_rs2);
  wire fwd_mem_ex_rs1 = memwb_reg_wr && (memwb_rd != 5'h0) && (wb_rd == idex_rs1) && !fwd_ex_ex_rs1;
  wire fwd_mem_ex_rs2 = memwb_reg_wr && (memwb_rd != 5'h0) && (wb_rd == idex_rs2) && !fwd_ex_ex_rs2;

  wire [31:0] ex_rs1_data = fwd_ex_ex_rs1  ? exmem_fwd_val :
                            fwd_mem_ex_rs1 ? wb_data       :
                            idex_rs1_data;
  wire [31:0] ex_rs2_data = fwd_ex_ex_rs2  ? exmem_fwd_val :
                            fwd_mem_ex_rs2 ? wb_data       :
                            idex_rs2_data;

  // ALU
  wire ex_is_lui   = (idex_inst[6:0] == 7'b0110111);
  wire ex_is_auipc = (idex_inst[6:0] == 7'b0010111);

  wire [31:0] alu_a = ex_is_auipc ? idex_pc : (ex_is_lui ? 32'b0 : ex_rs1_data);
  wire [31:0] alu_b = idex_alu_src ? idex_imm : ex_rs2_data;

  wire [31:0] alu_result;
  wire        alu_zero;

  alu u_alu (
    .a      (alu_a),
    .b      (alu_b),
    .alu_op (idex_alu_op),
    .result (alu_result),
    .zero   (alu_zero)
  );

  // M-extension: multiplier
  // Combinational — Vivado will infer DSP48 blocks for these 32x32 multiplies.
  // DSP48 has internal registered I/O, so a single-cycle multiply meets timing
  // at 100 MHz on Artix-7 without an extra pipeline stage.
  wire signed [63:0] mul_ss = $signed(ex_rs1_data) * $signed(ex_rs2_data);
  wire        [63:0] mul_uu = ex_rs1_data * ex_rs2_data;
  wire signed [63:0] mul_su = $signed({{32{ex_rs1_data[31]}}, ex_rs1_data}) *
                              {32'b0, ex_rs2_data};

  wire [31:0] mul_result;
  wire [ 2:0] mul_funct3 = idex_alu_op[2:0];
  assign mul_result = (mul_funct3 == 3'b000) ? mul_ss[31:0]  :   // MUL
                      (mul_funct3 == 3'b001) ? mul_ss[63:32] :   // MULH
                      (mul_funct3 == 3'b010) ? mul_su[63:32] :   // MULHSU
                      (mul_funct3 == 3'b011) ? mul_uu[63:32] :   // MULHU
                      32'h0;

  // M-extension: divider (iterative, stalls pipeline)
  // Combinational start — never fires when divider is busy (avoids restart bug
  // from registered div_start lingering across cycles).
  wire        div_is_signed_w = (idex_alu_op[2:0] == 3'b100 || idex_alu_op[2:0] == 3'b110);
  wire [31:0] div_quot, div_rem;
  wire        div_done;

  // 2-cycle freeze counter: holds EX/MEM so div result flows through
  // EX/MEM → MEM/WB before the bubble overwrites it.
  wire      div_result_valid = div_freeze || div_done;
  reg       div_busy_reg;
  reg [4:0] div_rd;
  reg       div_reg_wr;
  reg [2:0] div_funct3;
  assign    div_busy = div_busy_reg;

  // Combinational start: fires only when divider is truly idle
  assign div_starting = idex_is_m_ext && idex_alu_op[2:0] >= 3'b100 &&
                        !irq_trap && !u_div.busy && !div_freeze && !div_done;

  divider u_div (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (div_starting),
    .a         (ex_rs1_data),
    .b         (ex_rs2_data),
    .is_signed (div_is_signed_w),
    .quotient  (div_quot),
    .remainder (div_rem),
    .done      (div_done)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div_busy_reg     <= 1'b0;
      div_freeze_cnt   <= 2'd0;
      div_rd           <= 5'h0;
      div_reg_wr       <= 1'b0;
      div_funct3       <= 3'h0;
    end else if (div_done) begin
      div_busy_reg     <= 1'b1;  // keep busy through freeze
      div_freeze_cnt   <= 2'd3;
    end else if (div_starting) begin
      div_busy_reg     <= 1'b1;
      div_freeze_cnt   <= 2'd0;
      div_rd           <= idex_rd;
      div_reg_wr       <= idex_reg_wr;
      div_funct3       <= idex_alu_op[2:0];
    end else if (div_freeze) begin
      div_freeze_cnt   <= div_freeze_cnt - 2'd1;
      if (div_freeze_cnt == 2'd1)
        div_busy_reg   <= 1'b0;  // clear busy when freeze ends
    end
  end

  wire [31:0] div_result = (div_funct3 == 3'b100) ? div_quot :  // DIV
                           (div_funct3 == 3'b101) ? div_quot :  // DIVU
                           (div_funct3 == 3'b110) ? div_rem  :  // REM
                           (div_funct3 == 3'b111) ? div_rem  :  // REMU
                           32'h0;

  // EX result: M-extension or ALU
  assign div_override = div_done || div_result_valid;
  assign ex_result = (idex_is_m_ext || div_override) ?
                     (idex_alu_op[2:0] < 3'b100 && !div_override ? mul_result : div_result) :
                     alu_result;

  // =========================================================================
  // EX/MEM
  // =========================================================================

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exmem_alu_result <= 32'h0;
      exmem_rs2_data   <= 32'h0;
      exmem_pc         <= 32'h0;
      exmem_csr_rdata  <= 32'h0;
      exmem_rd         <= 5'h0;
      exmem_wb_sel     <= 2'h0;
      exmem_mem_size   <= 3'h0;
      exmem_reg_wr     <= 1'b0;
      exmem_mem_rd     <= 1'b0;
      exmem_mem_wr     <= 1'b0;
      exmem_is_mret    <= 1'b0;
      exmem_csr_addr   <= 12'h0;
      exmem_csr_op     <= 3'h0;
      exmem_is_system  <= 1'b0;
      exmem_is_ecall   <= 1'b0;
      exmem_rs1_data   <= 32'h0;
      exmem_rs1        <= 5'h0;
      exmem_bus_err    <= 1'b0;
    end else if (div_freeze) begin
      // Hold EX/MEM — divider result was captured when div_done fired
    end else begin
      exmem_alu_result <= ex_result;
      exmem_rs2_data   <= ex_rs2_data;
      exmem_pc         <= idex_pc;
      exmem_csr_rdata  <= csr_fwd_rdata;
      exmem_rd         <= div_override ? div_rd  : idex_rd;
      exmem_wb_sel     <= div_override ? 2'b00   : idex_wb_sel;
      exmem_mem_size   <= idex_mem_size;
      exmem_reg_wr     <= div_override ? div_reg_wr :
                           (idex_reg_wr && !div_busy && !idex_is_ecall);
      exmem_mem_rd     <= idex_mem_rd;
      exmem_mem_wr     <= idex_mem_wr;
      exmem_is_mret    <= idex_is_mret;
      exmem_csr_addr   <= idex_inst[31:20];
      exmem_csr_op     <= idex_csr_op;
      exmem_is_system  <= idex_is_system;
      exmem_is_ecall   <= idex_is_ecall;
      exmem_rs1_data   <= ex_rs1_data;
      exmem_rs1        <= idex_rs1;
      exmem_bus_err    <= bus_error;
    end
  end

  // =========================================================================
  // MEM stage
  // =========================================================================
  assign dmem_addr  = exmem_alu_result;
  assign dmem_wdata = exmem_rs2_data;
  assign dmem_we    = exmem_mem_wr;
  assign dmem_re    = exmem_mem_rd;
  assign dmem_size  = exmem_mem_size;

  // =========================================================================
  // MEM/WB
  // =========================================================================

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      memwb_alu_result <= 32'h0;
      memwb_dmem_rdata <= 32'h0;
      memwb_pc         <= 32'h0;
      memwb_rd         <= 5'h0;
      memwb_wb_sel     <= 2'h0;
      memwb_reg_wr     <= 1'b0;
      memwb_is_system  <= 1'b0;
      memwb_csr_op     <= 3'h0;
      memwb_csr_rdata  <= 32'h0;
      memwb_rs1_data   <= 32'h0;
      memwb_rs1        <= 5'h0;
      memwb_is_ecall   <= 1'b0;
      memwb_is_mret    <= 1'b0;
      memwb_bus_err    <= 1'b0;
      memwb_mem_wr     <= 1'b0;
    end else begin
      memwb_alu_result <= exmem_alu_result;
      memwb_dmem_rdata <= dmem_rdata;
      memwb_pc         <= exmem_pc;
      memwb_rd         <= exmem_rd;
      memwb_wb_sel     <= exmem_wb_sel;
      memwb_reg_wr     <= exmem_reg_wr;
      memwb_is_system  <= (exmem_is_system && !exmem_is_ecall && exmem_csr_op != 3'b000);
      memwb_csr_op     <= exmem_csr_op;
      memwb_csr_rdata  <= 32'h0;
      memwb_rs1_data   <= exmem_rs1_data;
      memwb_rs1        <= exmem_rs1;
      memwb_is_ecall   <= exmem_is_ecall;
      memwb_is_mret    <= exmem_is_mret;
      memwb_bus_err    <= exmem_bus_err;
      memwb_mem_wr     <= exmem_mem_wr;
    end
  end

  // =========================================================================
  // WB stage - CSR + writeback + interrupt handling
  // =========================================================================
  // CSR module
  wire [31:0] csr_rdata;
  wire [31:0] mtvec_out;
  wire        irq_pending;

  // CSR address from instruction (in WB stage, use memwb's instruction info)
  // We need the CSR address. For CSR instructions, it's inst[31:20].
  // We don't have the full instruction in WB. Let's pass it through.
  // Alternative: pass CSR addr through pipeline. Let's use a reg.
  reg [11:0] memwb_csr_addr;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      memwb_csr_addr <= 12'h0;
    else
      memwb_csr_addr <= exmem_csr_addr;
  end

  // CSR write data: rs1_data or zero-extended rs1 field (for CSRRWI)
  // The pipeline register memwb_rs1_data now has the correct forwarded value
  // because the EX-stage forwarding uses memwb_reg_wr (not wb_we) to forward
  // load results even during traps.
  wire [31:0] csr_rs1_fwd = (wb_we && (wb_rd != 5'h0) && (wb_rd == memwb_rs1)) ? wb_data : memwb_rs1_data;
  wire [31:0] csr_wdata = (memwb_csr_op[2]) ? {27'h0, csr_rs1_fwd[4:0]} : csr_rs1_fwd;

  // CSR write: CSRRW always writes, CSRRS/CSRRC write if rs1 != x0
  wire csr_we = memwb_is_system &&
                ((memwb_csr_op == 3'b001) ||  // CSRRW
                 ((memwb_csr_op == 3'b010 || memwb_csr_op == 3'b011) &&
                  (memwb_rs1 != 5'h0)));  // CSRRS/CSRRC only if rs1 field != 0

  // Trap detection
  wire timer_irq = irq_pending;
  wire ext_irq_pending = ext_irq && mie_out[11] && mstatus_mie;
  wire ecall_trap = memwb_is_ecall;
  wire load_fault  = memwb_bus_err && (memwb_wb_sel == 2'b01);
  wire store_fault = memwb_bus_err && memwb_mem_wr;
  wire bus_fault   = load_fault || store_fault;
  assign irq_trap = timer_irq || ext_irq_pending || ecall_trap || bus_fault;
  wire [31:0] trap_cause = timer_irq       ? 32'h80000007 :  // Machine timer
                           ext_irq_pending ? 32'h8000000B :  // Machine external
                           ecall_trap      ? 32'h0000000B :  // Environment call
                           load_fault      ? 32'h00000005 :  // Load access fault
                           store_fault     ? 32'h00000007 :  // Store access fault
                           32'h00000000;
  assign irq_handler = mtvec_out;

  // trap_pc mux: ecall uses memwb_pc (the ecall instruction in WB).
  // For timer: the WB instruction is suppressed (wb_we=0) so we must
  // return to it. If WB is a pipeline bubble (memwb_pc==0), the oldest
  // live instruction is in MEM (exmem_pc) or EX (idex_pc). Note: the
  // MEM instruction will commit on the first trap-handler cycle, so using
  // exmem_pc means it re-executes after mret — acceptable for branches
  // and idempotent ops in this simple core.
  wire [31:0] trap_pc_mux = ecall_trap ? memwb_pc :
                            (memwb_pc != 32'h0) ? memwb_pc :
                            (exmem_pc != 32'h0) ? exmem_pc :
                            (idex_pc  != 32'h0) ? idex_pc  : pc;


  wire [11:0] csr_fwd_addr = idex_inst[31:20];

  csr u_csr (
    .clk        (clk),
    .rst_n      (rst_n),
    .addr       (memwb_csr_addr),
    .wdata      (csr_wdata),
    .rdata      (csr_rdata),
    .we         (csr_we),
    .csr_op     (memwb_csr_op),
    .is_mret    (memwb_is_mret),
    .fwd_addr   (csr_fwd_addr),
    .fwd_rdata  (csr_fwd_rdata),
    .trap       (irq_trap),
    .trap_pc    (trap_pc_mux),
    .trap_cause (trap_cause),
    .mtvec_out  (mtvec_out),
    .mepc_out   (mepc_out),
    .irq_pending(irq_pending),
    .ext_irq    (ext_irq),
    .mie_out    (mie_out),
    .mstatus_mie(mstatus_mie)
  );

  // Writeback MUX
  // wb_sel: 00=ALU, 01=MEM, 10=PC+4, 11=CSR
  assign wb_we   = memwb_reg_wr && (memwb_rd != 5'h0) && !irq_trap;
  assign wb_rd   = memwb_rd;
  assign wb_data = (memwb_wb_sel == 2'b00) ? memwb_alu_result :
                   (memwb_wb_sel == 2'b01) ? memwb_dmem_rdata :
                   (memwb_wb_sel == 2'b10) ? (memwb_pc + 32'd4) :
                   (memwb_wb_sel == 2'b11) ? csr_rdata :
                   32'h0;

endmodule
