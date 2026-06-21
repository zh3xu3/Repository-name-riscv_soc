`timescale 1ns / 1ps
module tb_quick;
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;
  wire [31:0] dbg_x1, dbg_x2, dbg_x3, dbg_x4, dbg_x5, dbg_x6, dbg_x7, dbg_x8;
  wire [31:0] dbg_x12, dbg_x13, dbg_x14, dbg_x15;
  soc_top u_dut (
    .clk(clk), .rst_n(rst_n),
    .uart_tx(), .uart_rx(1'b1),
    .gpio_o(), .gpio_i(32'h0), .gpio_dir(),
    .dbg_x1(dbg_x1), .dbg_x2(dbg_x2), .dbg_x3(dbg_x3), .dbg_x4(dbg_x4),
    .dbg_x5(dbg_x5), .dbg_x6(dbg_x6), .dbg_x7(dbg_x7), .dbg_x8(dbg_x8),
    .dbg_x12(dbg_x12), .dbg_x13(dbg_x13), .dbg_x14(dbg_x14), .dbg_x15(dbg_x15)
  );
  always @(posedge clk) begin
    if (rst_n)
      $display("[%0t] PC=%08h inst=%08h | x1=%08h x3=%08h | stall=%b flush=%b irq=%b div_busy=%b div_done=%b",
        $time, u_dut.u_core.pc, u_dut.u_core.imem_rdata,
        dbg_x1, dbg_x3,
        u_dut.u_core.stall, u_dut.u_core.flush,
        u_dut.u_core.irq_trap, u_dut.u_core.div_busy, u_dut.u_core.div_done);
  end
  initial begin
    rst_n = 0; #25; rst_n = 1;
    #200;
    $finish;
  end
endmodule
