`timescale 1ns / 1ps

// Testbench for new peripheral tests (DMA, I-Cache, I2C)
module tb_new_peripherals;

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

  // I2C loopback (for basic testing)
  wire i2c_scl_pin;
  wire i2c_sda_pin;

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
    .scl_o    (i2c_scl_pin),
    .scl_i    (i2c_scl_pin),
    .sda_o    (i2c_sda_pin),
    .sda_i    (i2c_sda_pin),
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
  // VCD Dump
  // ================================================================
  initial begin
    $dumpfile("tb_new_peripherals.vcd");
    $dumpvars(0, tb_new_peripherals);
  end

  // ================================================================
  // Test Infrastructure
  // ================================================================
  integer pass_count, fail_count;
  integer test_id;
  reg [31:0] gpio_result;

  task check_test;
    input [31:0] actual;
    input [31:0] expected;
    input [8*40-1:0] name;
    input integer tid;
    begin
      if (actual === expected) begin
        $display("  [PASS] Test %0d: %0s", tid, name);
        pass_count = pass_count + 1;
      end else begin
        $display("  [FAIL] Test %0d: %0s (got 0x%08h, expected 0x%08h)", tid, name, actual, expected);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // ================================================================
  // Main Test Sequence
  // ================================================================
  initial begin
    // Initialize
    rst_n = 0;
    pass_count = 0;
    fail_count = 0;

    // Reset
    #100;
    rst_n = 1;
    #100;

    $display("");
    $display("============================================================");
    $display("  New Peripheral Test Results (DMA, I-Cache, I2C)");
    $display("============================================================");
    $display("");

    // Wait for program to complete
    // The program writes results to GPIO[0] at address 0x3000
    // GPIO[0] = pass_count | (fail_count << 8) | (last_test_id << 16)
    // We wait for the program to finish (EBREAK instruction)

    // Wait for sufficient time for all tests to complete
    // DMA test: ~100 cycles
    // I-Cache test: ~200 cycles
    // I2C test: ~500 cycles (slow I2C)
    // Total: ~1000 cycles = 10us
    #50000;  // 50us

    // Read GPIO result from output pins
    // The test program writes results to GPIO[0] at address 0x3000
    // GPIO output is directly visible on gpio_out pins
    gpio_result = gpio_out;

    // Parse result
    // bits [7:0] = pass_count
    // bits [15:8] = fail_count
    // bits [23:16] = last_test_id
    pass_count = gpio_result[7:0];
    fail_count = gpio_result[15:8];
    test_id = gpio_result[23:16];

    // Display results by category
    $display("  DMA Tests:");
    if (test_id >= 1) begin
      if (pass_count > 0 && fail_count == 0)
        $display("    [PASS] Test 1: DMA mem-to-mem transfer");
      else
        $display("    [FAIL] Test 1: DMA mem-to-mem transfer");
    end else begin
      $display("    [SKIP] Test 1: DMA mem-to-mem transfer (not reached)");
    end

    if (test_id >= 2) begin
      if (pass_count > 1 && fail_count == 0)
        $display("    [PASS] Test 2: DMA transfer-complete IRQ");
      else
        $display("    [FAIL] Test 2: DMA transfer-complete IRQ");
    end else begin
      $display("    [SKIP] Test 2: DMA transfer-complete IRQ (not reached)");
    end

    $display("");
    $display("  I-Cache Tests:");
    if (test_id >= 3) begin
      if (pass_count > 2 && fail_count == 0)
        $display("    [PASS] Test 3: I-Cache enable/disable");
      else
        $display("    [FAIL] Test 3: I-Cache enable/disable");
    end else begin
      $display("    [SKIP] Test 3: I-Cache enable/disable (not reached)");
    end

    if (test_id >= 4) begin
      if (pass_count > 3 && fail_count == 0)
        $display("    [PASS] Test 4: I-Cache hit/miss counters");
      else
        $display("    [FAIL] Test 4: I-Cache hit/miss counters");
    end else begin
      $display("    [SKIP] Test 4: I-Cache hit/miss counters (not reached)");
    end

    if (test_id >= 5) begin
      if (pass_count > 4 && fail_count == 0)
        $display("    [PASS] Test 5: I-Cache flush");
      else
        $display("    [FAIL] Test 5: I-Cache flush");
    end else begin
      $display("    [SKIP] Test 5: I-Cache flush (not reached)");
    end

    $display("");
    $display("  I2C Tests:");
    if (test_id >= 6) begin
      if (pass_count > 5 && fail_count == 0)
        $display("    [PASS] Test 6: I2C write operation");
      else
        $display("    [FAIL] Test 6: I2C write operation");
    end else begin
      $display("    [SKIP] Test 6: I2C write operation (not reached)");
    end

    if (test_id >= 7) begin
      if (pass_count > 6 && fail_count == 0)
        $display("    [PASS] Test 7: I2C read operation");
      else
        $display("    [FAIL] Test 7: I2C read operation");
    end else begin
      $display("    [SKIP] Test 7: I2C read operation (not reached)");
    end

    if (test_id >= 8) begin
      if (pass_count > 7 && fail_count == 0)
        $display("    [PASS] Test 8: I2C NACK handling");
      else
        $display("    [FAIL] Test 8: I2C NACK handling");
    end else begin
      $display("    [SKIP] Test 8: I2C NACK handling (not reached)");
    end

    $display("");
    $display("============================================================");
    $display("  Summary: %0d PASS, %0d FAIL, %0d total", pass_count, fail_count, pass_count + fail_count);
    $display("  GPIO Result: 0x%08h", gpio_result);
    $display("============================================================");

    if (fail_count == 0 && pass_count == 8) begin
      $display("  >>> ALL TESTS PASSED! <<<");
    end else begin
      $display("  >>> %0d TEST(S) FAILED! <<<", fail_count);
    end

    $display("");
    $display("  Final Register State:");
    $display("    x1  = 0x%08h  x2  = 0x%08h  x3  = 0x%08h  x4  = 0x%08h", dbg_x1, dbg_x2, dbg_x3, dbg_x4);
    $display("    x5  = 0x%08h  x6  = 0x%08h  x7  = 0x%08h  x8  = 0x%08h", dbg_x5, dbg_x6, dbg_x7, dbg_x8);
    $display("    x12 = 0x%08h  x13 = 0x%08h  x14 = 0x%08h  x15 = 0x%08h", dbg_x12, dbg_x13, dbg_x14, dbg_x15);

    $display("");
    $finish;
  end

  // ================================================================
  // Timeout watchdog
  // ================================================================
  initial begin
    #100000;  // 100us timeout
    $display("");
    $display("============================================================");
    $display("  ERROR: Simulation timeout!");
    $display("  Program did not complete within 100us");
    $display("============================================================");
    $display("");
    $display("  Current Register State:");
    $display("    x1  = 0x%08h  x2  = 0x%08h  x3  = 0x%08h  x4  = 0x%08h", dbg_x1, dbg_x2, dbg_x3, dbg_x4);
    $display("    x5  = 0x%08h  x6  = 0x%08h  x7  = 0x%08h  x8  = 0x%08h", dbg_x5, dbg_x6, dbg_x7, dbg_x8);
    $display("    x12 = 0x%08h  x13 = 0x%08h  x14 = 0x%08h  x15 = 0x%08h", dbg_x12, dbg_x13, dbg_x14, dbg_x15);
    $display("");
    $finish;
  end

endmodule
