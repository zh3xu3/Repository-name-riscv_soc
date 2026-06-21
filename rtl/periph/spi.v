`timescale 1ns / 1ps

// Simple SPI Master
// Register map (word-aligned):
//   0x00: SPI_DATA   (WO: write tx data, RO: read rx data)
//   0x04: SPI_CTRL   (RW: [0]=CPOL, [1]=CPHA, [7:4]=clock divider)
//   0x08: SPI_STATUS (RO: [0]=busy, [1]=rx_valid)
//   0x0C: SPI_CS     (RW: [0]=CS_N active-low)
module spi #(
    parameter DEFAULT_DIV = 4   // SPI clock = clk / (2*DIV)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        re,
    // SPI pins
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output reg         spi_cs_n
);

  // Registers
  reg [7:0]  tx_data;
  reg [7:0]  rx_data;
  reg        cpol, cpha;
  reg [3:0]  clk_div;
  reg        rx_valid;
  reg        busy;

  // SPI clock generation
  reg [3:0]  div_cnt;
  reg        spi_clk_en;
  reg        spi_clk_internal;
  wire       tick = (div_cnt == 0);

  // Shift register
  reg [7:0]  shift_out;
  reg [7:0]  shift_in;
  reg [3:0]  bit_cnt;
  reg [1:0]  state;

  localparam IDLE   = 2'b00;
  localparam SHIFT  = 2'b01;
  localparam DONE   = 2'b10;

  // Register write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_data   <= 8'h00;
      cpol      <= 1'b0;
      cpha      <= 1'b0;
      clk_div   <= DEFAULT_DIV[3:0];
      spi_cs_n  <= 1'b1;
    end else if (we) begin
      case (addr[3:2])
        2'b00: tx_data  <= wdata[7:0];
        2'b01: begin cpol <= wdata[0]; cpha <= wdata[1]; clk_div <= wdata[7:4]; end
        2'b11: spi_cs_n <= wdata[0];
        default: ;
      endcase
    end
  end

  // SPI state machine
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= IDLE;
      busy       <= 1'b0;
      rx_valid   <= 1'b0;
      div_cnt    <= 0;
      bit_cnt    <= 0;
      shift_out  <= 8'h00;
      shift_in   <= 8'h00;
      spi_clk_internal <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          spi_clk_internal <= cpol;
          if (we && addr[3:2] == 2'b00 && !busy) begin
            shift_out <= wdata[7:0];
            bit_cnt   <= 0;
            div_cnt   <= clk_div;
            busy      <= 1'b1;
            rx_valid  <= 1'b0;
            state     <= SHIFT;
          end
        end

        SHIFT: begin
          if (tick) begin
            div_cnt <= clk_div;
            // Toggle SPI clock
            spi_clk_internal <= ~spi_clk_internal;
            // Determine if this edge is leading or trailing based on CPOL
            // Leading edge = transition away from idle (CPOL)
            // For CPHA=0: sample on leading, shift on trailing
            // For CPHA=1: shift on leading, sample on trailing
            if ((!spi_clk_internal ^ cpol) ^ cpha) begin
              // Sample MISO
              shift_in <= {shift_in[6:0], spi_miso};
              if (bit_cnt == 7) begin
                state <= DONE;
              end else begin
                bit_cnt <= bit_cnt + 1;
              end
            end else begin
              // Shift out next bit
              shift_out <= {shift_out[6:0], 1'b0};
            end
          end else begin
            div_cnt <= div_cnt - 1;
          end
        end

        DONE: begin
          rx_data  <= shift_in;
          rx_valid <= 1'b1;
          busy     <= 1'b0;
          state    <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign spi_sck  = spi_clk_internal;
  assign spi_mosi = shift_out[7];

  // Register read
  always @(*) begin
    if (!re)
      rdata = 32'h0;
    else begin
      case (addr[3:2])
        2'b00: rdata = {24'h0, rx_data};
        2'b01: rdata = {24'h0, clk_div, 2'b0, cpha, cpol};
        2'b10: rdata = {30'h0, rx_valid, busy};
        2'b11: rdata = {31'h0, ~spi_cs_n};
        default: rdata = 32'h0;
      endcase
    end
  end

endmodule
