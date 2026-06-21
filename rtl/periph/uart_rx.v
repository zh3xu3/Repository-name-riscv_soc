`timescale 1ns / 1ps

// UART Receiver - 8N1
module uart_rx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] dout,
    output reg        valid,    // pulses 1 cycle when byte ready
    input  wire       rd_en,    // clear valid
    output reg        overflow  // new byte arrived before previous read
);

  localparam DIVISOR  = CLK_FREQ / BAUD;
  localparam HALF_DIV = DIVISOR / 2;

  reg [15:0] cnt;
  reg [3:0]  bit_idx;
  reg [7:0]  shift;
  reg        active;
  reg [1:0]  rx_sync;  // metastability sync

  // 2-stage synchronizer
  always @(posedge clk) begin
    rx_sync <= {rx_sync[0], rx};
  end

  wire rx_in = rx_sync[1];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt      <= 0;
      bit_idx  <= 0;
      shift    <= 0;
      active   <= 0;
      dout     <= 0;
      valid    <= 0;
      overflow <= 0;
    end else begin
      if (rd_en) valid <= 0;

      if (!active) begin
        // Detect start bit (falling edge)
        if (!rx_in) begin
          active  <= 1;
          cnt     <= HALF_DIV;  // sample mid-bit
          bit_idx <= 0;
        end
      end else begin
        if (cnt == DIVISOR - 1) begin
          cnt <= 0;
          if (bit_idx == 0) begin
            // Verify start bit still low
            if (rx_in) active <= 0;  // false start
          end else if (bit_idx <= 8) begin
            shift <= {rx_in, shift[7:1]};
          end else begin
            // Stop bit
            if (rx_in) begin
              if (valid) overflow <= 1;
              dout  <= shift;
              valid <= 1;
            end
            active <= 0;
          end
          bit_idx <= bit_idx + 1;
        end else begin
          cnt <= cnt + 1;
        end
      end
    end
  end

endmodule
