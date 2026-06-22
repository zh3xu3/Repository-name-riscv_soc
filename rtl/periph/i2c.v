`timescale 1ns / 1ps

// I2C Controller - Master mode, register-mapped
// Register map (word-aligned, 0x0000_A000 - 0x0000_A01F):
//   0x00: CTRL      (RW: [0]=enable, [1]=start, [2]=stop, [3]=ack, [4]=irq_en)
//   0x04: STATUS    (RO: [0]=busy, [1]=ack_rx, [2]=arb_lost, [3]=ack_err)
//   0x08: DATA      (RW: data byte)
//   0x0C: DIVIDER   (RW: clock divider value)
//   0x10: CMD       (WO: [0]=write, [1]=read, [2]=restart)
module i2c (
    input  wire        clk,
    input  wire        rst_n,
    // Bus interface
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    output reg  [31:0] bus_rdata,
    input  wire        bus_we,
    input  wire        bus_re,
    // I2C pins (active-low, open-drain style)
    output wire        scl_o,
    input  wire        scl_i,
    output wire        sda_o,
    input  wire        sda_i,
    // Interrupt
    output wire        i2c_irq
);

  // State encoding
  localparam IDLE     = 3'd0;
  localparam START    = 3'd1;
  localparam ADDR     = 3'd2;
  localparam RW       = 3'd3;
  localparam DATA     = 3'd4;
  localparam STOP     = 3'd5;
  localparam ACK      = 3'd6;

  // Register storage
  reg        ctrl_enable;
  reg        ctrl_start;
  reg        ctrl_stop;
  reg        ctrl_ack;
  reg        ctrl_irq_en;
  reg [7:0]  data_reg;
  reg [15:0] divider;
  reg [7:0]  shift_reg;
  reg [3:0]  bit_cnt;
  reg [2:0]  state;
  reg [15:0] clk_cnt;
  reg        scl_out;
  reg        sda_out;
  reg        busy;
  reg        ack_rx;
  reg        arb_lost;
  reg        ack_err;
  reg        done;

  // Clock enable (center of SCL low/high)
  wire clk_en = (clk_cnt == divider[15:1]);

  // I2C outputs (active-low, inverted for active-high logic)
  assign scl_o = ~scl_out;
  assign sda_o = ~sda_out;

  // Interrupt output
  assign i2c_irq = done & ctrl_irq_en;

  // ---- Bus register write ----
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_enable  <= 1'b0;
      ctrl_start   <= 1'b0;
      ctrl_stop    <= 1'b0;
      ctrl_ack     <= 1'b0;
      ctrl_irq_en  <= 1'b0;
      data_reg     <= 8'h00;
      divider      <= 16'h0000;
    end else begin
      // Auto-clear start/stop
      if (ctrl_start) ctrl_start <= 1'b0;
      if (ctrl_stop)  ctrl_stop  <= 1'b0;

      if (bus_we) begin
        case (bus_addr[3:0])
          4'h0: begin // CTRL
            ctrl_enable <= bus_wdata[0];
            ctrl_start  <= bus_wdata[1];
            ctrl_stop   <= bus_wdata[2];
            ctrl_ack    <= bus_wdata[3];
            ctrl_irq_en <= bus_wdata[4];
          end
          4'h8: data_reg  <= bus_wdata[7:0]; // DATA
          4'hC: divider   <= bus_wdata[15:0]; // DIVIDER
          default: ;
        endcase
      end
    end
  end

  // ---- Bus register read ----
  always @(*) begin
    if (!bus_re)
      bus_rdata = 32'h0;
    else begin
      case (bus_addr[3:0])
        4'h0: bus_rdata = {27'h0, ctrl_irq_en, ctrl_ack, ctrl_stop, ctrl_start, ctrl_enable};
        4'h4: bus_rdata = {28'h0, ack_err, arb_lost, ack_rx, busy};
        4'h8: bus_rdata = {24'h0, data_reg};
        4'hC: bus_rdata = {16'h0, divider};
        default: bus_rdata = 32'h0;
      endcase
    end
  end

  // ---- I2C state machine ----
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= IDLE;
      busy      <= 1'b0;
      ack_rx    <= 1'b0;
      arb_lost  <= 1'b0;
      ack_err   <= 1'b0;
      done      <= 1'b0;
      scl_out   <= 1'b1;
      sda_out   <= 1'b1;
      shift_reg <= 8'h00;
      bit_cnt   <= 4'h0;
      clk_cnt   <= 16'h0;
    end else begin
      // Default
      done <= 1'b0;

      case (state)
        IDLE: begin
          scl_out <= 1'b1;
          sda_out <= 1'b1;
          if (ctrl_enable && ctrl_start) begin
            busy    <= 1'b1;
            state   <= START;
            clk_cnt <= 16'h0;
          end
        end

        START: begin
          // SDA goes low while SCL high (start condition)
          sda_out <= 1'b0;
          if (clk_en) begin
            scl_out <= 1'b0;
            state   <= ADDR;
            bit_cnt <= 4'd7;
            shift_reg <= data_reg; // Address byte
            clk_cnt <= 16'h0;
          end else begin
            clk_cnt <= clk_cnt + 1;
          end
        end

        ADDR: begin
          // Shift out address bits
          sda_out <= shift_reg[7];
          if (clk_en) begin
            scl_out <= ~scl_out;
            if (scl_out) begin // Falling edge
              shift_reg <= {shift_reg[6:0], 1'b0};
              bit_cnt   <= bit_cnt - 1;
              if (bit_cnt == 0) begin
                state   <= RW;
                clk_cnt <= 16'h0;
              end
            end
          end else begin
            clk_cnt <= clk_cnt + 1;
          end
        end

        RW: begin
          // R/W bit (LSB of address)
          sda_out <= shift_reg[0];
          if (clk_en) begin
            scl_out <= ~scl_out;
            if (scl_out) begin // Falling edge
              state   <= ACK;
              sda_out <= 1'b1; // Release SDA for ACK
              clk_cnt <= 16'h0;
            end
          end else begin
            clk_cnt <= clk_cnt + 1;
          end
        end

        ACK: begin
          // Sample ACK from slave
          if (clk_en) begin
            scl_out <= ~scl_out;
            if (!scl_out) begin // Rising edge - sample
              ack_rx  <= ~sda_i; // ACK is low
              ack_err <= sda_i;  // NACK is high (error)
            end else begin // Falling edge
              if (ctrl_stop) begin
                state   <= STOP;
                clk_cnt <= 16'h0;
              end else begin
                state   <= DATA;
                bit_cnt <= 4'd7;
                shift_reg <= data_reg;
                clk_cnt <= 16'h0;
              end
            end
          end else begin
            clk_cnt <= clk_cnt + 1;
          end
        end

        DATA: begin
          // Data transfer
          sda_out <= shift_reg[7];
          if (clk_en) begin
            scl_out <= ~scl_out;
            if (scl_out) begin // Falling edge
              shift_reg <= {shift_reg[6:0], 1'b0};
              bit_cnt   <= bit_cnt - 1;
              if (bit_cnt == 0) begin
                state   <= ACK;
                sda_out <= 1'b1; // Release for ACK
                clk_cnt <= 16'h0;
              end
            end
          end else begin
            clk_cnt <= clk_cnt + 1;
          end
        end

        STOP: begin
          // SDA goes high while SCL high (stop condition)
          sda_out <= 1'b0;
          if (clk_en) begin
            scl_out <= 1'b1;
            if (scl_out) begin // SCL already high
              sda_out <= 1'b1;
              busy    <= 1'b0;
              done    <= 1'b1;
              state   <= IDLE;
            end
          end else begin
            clk_cnt <= clk_cnt + 1;
          end
        end

        default: state <= IDLE;
      endcase

      // Arbitration lost detection (SDA mismatch while driving)
      if (state == ADDR || state == RW || state == DATA) begin
        if (scl_out && !scl_i) begin // SCL pulled low by slave
          arb_lost <= 1'b1;
        end
      end
    end
  end

endmodule
