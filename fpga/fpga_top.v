`timescale 1ns / 1ps

// FPGA Top Level for A7_lite Board (Artix-7 XC7A35T)
// 50MHz input clock → PLL → 100MHz system clock
//
// UART_LOOPBACK=1: internal TX→RX loopback (no external wiring needed)
// UART_LOOPBACK=0: use external UART pins (connect USB-UART adapter)
module fpga_top #(
    parameter UART_LOOPBACK = 1   // 1=internal loopback, 0=external pins
)(
    input  wire clk_50m,    // 50MHz oscillator (J19)
    input  wire rst_n_in,   // Active-low reset (L18)
    // UART
    input  wire uart_rx,    // RX (U2)
    output wire uart_tx,    // TX (V2)
    // LEDs
    output wire led1,       // M18
    output wire led2,       // N18
    // SPI (directly available on header)
    output wire spi_sck,
    output wire spi_mosi,
    input  wire spi_miso,
    output wire spi_cs_n,
    // PWM outputs
    output wire pwm0,
    output wire pwm1
);

  // ================================================================
  // PLL: 50MHz → 100MHz
  // ================================================================
  wire clk_100m, pll_locked;
  wire pll_clkfb;

  PLL_BASE #(
    .BANDWIDTH          ("OPTIMIZED"),
    .CLKFBOUT_MULT      (20),        // VCO = 50MHz × 20 = 1000MHz
    .CLKFBOUT_PHASE     (0.0),
    .CLKIN1_PERIOD       (20.0),      // 50MHz = 20ns
    .CLKOUT0_DIVIDE     (10),        // 1000MHz / 10 = 100MHz
    .CLKOUT1_DIVIDE     (1),
    .CLKOUT2_DIVIDE     (1),
    .CLKOUT3_DIVIDE     (1),
    .CLKOUT4_DIVIDE     (1),
    .CLKOUT5_DIVIDE     (1),
    .CLK_FEEDBACK       ("CLKFBOUT"),
    .COMPENSATION       ("SYSTEM_SYNCHRONOUS"),
    .DIVCLK_DIVIDE      (1),
    .REF_JITTER         (0.100),
    .RESET_ON_LOSS_OF_LOCK ("FALSE")
  ) u_pll (
    .CLKIN1    (clk_50m),
    .CLKFBIN   (pll_clkfb),
    .CLKFBOUT  (pll_clkfb),
    .CLKOUT0   (clk_100m),
    .CLKOUT1   (),
    .CLKOUT2   (),
    .CLKOUT3   (),
    .CLKOUT4   (),
    .CLKOUT5   (),
    .LOCKED    (pll_locked),
    .RST       (1'b0),
    .CLKFBOUTB (),
    .CLKOUT0B  (),
    .CLKOUT1B  (),
    .CLKOUT2B  (),
    .CLKOUT3B  (),
    .CLKOUT4B  (),
    .CLKOUT5B  ()
  );

  // ================================================================
  // Reset Synchronizer
  // ================================================================
  reg [2:0] rst_sync;
  wire sys_rst_n;

  always @(posedge clk_100m or negedge pll_locked) begin
    if (!pll_locked)
      rst_sync <= 3'b000;
    else
      rst_sync <= {rst_sync[1:0], rst_n_in};
  end

  assign sys_rst_n = rst_sync[2];

  // ================================================================
  // UART Loopback MUX
  // ================================================================
  wire uart_rx_int = (UART_LOOPBACK) ? uart_tx : uart_rx;

  // ================================================================
  // SoC Instantiation
  // ================================================================
  wire [31:0] gpio_o, gpio_i, gpio_dir;
  wire [3:0]  pwm_out;

  soc_top #(
    .CLK_FREQ(100_000_000),
    .BAUD    (115200)
  ) u_soc (
    .clk     (clk_100m),
    .rst_n   (sys_rst_n),
    .uart_tx (uart_tx),
    .uart_rx (uart_rx_int),
    .gpio_o  (gpio_o),
    .gpio_i  (gpio_i),
    .gpio_dir(gpio_dir),
    .spi_sck (spi_sck),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .spi_cs_n(spi_cs_n),
    .pwm_out (pwm_out),
    .dbg_x1  (),
    .dbg_x2  (),
    .dbg_x3  (),
    .dbg_x4  (),
    .dbg_x5  (),
    .dbg_x6  (),
    .dbg_x7  (),
    .dbg_x8  (),
    .dbg_x12 (),
    .dbg_x13 (),
    .dbg_x14 (),
    .dbg_x15 ()
  );

  // GPIO loopback (same as testbench)
  assign gpio_i = gpio_o;

  // PWM outputs
  assign pwm0 = pwm_out[0];
  assign pwm1 = pwm_out[1];

  // Map GPIO[4] → LED1, GPIO[5] → LED2
  // Test program writes 0xABCD1234: bit4=1, bit5=1 → both LEDs ON
  assign led1 = gpio_o[4];
  assign led2 = gpio_o[5];

endmodule
