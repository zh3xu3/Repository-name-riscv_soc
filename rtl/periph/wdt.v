`timescale 1ns / 1ps

// Watchdog Timer (WDT)
// Register map:
//   0x00: CTRL    (w)  - write 0x5A5A to kick (reset counter)
//   0x04: TIMEOUT (r/w) - timeout value in clock cycles (default: 1M)
//   0x08: STATUS  (r)  - [0]=enabled [31:16]=counter[15:0] (high bits)
// When counter reaches TIMEOUT, wdt_rst asserts for 1 cycle.
module wdt (
    input  wire        clk,
    input  wire        rst_n,
    // Register access
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        re,
    // Reset output
    output wire        wdt_rst
);

  reg [31:0] timeout;
  reg [31:0] counter;
  reg        enabled;

  // Initialize timeout to 1,000,000 cycles (~10ms at 100MHz)
  initial begin
    timeout = 32'd1_000_000;
    enabled = 1'b0;
  end

  // Kick detection: write 0x5A5A to offset 0x00
  wire kick = we && (addr[3:2] == 2'b00) && (wdata == 32'h0000_5A5A);

  // Counter logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      counter <= 32'h0;
      timeout <= 32'd1_000_000;
      enabled <= 1'b0;
    end else if (kick) begin
      counter <= 32'h0;
      enabled <= 1'b1;  // kick also enables
    end else if (we && addr[3:2] == 2'b01) begin
      timeout <= wdata;
    end else if (enabled) begin
      counter <= counter + 1;
    end
  end

  // Timeout: assert reset when counter reaches timeout
  assign wdt_rst = enabled && (counter >= timeout);

  // Read
  always @(*) begin
    if (!re)
      rdata = 32'h0;
    else begin
      case (addr[3:2])
        2'b00:   rdata = 32'h0;                           // CTRL (read returns 0)
        2'b01:   rdata = timeout;                          // TIMEOUT
        2'b10:   rdata = {counter[31:16], 15'h0, enabled}; // STATUS
        default: rdata = 32'h0;
      endcase
    end
  end

endmodule
