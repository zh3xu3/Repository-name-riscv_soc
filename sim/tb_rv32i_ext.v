`timescale 1ns / 1ps

module tb_rv32i_ext;

  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  wire uart_tx_pin;
  wire uart_rx_pin = uart_tx_pin;
  wire [31:0] gpio_out;
  wire [31:0] gpio_in = gpio_out;
  wire [31:0] gpio_dir;

  soc_top #(
    .CLK_FREQ(100_000_000),
    .BAUD(115200)
  ) u_dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .uart_tx  (uart_tx_pin),
    .uart_rx  (uart_rx_pin),
    .gpio_o   (gpio_out),
    .gpio_i   (gpio_in),
    .gpio_dir (gpio_dir),
    .dbg_x1   (),
    .dbg_x2   (),
    .dbg_x3   (),
    .dbg_x4   (),
    .dbg_x5   (),
    .dbg_x6   (),
    .dbg_x7   (),
    .dbg_x8   (),
    .dbg_x12  (),
    .dbg_x13  (),
    .dbg_x14  (),
    .dbg_x15  ()
  );

  integer pass_count, fail_count;

  task check;
    input [31:0] actual;
    input [31:0] expected;
    input [8*30-1:0] name;
    begin
      if (actual === expected) begin
        $display("  PASS: 0x%08h  (%0s)", actual, name);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: got 0x%08h, expected 0x%08h  (%0s)", actual, expected, name);
        fail_count = fail_count + 1;
      end
    end
  endtask

  function [31:0] read_dmem;
    input [31:0] byte_offset;
    begin
      read_dmem = {u_dut.u_dmem.mem[byte_offset+3],
                   u_dut.u_dmem.mem[byte_offset+2],
                   u_dut.u_dmem.mem[byte_offset+1],
                   u_dut.u_dmem.mem[byte_offset]};
    end
  endfunction

  initial begin
    pass_count = 0;
    fail_count = 0;

    $display("");
    $display("===== Extended RV32I Instruction Tests =====");
    $display("");

    rst_n = 0;
    #25;
    rst_n = 1;

    // Wait for program to complete (halt loop at 0xF8)
    #50000;

    // Debug
    $display("  [DBG] x1=0x%08h x2=0x%08h x3=0x%08h x4=0x%08h x5=0x%08h x6=0x%08h",
             u_dut.u_core.u_rf.regs[1], u_dut.u_core.u_rf.regs[2],
             u_dut.u_core.u_rf.regs[3], u_dut.u_core.u_rf.regs[4],
             u_dut.u_core.u_rf.regs[5], u_dut.u_core.u_rf.regs[6]);
    $display("  [DBG] DMEM bytes[0..7] = %02h %02h %02h %02h %02h %02h %02h %02h",
             u_dut.u_dmem.mem[0], u_dut.u_dmem.mem[1],
             u_dut.u_dmem.mem[2], u_dut.u_dmem.mem[3],
             u_dut.u_dmem.mem[4], u_dut.u_dmem.mem[5],
             u_dut.u_dmem.mem[6], u_dut.u_dmem.mem[7]);

    $display("--- Shift Tests ---");
    check(read_dmem(32'h100), 32'h00000010, "SLL: 1 << 4 = 16");
    check(read_dmem(32'h104), 32'h08000000, "SRL: 0x80000000 >> 4");
    check(read_dmem(32'h108), 32'hF8000000, "SRA: 0x80000000 >>> 4");

    $display("");
    $display("--- SLT / SLTU Tests ---");
    check(read_dmem(32'h10C), 32'h00000001, "SLT(-1, 1) = 1 (signed)");
    check(read_dmem(32'h110), 32'h00000000, "SLTU(-1, 1) = 0 (unsigned)");

    $display("");
    $display("--- AUIPC / JALR Tests ---");
    check(read_dmem(32'h114), 32'h10000040, "AUIPC: PC(0x40) + 0x10000000");
    check(read_dmem(32'h118), 32'h0000004C, "JALR: return addr = PC+4");

    $display("");
    $display("--- Load/Store Byte/Half Tests ---");
    check(read_dmem(32'h11C), 32'hFFFFBEEF, "LH 0xBEEF sign-ext");
    check(read_dmem(32'h120), 32'h0000BEEF, "LHU 0xBEEF zero-ext");
    check(read_dmem(32'h124), 32'hFFFFFFEF, "LB 0xEF sign-ext");
    check(read_dmem(32'h128), 32'h000000EF, "LBU 0xEF zero-ext");
    check(read_dmem(32'h12C), 32'hDEADBEEF, "LW full word");

    $display("");
    $display("--- Branch Tests ---");
    check(read_dmem(32'h130), 32'h00000007, "All 7 branch tests passed");

    $display("");
    $display("===== Results: %0d PASS, %0d FAIL =====", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED!");
    else $display("SOME TESTS FAILED!");
    $display("");
    $finish;
  end

endmodule
