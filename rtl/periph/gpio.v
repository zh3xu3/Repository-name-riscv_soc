`timescale 1ns / 1ps

// GPIO Controller - 32-bit bidirectional with direction register
// Register map:
//   0x00: DATA   (r/w) - output data register
//   0x04: INPUT  (r)   - input data (synchronized external pins)
//   0x08: DIR    (r/w) - direction (0=input, 1=output, per bit)
module gpio (
    input  wire        clk,
    input  wire        rst_n,
    // Register access
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        re,
    // External pins
    output reg  [31:0] gpio_o,
    input  wire [31:0] gpio_i,
    output wire [31:0] gpio_dir
);

  reg [31:0] dir;

  // Write output register (only bits set as output)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      gpio_o <= 32'h0;
    else if (we && addr[3:2] == 2'b00)
      gpio_o <= wdata;
  end

  // Write direction register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      dir <= 32'h0;
    else if (we && addr[3:2] == 2'b10)
      dir <= wdata;
  end

  assign gpio_dir = dir;

  // 2-stage synchronizer for GPIO input (prevent metastability)
  reg [31:0] gpio_i_sync1, gpio_i_sync2;
  always @(posedge clk) begin
    gpio_i_sync1 <= gpio_i;
    gpio_i_sync2 <= gpio_i_sync1;
  end

  // Read
  always @(*) begin
    if (!re)
      rdata = 32'h0;
    else begin
      case (addr[3:2])
        2'b00:   rdata = gpio_o;        // 0x00: output data
        2'b01:   rdata = gpio_i_sync2;  // 0x04: input data (synchronized)
        2'b10:   rdata = dir;           // 0x08: direction
        default: rdata = 32'h0;
      endcase
    end
  end

endmodule
