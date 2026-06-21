`timescale 1ns / 1ps

// Iterative divider for RV32M (DIV/DIVU/REM/REMU)
// 32-cycle shift-and-subtract.
// done pulses for 1 cycle on completion (cnt==31).
// busy stays high until cnt==32 to keep pipeline stalled during done cycle.
module divider (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        is_signed,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder,
    output reg         done
);

  reg        busy;
  reg [ 5:0] cnt;
  reg [31:0] abs_b;
  reg [63:0] rem;
  reg        neg_q, neg_r;
  reg [31:0] q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy      <= 1'b0;
      cnt       <= 6'h0;
      done      <= 1'b0;
      quotient  <= 32'h0;
      remainder <= 32'h0;
    end else if (start) begin
      // RISC-V spec: divide by zero returns defined values
      if (b == 32'h0) begin
        done      <= 1'b1;
        quotient  <= 32'hFFFFFFFF;           // DIV/DIVU: -1
        remainder <= a;                       // REM/REMU: dividend
        busy      <= 1'b1;                    // hold for freeze cycle
        cnt       <= 6'd32;
      end else begin
        busy      <= 1'b1;
        cnt       <= 6'd0;
        done      <= 1'b0;
        abs_b     <= is_signed && b[31] ? -b : b;
        neg_q     <= is_signed && (a[31] ^ b[31]);
        neg_r     <= is_signed && a[31];
        rem       <= {32'h0, is_signed && a[31] ? -a : a};
        q         <= 32'h0;
      end
    end else if (busy) begin
      if (cnt == 6'd31) begin
        // Final iteration: compute last bit, output results, pulse done.
        // busy stays high for 1 more cycle (cnt==32) to stall pipeline.
        rem = rem << 1;
        if (rem[63:32] >= abs_b) begin
          rem[63:32] = rem[63:32] - abs_b;
          q = {q[30:0], 1'b1};
        end else begin
          q = {q[30:0], 1'b0};
        end
        done      <= 1'b1;
        quotient  <= neg_q ? -q : q;
        remainder <= neg_r ? -rem[63:32] : rem[63:32];
        cnt       <= 6'd32;
      end else if (cnt == 6'd32) begin
        // Pipeline stalled for done cycle. Now safe to clear busy.
        done <= 1'b0;
        busy <= 1'b0;
        cnt  <= 6'h0;
      end else begin
        cnt <= cnt + 6'd1;
        rem = rem << 1;
        if (rem[63:32] >= abs_b) begin
          rem[63:32] = rem[63:32] - abs_b;
          q = {q[30:0], 1'b1};
        end else begin
          q = {q[30:0], 1'b0};
        end
      end
    end else begin
      done <= 1'b0;
    end
  end

endmodule
