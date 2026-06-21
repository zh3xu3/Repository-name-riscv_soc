`timescale 1ns / 1ps

// PWM Controller - 4 independent channels
// Register map (word-aligned):
//   0x00: PWM_CTRL    (RW: [0]=global_enable, [4]=ch0_en, [5]=ch1_en, [6]=ch2_en, [7]=ch3_en)
//   0x04: PWM_PERIOD  (RW: period value - 1)
//   0x08: PWM_DUTY0   (RW: channel 0 duty cycle)
//   0x0C: PWM_DUTY1   (RW: channel 1 duty cycle)
//   0x10: PWM_DUTY2   (RW: channel 2 duty cycle)
//   0x14: PWM_DUTY3   (RW: channel 3 duty cycle)
//   0x18: PWM_COUNT   (RO: current counter value)
module pwm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        re,
    // PWM outputs
    output wire [3:0]  pwm_out
);

  // Registers
  reg        global_en;
  reg [3:0]  ch_en;
  reg [31:0] period;
  reg [31:0] duty [0:3];

  // Counter
  reg [31:0] counter;

  // Register write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      global_en <= 1'b0;
      ch_en     <= 4'b0000;
      period    <= 32'h0;
      duty[0]   <= 32'h0;
      duty[1]   <= 32'h0;
      duty[2]   <= 32'h0;
      duty[3]   <= 32'h0;
    end else if (we) begin
      case (addr[4:2])
        3'b000: begin global_en <= wdata[0]; ch_en <= wdata[7:4]; end
        3'b001: period  <= wdata;
        3'b010: duty[0] <= wdata;
        3'b011: duty[1] <= wdata;
        3'b100: duty[2] <= wdata;
        3'b101: duty[3] <= wdata;
        default: ;
      endcase
    end
  end

  // Counter
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      counter <= 32'h0;
    else if (global_en) begin
      if (counter >= period)
        counter <= 32'h0;
      else
        counter <= counter + 1;
    end
  end

  // PWM output compare
  assign pwm_out[0] = global_en & ch_en[0] & (counter < duty[0]);
  assign pwm_out[1] = global_en & ch_en[1] & (counter < duty[1]);
  assign pwm_out[2] = global_en & ch_en[2] & (counter < duty[2]);
  assign pwm_out[3] = global_en & ch_en[3] & (counter < duty[3]);

  // Register read
  always @(*) begin
    if (!re)
      rdata = 32'h0;
    else begin
      case (addr[4:2])
        3'b000: rdata = {24'h0, ch_en, 3'b0, global_en};
        3'b001: rdata = period;
        3'b010: rdata = duty[0];
        3'b011: rdata = duty[1];
        3'b100: rdata = duty[2];
        3'b101: rdata = duty[3];
        3'b110: rdata = counter;
        default: rdata = 32'h0;
      endcase
    end
  end

endmodule
