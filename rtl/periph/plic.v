`timescale 1ns / 1ps

// Platform-Level Interrupt Controller (PLIC)
// 16 interrupt sources, priority-based arbitration
//
// Register map (word-aligned, 6-bit address):
//   0x00: PENDING   (RO: pending interrupt bits)
//   0x04: ENABLE    (RW: interrupt enable bits)
//   0x08: THRESHOLD (RW: priority threshold)
//   0x0C: CLAIM     (RO: claim / WO: complete)
module plic #(
    parameter NUM_SRC = 16
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    input  wire        we,
    input  wire        re,
    input  wire [NUM_SRC-1:0] irq_src,
    output wire        irq_out
);

  reg [NUM_SRC-1:0] pending;
  reg [NUM_SRC-1:0] enable;
  reg [3:0]  threshold;

  // Rising-edge detect for level-sensitive sources
  reg [NUM_SRC-1:0] src_d;
  wire [NUM_SRC-1:0] rising = irq_src & ~src_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      src_d <= {NUM_SRC{1'b0}};
    else
      src_d <= irq_src;
  end

  // Pending register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pending <= {NUM_SRC{1'b0}};
    else begin
      pending <= pending | rising;
      // Clear on complete write
      if (we && addr[3:0] == 4'hC && wdata[4:0] < NUM_SRC[4:0])
        pending[wdata[4:0]] <= 1'b0;
    end
  end

  // Find highest-number pending enabled source
  reg [4:0] best_id;
  integer i;
  always @(*) begin
    best_id = 5'd0;
    for (i = NUM_SRC-1; i >= 0; i = i - 1)
      if (pending[i] && enable[i])
        best_id = i[4:0];
  end

  assign irq_out = |(pending & enable);

  // Register write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      enable    <= {NUM_SRC{1'b0}};
      threshold <= 4'h0;
    end else if (we) begin
      case (addr[3:0])
        4'h4: enable    <= wdata[NUM_SRC-1:0];
        4'h8: threshold <= wdata[3:0];
        default: ;
      endcase
    end
  end

  // Register read
  always @(*) begin
    if (!re)
      rdata = 32'h0;
    else begin
      case (addr[3:0])
        4'h0: rdata = {{(32-NUM_SRC){1'b0}}, pending};
        4'h4: rdata = {{(32-NUM_SRC){1'b0}}, enable};
        4'h8: rdata = {28'h0, threshold};
        4'hC: rdata = {27'h0, best_id};
        default: rdata = 32'h0;
      endcase
    end
  end

endmodule
