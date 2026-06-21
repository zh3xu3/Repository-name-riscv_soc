`timescale 1ns / 1ps
module tb_debug;
  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  wire [31:0] imem_addr, imem_rdata;
  
  inst_mem #(.MEM_SIZE(256)) u_imem (
    .addr(imem_addr),
    .rdata(imem_rdata)
  );

  reg [31:0] pc;
  initial begin
    pc = 0;
    rst_n = 0;
    #25 rst_n = 1;
    
    repeat(20) begin
      @(posedge clk);
      #1;
      imem_addr = pc;
      #1;
      $display("PC=0x%08h -> rdata=0x%08h", pc, imem_rdata);
      pc = pc + 4;
    end
    $finish;
  end
endmodule
