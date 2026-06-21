`timescale 1ns / 1ps

// UART peripheral - TX + RX + status registers
// Register map (word-aligned):
//   0x00: TX_DATA  (write) - send byte
//   0x04: RX_DATA  (read)  - received byte, clears valid
//   0x08: STATUS   (read)  - [0]=tx_busy [1]=rx_valid [2]=rx_overflow
module uart #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    // Register access
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        re,
    // External pins
    output wire        tx_pin,
    input  wire        rx_pin
);

  wire       tx_busy;
  wire [7:0] rx_dout;
  wire       rx_valid;
  wire       rx_overflow;
  reg        rx_rd_en;

  uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_tx (
    .clk   (clk),
    .rst_n (rst_n),
    .din   (wdata[7:0]),
    .wr_en (we && addr[3:0] == 4'h0),
    .busy  (tx_busy),
    .tx    (tx_pin)
  );

  uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_rx (
    .clk      (clk),
    .rst_n    (rst_n),
    .rx       (rx_pin),
    .dout     (rx_dout),
    .valid    (rx_valid),
    .rd_en    (rx_rd_en),
    .overflow (rx_overflow)
  );

  // Read: RX_DATA clears valid
  always @(*) begin
    rx_rd_en = re && (addr[3:0] == 4'h4);
    if (!re)
      rdata = 32'h0;
    else begin
      case (addr[3:0])
        4'h0:   rdata = {31'h0, tx_busy};
        4'h4:   rdata = {24'h0, rx_dout};
        4'h8:   rdata = {29'h0, rx_overflow, rx_valid, tx_busy};
        default: rdata = 32'h0;
      endcase
    end
  end

endmodule
