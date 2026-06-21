`timescale 1ns / 1ps
module tb_mext;
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;
  wire [31:0] dbg_x1, dbg_x2, dbg_x3, dbg_x4, dbg_x9, dbg_x10, dbg_x11, dbg_x12, dbg_x13, dbg_x14;
  soc_top u_dut (
    .clk(clk), .rst_n(rst_n),
    .uart_tx(), .uart_rx(1'b1),
    .gpio_o(), .gpio_i(32'h0), .gpio_dir(),
    .dbg_x1(dbg_x1), .dbg_x2(dbg_x2), .dbg_x3(dbg_x3), .dbg_x4(dbg_x4),
    .dbg_x5(), .dbg_x6(), .dbg_x7(), .dbg_x8(),
    .dbg_x12(dbg_x12), .dbg_x13(dbg_x13), .dbg_x14(dbg_x14), .dbg_x15()
  );
  always @(posedge clk) begin
    if (rst_n && u_dut.u_core.pc >= 32'h70 && u_dut.u_core.pc <= 32'h9C)
      $display("[%0t] PC=%08h inst=%08h | div_busy=%b div_done=%b div_start=%b | mext=%b alu_op=%04b | EXMEM: wr=%b rd=%0d | WB: we=%b rd=%0d data=%08h | x9=%08h x10=%08h x11=%08h x12=%08h x13=%08h x14=%08h",
        $time, u_dut.u_core.pc, u_dut.u_core.imem_rdata,
        u_dut.u_core.div_busy, u_dut.u_core.div_done, u_dut.u_core.div_start,
        u_dut.u_core.idex_is_m_ext, u_dut.u_core.idex_alu_op,
        u_dut.u_core.exmem_reg_wr, u_dut.u_core.exmem_rd,
        u_dut.u_core.wb_we, u_dut.u_core.wb_rd, u_dut.u_core.wb_data,
        dbg_x9, dbg_x10, dbg_x11, dbg_x12, dbg_x13, dbg_x14);
  end
  initial begin
    rst_n = 0; #25; rst_n = 1;
    #3000;
    $finish;
  end
endmodule
