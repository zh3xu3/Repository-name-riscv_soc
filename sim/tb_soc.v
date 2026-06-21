`timescale 1ns / 1ps

module tb_soc;

  // ================================================================
  // Clock & Reset
  // ================================================================
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;  // 100MHz

  // ================================================================
  // Signals
  // ================================================================
  wire [31:0] dbg_x1, dbg_x2, dbg_x3, dbg_x4;
  wire [31:0] dbg_x5, dbg_x6, dbg_x7, dbg_x8;
  wire [31:0] dbg_x12, dbg_x13, dbg_x14, dbg_x15;

  // UART loopback
  wire uart_tx_pin;
  wire uart_rx_pin = uart_tx_pin;

  // GPIO loopback
  wire [31:0] gpio_out;
  wire [31:0] gpio_in = gpio_out;
  wire [31:0] gpio_dir;

  // SPI loopback
  wire spi_sck_pin, spi_mosi_pin, spi_cs_n_pin;
  wire spi_miso_pin = spi_mosi_pin;

  // PWM
  wire [3:0] pwm_out_pin;

  // ================================================================
  // DUT
  // ================================================================
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
    .spi_sck  (spi_sck_pin),
    .spi_mosi (spi_mosi_pin),
    .spi_miso (spi_miso_pin),
    .spi_cs_n (spi_cs_n_pin),
    .pwm_out  (pwm_out_pin),
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

  // ================================================================
  // VCD Dump (for waveform analysis)
  // ================================================================
  initial begin
    $dumpfile("tb_soc.vcd");
    $dumpvars(0, tb_soc);
  end

  // ================================================================
  // Performance Counter
  // ================================================================
  reg [63:0] cycle_count;
  reg [63:0] sim_start_time;

  always @(posedge clk) begin
    if (!rst_n)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;
  end

  // ================================================================
  // Test Infrastructure
  // ================================================================
  integer pass_count, fail_count;

  task check;
    input [31:0] actual;
    input [31:0] expected;
    input [8*40-1:0] name;
    begin
      if (actual === expected) begin
        $display("  [PASS] 0x%08h  %0s", actual, name);
        pass_count = pass_count + 1;
      end else begin
        $display("  [FAIL] got 0x%08h, expected 0x%08h  %0s", actual, expected, name);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // Read 32-bit word from data memory (hierarchical reference)
  function [31:0] read_dmem;
    input [31:0] addr;
    begin
      read_dmem = {u_dut.u_dmem.mem[addr+3],
                   u_dut.u_dmem.mem[addr+2],
                   u_dut.u_dmem.mem[addr+1],
                   u_dut.u_dmem.mem[addr]};
    end
  endfunction

  // ================================================================
  // Main Test Sequence
  // ================================================================
  reg [31:0] gpio_readback, gpio_loopback, uart_rx_data;
  reg [31:0] spi_rx, spi_status, pwm_period, pwm_ctrl;
  reg [31:0] plic_enable, plic_threshold, plic_pending;
  integer    test_phase;

  initial begin
    pass_count = 0;
    fail_count = 0;
    test_phase = 0;

    $display("");
    $display("============================================================");
    $display("  RISC-V SoC Testbench");
    $display("  Clock: 100MHz | Pipeline: 5-stage RV32IM");
    $display("  Peripherals: GPIO, UART, SPI, PWM, WDT, PLIC");
    $display("============================================================");
    $display("");

    // Reset
    rst_n = 0;
    #25;
    rst_n = 1;
    sim_start_time = $time;
    $display("[%0t] Reset released, starting tests...", $time);

    // Wait for full program: GPIO/UART + RV32I + RV32M + extended tests + timer
    #5_000_000;

    $display("[%0t] Program complete. Cycles: %0d", $time, cycle_count);
    $display("");

    // Read GPIO/UART results from data memory
    gpio_readback  = read_dmem(0);
    gpio_loopback  = read_dmem(4);
    uart_rx_data   = read_dmem(8);

    // Read peripheral test results from data memory
    spi_rx          = read_dmem(12);   // MEM[0x100C]
    spi_status      = read_dmem(16);   // MEM[0x1010]
    pwm_period      = read_dmem(20);   // MEM[0x1014]
    pwm_ctrl        = read_dmem(24);   // MEM[0x1018]
    plic_enable     = read_dmem(28);   // MEM[0x101C]
    plic_threshold  = read_dmem(32);   // MEM[0x1020]
    plic_pending    = read_dmem(36);   // MEM[0x1024]

    // ================================================================
    // Test Results
    // ================================================================
    $display("============================================================");
    $display("  TEST RESULTS");
    $display("============================================================");

    // --- GPIO ---
    $display("");
    $display("--- GPIO Tests ---");
    check(gpio_readback, 32'hABCD1234, "GPIO output readback");
    check(gpio_loopback, 32'hABCD1234, "GPIO input loopback");

    // --- UART ---
    $display("");
    $display("--- UART Tests ---");
    check(uart_rx_data, 32'h00000055, "UART TX/RX loopback (0x55)");

    // --- RV32I Basic ---
    $display("");
    $display("--- RV32I Basic Tests ---");
    check(dbg_x6,  32'h0000000f, "OR   (15 | 15 = 15)");
    check(dbg_x7,  32'hfffffff0, "XOR  (-1 ^ 15 = 0xFFFFFFF0)");
    check(dbg_x8,  32'h12345000, "LUI  (0x12345 << 12)");

    // --- RV32I Extended ---
    $display("");
    $display("--- RV32I Extended Tests ---");
    check(dbg_x1,  32'h00000001, "SLT  (-5 < 10 signed = 1)");
    check(dbg_x2,  32'h00000000, "SLTU (0xFFFFFFFB < 10 unsigned = 0)");
    check(dbg_x3,  32'h00000010, "SRL  (256 >> 4 = 16)");
    check(dbg_x4,  32'hffffffff, "SRA  (-16 >>> 4 = -1)");
    check(dbg_x5,  32'h00000000, "SRL  (1 >> 31 = 0)");

    // --- RV32M ---
    $display("");
    $display("--- RV32M Tests ---");
    check(dbg_x12, 32'h0000002a, "REM  (100 % 58 = 42)");
    check(dbg_x13, 32'h00000001, "DIVU (100 / 58 = 1)");
    check(dbg_x14, 32'h0000002a, "REMU (100 % 58 = 42)");

    // --- Timer IRQ ---
    $display("");
    $display("--- Timer Interrupt Test ---");
    check(dbg_x15, 32'h00000001, "Timer IRQ handler executed (x15=1)");

    // --- SPI ---
    $display("");
    $display("--- SPI Tests ---");
    check(spi_rx, 32'h000000A5, "SPI MOSI->MISO loopback (0xA5)");
    check(spi_status[1], 1'b1,     "SPI STATUS rx_valid=1");

    // --- PWM ---
    $display("");
    $display("--- PWM Tests ---");
    check(pwm_period, 32'h00000003, "PWM PERIOD readback (3)");
    check(pwm_ctrl,   32'h00000051, "PWM CTRL readback (0x51)");

    // --- PLIC ---
    $display("");
    $display("--- PLIC Tests ---");
    check(plic_enable,    32'h000000FF, "PLIC ENABLE readback (0xFF)");
    check(plic_threshold, 32'h00000005, "PLIC THRESHOLD readback (5)");
    check(plic_pending,   32'h00000000, "PLIC PENDING=0 (no IRQ)");

    // ================================================================
    // Summary
    // ================================================================
    $display("");
    $display("============================================================");
    $display("  SUMMARY");
    $display("============================================================");
    $display("  Tests:    %0d PASS, %0d FAIL, %0d total", pass_count, fail_count, pass_count + fail_count);
    $display("  Cycles:   %0d", cycle_count);
    $display("  Sim time: %0t ns ($time)", $time);
    $display("============================================================");
    if (fail_count == 0)
      $display("  >>> ALL TESTS PASSED! <<<");
    else
      $display("  >>> %0d TEST(S) FAILED! <<<", fail_count);
    $display("============================================================");
    $display("");

    // Dump register state
    $display("--- Final Register State (debug ports) ---");
    $display("  x1  = 0x%08h  x2  = 0x%08h  x3  = 0x%08h  x4  = 0x%08h",
             dbg_x1, dbg_x2, dbg_x3, dbg_x4);
    $display("  x5  = 0x%08h  x6  = 0x%08h  x7  = 0x%08h  x8  = 0x%08h",
             dbg_x5, dbg_x6, dbg_x7, dbg_x8);
    $display("  x12 = 0x%08h  x13 = 0x%08h  x14 = 0x%08h  x15 = 0x%08h",
             dbg_x12, dbg_x13, dbg_x14, dbg_x15);
    $display("");

    // Dump first 40 bytes of DMEM
    $display("--- DMEM[0x00-0x24] (hex) ---");
    $display("  [0x00] %08h  [0x04] %08h  [0x08] %08h  [0x0C] %08h",
             read_dmem(0), read_dmem(4), read_dmem(8), read_dmem(12));
    $display("  [0x10] %08h  [0x14] %08h  [0x18] %08h  [0x1C] %08h",
             read_dmem(16), read_dmem(20), read_dmem(24), read_dmem(28));
    $display("  [0x20] %08h  [0x24] %08h",
             read_dmem(32), read_dmem(36));
    $display("");

    $finish;
  end

endmodule
