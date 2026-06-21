`timescale 1ns / 1ps

// RISC-V SoC Top Level with Bus + Peripherals
// Memory Map:
//   0x0000_0000: Instruction memory (read-only from core imem port)
//   0x0000_1000: Data memory (4KB)
//   0x0000_2000: UART (TX_DATA, RX_DATA, STATUS)
//   0x0000_3000: GPIO (output, input, direction)
//   0x0000_4000: WDT  (kick, timeout, status)
//   0x0000_5000: SPI  (data, ctrl, status, cs)
//   0x0000_6000: PWM  (ctrl, period, duty0-3, count)
//   0x0000_7000: PLIC (pending, enable, threshold, claim, priority)
module soc_top #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    // UART pins
    output wire        uart_tx,
    input  wire        uart_rx,
    // GPIO pins
    output wire [31:0] gpio_o,
    input  wire [31:0] gpio_i,
    output wire [31:0] gpio_dir,
    // SPI pins
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,
    // PWM outputs
    output wire [3:0]  pwm_out,
    // Debug
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

  // Core interfaces
  wire [31:0] imem_addr, imem_rdata;
  wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  wire        dmem_we, dmem_re;
  wire [ 2:0] dmem_size;
  wire        plic_irq;

  // Address decode
  wire sel_dmem = (dmem_addr[31:12] == 20'h00001);  // 0x0000_1xxx
  wire sel_uart = (dmem_addr[31:12] == 20'h00002);  // 0x0000_2xxx
  wire sel_gpio = (dmem_addr[31:12] == 20'h00003);  // 0x0000_3xxx
  wire sel_wdt  = (dmem_addr[31:12] == 20'h00004);  // 0x0000_4xxx
  wire sel_spi  = (dmem_addr[31:12] == 20'h00005);  // 0x0000_5xxx
  wire sel_pwm  = (dmem_addr[31:12] == 20'h00006);  // 0x0000_6xxx
  wire sel_plic = (dmem_addr[31:12] == 20'h00007);  // 0x0000_7xxx

  // Peripheral read data
  wire [31:0] dmem_rdata_mem, uart_rdata, gpio_rdata, wdt_rdata, spi_rdata, pwm_rdata, plic_rdata;

  // Read MUX
  assign dmem_rdata = sel_dmem ? dmem_rdata_mem :
                      sel_uart ? uart_rdata :
                      sel_gpio ? gpio_rdata :
                      sel_wdt  ? wdt_rdata :
                      sel_spi  ? spi_rdata :
                      sel_pwm  ? pwm_rdata :
                      sel_plic ? plic_rdata :
                      32'h0;

  // Bus error: access to unmapped address
  wire sel_any = sel_dmem || sel_uart || sel_gpio || sel_wdt || sel_spi || sel_pwm || sel_plic;
  wire bus_error = (dmem_we || dmem_re) && !sel_any;

  // Watchdog timer
  wire wdt_rst;
  wire sys_rst_n = rst_n & ~wdt_rst;

  wdt u_wdt (
    .clk     (clk),
    .rst_n   (rst_n),
    .addr    (dmem_addr[3:0]),
    .wdata   (dmem_wdata),
    .rdata   (wdt_rdata),
    .we      (dmem_we && sel_wdt),
    .re      (dmem_re && sel_wdt),
    .wdt_rst (wdt_rst)
  );

  // RISC-V Core (reset by external reset OR watchdog timeout)
  riscv_core u_core (
    .clk        (clk),
    .rst_n      (sys_rst_n),
    .imem_addr  (imem_addr),
    .imem_rdata (imem_rdata),
    .dmem_addr  (dmem_addr),
    .dmem_wdata (dmem_wdata),
    .dmem_rdata (dmem_rdata),
    .dmem_we    (dmem_we),
    .dmem_re    (dmem_re),
    .dmem_size  (dmem_size),
    .bus_error  (bus_error),
    .ext_irq    (plic_irq),
    .dbg_x1     (dbg_x1),
    .dbg_x2     (dbg_x2),
    .dbg_x3     (dbg_x3),
    .dbg_x4     (dbg_x4),
    .dbg_x5     (dbg_x5),
    .dbg_x6     (dbg_x6),
    .dbg_x7     (dbg_x7),
    .dbg_x8     (dbg_x8),
    .dbg_x12    (dbg_x12),
    .dbg_x13    (dbg_x13),
    .dbg_x14    (dbg_x14),
    .dbg_x15    (dbg_x15)
  );

  // Instruction Memory
  inst_mem #(
    .MEM_SIZE(1024)
  ) u_imem (
    .addr  (imem_addr),
    .rdata (imem_rdata)
  );

  // Data Memory
  data_mem #(
    .MEM_SIZE(1024)
  ) u_dmem (
    .clk   (clk),
    .addr  (dmem_addr),
    .rdata (dmem_rdata_mem),
    .re    (dmem_re && sel_dmem),
    .wdata (dmem_wdata),
    .we    (dmem_we && sel_dmem),
    .size  (dmem_size)
  );

  // UART
  uart #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD(BAUD)
  ) u_uart (
    .clk     (clk),
    .rst_n   (rst_n),
    .addr    (dmem_addr[3:0]),
    .wdata   (dmem_wdata),
    .rdata   (uart_rdata),
    .we      (dmem_we && sel_uart),
    .re      (dmem_re && sel_uart),
    .tx_pin  (uart_tx),
    .rx_pin  (uart_rx)
  );

  // GPIO
  gpio u_gpio (
    .clk     (clk),
    .rst_n   (rst_n),
    .addr    (dmem_addr[3:0]),
    .wdata   (dmem_wdata),
    .rdata   (gpio_rdata),
    .we      (dmem_we && sel_gpio),
    .re      (dmem_re && sel_gpio),
    .gpio_o  (gpio_o),
    .gpio_i  (gpio_i),
    .gpio_dir(gpio_dir)
  );

  // SPI
  spi u_spi (
    .clk      (clk),
    .rst_n    (rst_n),
    .addr     (dmem_addr[3:0]),
    .wdata    (dmem_wdata),
    .rdata    (spi_rdata),
    .we       (dmem_we && sel_spi),
    .re       (dmem_re && sel_spi),
    .spi_sck  (spi_sck),
    .spi_mosi (spi_mosi),
    .spi_miso (spi_miso),
    .spi_cs_n (spi_cs_n)
  );

  // PWM
  pwm u_pwm (
    .clk     (clk),
    .rst_n   (rst_n),
    .addr    (dmem_addr[4:0]),
    .wdata   (dmem_wdata),
    .rdata   (pwm_rdata),
    .we      (dmem_we && sel_pwm),
    .re      (dmem_re && sel_pwm),
    .pwm_out (pwm_out)
  );

  // PLIC - interrupt sources: UART RX, SPI done, WDT
  wire [15:0] irq_sources;
  assign irq_sources[0] = 1'b0;  // Reserved
  assign irq_sources[1] = 1'b0;  // UART TX (unused)
  assign irq_sources[2] = 1'b0;  // UART RX (placeholder)
  assign irq_sources[3] = 1'b0;  // SPI done (placeholder)
  assign irq_sources[4] = 1'b0;  // WDT (placeholder)
  assign irq_sources[15:5] = 11'b0;

  plic u_plic (
    .clk     (clk),
    .rst_n   (rst_n),
    .addr    (dmem_addr[5:0]),
    .wdata   (dmem_wdata),
    .rdata   (plic_rdata),
    .we      (dmem_we && sel_plic),
    .re      (dmem_re && sel_plic),
    .irq_src (irq_sources),
    .irq_out (plic_irq)
  );

endmodule
