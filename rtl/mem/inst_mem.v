`timescale 1ns / 1ps

// Instruction memory - async read, 1KB
module inst_mem #(
    parameter MEM_SIZE = 1024 // 1024 words = 4KB
)(
    input  wire [31:0] addr,
    output wire [31:0] rdata
);

  reg [31:0] mem [0:MEM_SIZE-1];

  // Load program from hex file
  initial begin
    $readmemh("inst_mem.hex", mem);  // Vivado: add .hex as Memory Init File
  end

  assign rdata = mem[addr[31:2]];  // Word-aligned access

endmodule
