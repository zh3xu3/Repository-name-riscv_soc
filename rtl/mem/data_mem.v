`timescale 1ns / 1ps

// Data memory - sync write, async read, 1KB
// Base address: 0x0000_1000 (internal addr = addr - BASE)
module data_mem #(
    parameter MEM_SIZE = 1024, // 1024 words = 4KB
    parameter BASE_ADDR = 32'h0000_1000
)(
    input  wire        clk,
    // Read port
    input  wire [31:0] addr,
    output reg  [31:0] rdata,
    input  wire        re,
    // Write port
    input  wire [31:0] wdata,
    input  wire        we,
    input  wire [ 2:0] size   // 000=byte, 001=half, 010=word
);

  reg [7:0] mem [0:MEM_SIZE*4-1];
  wire [31:0] local_addr = addr - BASE_ADDR;

  wire [31:0] word_addr = {local_addr[31:2], 2'b00};

  // Async read with size handling
  always @(*) begin
    if (!re) begin
      rdata = 32'b0;
    end else begin
      case (size)
        3'b000: rdata = {{24{mem[local_addr][7]}}, mem[local_addr]};          // LB
        3'b001: rdata = {{16{mem[local_addr+1][7]}}, mem[local_addr+1], mem[local_addr]}; // LH
        3'b100: rdata = {24'b0, mem[local_addr]};                             // LBU
        3'b101: rdata = {16'b0, mem[local_addr+1], mem[local_addr]};          // LHU
        default: rdata = {mem[word_addr+3], mem[word_addr+2],                 // LW
                          mem[word_addr+1], mem[word_addr]};
      endcase
    end
  end

  always @(posedge clk) begin
    if (we) begin
      case (size[1:0])
        2'b00: mem[local_addr] <= wdata[7:0];                                    // SB
        2'b01: begin mem[local_addr] <= wdata[7:0]; mem[local_addr+1] <= wdata[15:8]; end // SH
        default: begin                                                      // SW
          mem[word_addr]   <= wdata[7:0];
          mem[word_addr+1] <= wdata[15:8];
          mem[word_addr+2] <= wdata[23:16];
          mem[word_addr+3] <= wdata[31:24];
        end
      endcase
    end
  end

endmodule
