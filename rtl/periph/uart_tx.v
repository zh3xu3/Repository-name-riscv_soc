`timescale 1ns / 1ps

// UART Transmitter - 8N1
module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] din,
    input  wire       wr_en,
    output wire       busy,
    output reg        tx
);

  localparam DIVISOR = CLK_FREQ / BAUD;

  reg [15:0] cnt;
  reg [3:0]  bit_idx;
  reg [9:0]  shift;
  reg        active;

  // busy is combinationally high when active or when a write is accepted this cycle.
  // This prevents a second write from being accepted on the same cycle the first
  // write starts (before 'active' goes high on the next clock edge).
  assign busy = active || (wr_en && !active);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt     <= 0;
      bit_idx <= 0;
      shift   <= 10'h3FF;
      active  <= 0;
      tx      <= 1;
    end else if (wr_en && !active) begin
      // Start: load shift register {stop, data[7:0], start}
      shift   <= {1'b1, din, 1'b0};
      bit_idx <= 0;
      cnt     <= 0;
      active  <= 1;
      tx      <= 0;  // start bit immediately
    end else if (active) begin
      if (cnt == DIVISOR - 1) begin
        cnt     <= 0;
        bit_idx <= bit_idx + 1;
        shift   <= {1'b1, shift[9:1]};
        tx      <= shift[1];
        if (bit_idx == 9) begin
          active <= 0;
          tx     <= 1;
        end
      end else begin
        cnt <= cnt + 1;
      end
    end
  end

endmodule
