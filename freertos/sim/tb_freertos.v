`timescale 1ns / 1ps

module tb_freertos;

  reg clk, rst_n;
  initial clk = 0;
  always #5 clk = ~clk;

  wire uart_tx_pin;
  wire uart_rx_pin = uart_tx_pin;
  wire [31:0] gpio_out;
  wire [31:0] gpio_in = gpio_out;

  soc_top #(
    .CLK_FREQ(100_000_000),
    .BAUD(115200)
  ) u_dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .uart_tx  (uart_tx_pin),
    .uart_rx  (uart_rx_pin),
    .gpio_o   (gpio_out),
    .gpio_i   (gpio_in),
    .dbg_x1   (),
    .dbg_x2   (),
    .dbg_x3   (),
    .dbg_x4   (),
    .dbg_x5   (),
    .dbg_x6   (),
    .dbg_x7   (),
    .dbg_x8   (),
    .dbg_x12  (),
    .dbg_x13  (),
    .dbg_x14  (),
    .dbg_x15  ()
  );

  initial begin
    $dumpfile("wave_freertos.vcd");
    $dumpvars(0, tb_freertos);
  end

  integer pass_count, fail_count;

  task check;
    input [31:0] actual;
    input [31:0] expected;
    input [8*30-1:0] name;
    begin
      if (actual === expected) begin
        $display("  PASS: 0x%08h  (%0s)", actual, name);
        pass_count = pass_count + 1;
      end else begin
        $display("  FAIL: got 0x%08h, expected 0x%08h  (%0s)", actual, expected, name);
        fail_count = fail_count + 1;
      end
    end
  endtask

  function [31:0] read_dmem;
    input [31:0] byte_offset;
    begin
      read_dmem = {u_dut.u_dmem.mem[byte_offset+3],
                   u_dut.u_dmem.mem[byte_offset+2],
                   u_dut.u_dmem.mem[byte_offset+1],
                   u_dut.u_dmem.mem[byte_offset]};
    end
  endfunction

  reg [31:0] gpio_result, uart_result;
  reg [31:0] prev_pc;
  integer cycle_cnt;
  reg [31:0] tcb_ptr, sp_ptr, ctx_mepc;
  reg [31:0] prev_mepc;

  initial begin
    pass_count = 0;
    fail_count = 0;
    prev_pc = 32'hFFFFFFFF;
    cycle_cnt = 0;

    $display("");
    $display("===== FreeRTOS RISC-V SoC Test =====");
    $display("");

    rst_n = 0;
    #25;
    rst_n = 1;

    // Early snapshots to catch the restart loop
    #10000;  // 10us
    $display("=== DMEM @ 10us ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  uxCurrentNumTasks @ 0x534 = 0x%08h", read_dmem(32'h534));
    $display("  xSchedulerInit @ 0x52c = 0x%08h", read_dmem(32'h52c));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  PC = 0x%08h", u_dut.u_core.pc);

    #10000;  // 20us
    $display("=== DMEM @ 20us ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  uxCurrentNumTasks @ 0x534 = 0x%08h", read_dmem(32'h534));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  PC = 0x%08h", u_dut.u_core.pc);

    #10000;  // 30us
    $display("=== DMEM @ 30us ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  uxCurrentNumTasks @ 0x534 = 0x%08h", read_dmem(32'h534));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  PC = 0x%08h", u_dut.u_core.pc);
    $display("  --- Heap ---");
    $display("  pxEnd @ 0x1548 = 0x%08h", read_dmem(32'h548));
    $display("  xFreeBytesRemaining @ 0x1544 = 0x%08h", read_dmem(32'h544));
    $display("  xStart.pxNextFreeBlock @ 0x154c = 0x%08h", read_dmem(32'h54c));
    $display("  xStart.xBlockSize @ 0x1550 = 0x%08h", read_dmem(32'h550));
    $display("  ucHeap[0] (block header) @ 0x1124 = 0x%08h", read_dmem(32'h124));
    $display("  ucHeap[1] (block size)  @ 0x1128 = 0x%08h", read_dmem(32'h128));

    #10000;  // 40us
    $display("=== DMEM @ 40us ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  uxCurrentNumTasks @ 0x534 = 0x%08h", read_dmem(32'h534));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  PC = 0x%08h", u_dut.u_core.pc);
    $display("  --- Heap ---");
    $display("  xStart.pxNextFreeBlock @ 0x154c = 0x%08h", read_dmem(32'h54c));
    $display("  xStart.xBlockSize @ 0x1550 = 0x%08h", read_dmem(32'h550));
    $display("  ucHeap[0..1] @ 0x1124 = 0x%08h 0x%08h", read_dmem(32'h124), read_dmem(32'h128));

    #60000;  // 100us total
    // Wait for scheduler to start, then dump DMEM
    $display("=== DMEM @ 100us ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    tcb_ptr = read_dmem(32'h528);
    if (tcb_ptr != 0 && tcb_ptr >= 32'h1000 && tcb_ptr < 32'h2000) begin
      sp_ptr = read_dmem(tcb_ptr - 32'h1000);
      $display("  TCB @ 0x%08h, pxTopOfStack = 0x%08h", tcb_ptr, sp_ptr);
      if (sp_ptr >= 32'h1000 && sp_ptr < 32'h2000) begin
        ctx_mepc = read_dmem(sp_ptr - 32'h1000);
        $display("  ctx[0] (mepc) = 0x%08h", ctx_mepc);
        $display("  ctx[1] (ra)   = 0x%08h", read_dmem(sp_ptr - 32'h1000 + 4));
        $display("  ctx[2] (sp)   = 0x%08h", read_dmem(sp_ptr - 32'h1000 + 8));
        $display("  ctx[3] (gp)   = 0x%08h", read_dmem(sp_ptr - 32'h1000 + 12));
        $display("  ctx[8] (s0)   = 0x%08h", read_dmem(sp_ptr - 32'h1000 + 32));
        $display("  ctx[10](a0)   = 0x%08h", read_dmem(sp_ptr - 32'h1000 + 40));
      end
    end
    $display("  xSchedulerInit @ 0x52c = 0x%08h", read_dmem(32'h52c));
    $display("  uxCurrentNumTasks @ 0x534 = 0x%08h", read_dmem(32'h534));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  mstatus CSR = 0x%08h", u_dut.u_core.u_csr.mstatus);
    $display("  mie CSR = 0x%08h", u_dut.u_core.u_csr.mie);
    $display("  mtvec CSR = 0x%08h", u_dut.u_core.u_csr.mtvec);
    $display("  PC = 0x%08h", u_dut.u_core.pc);
    $display("  trap frame s0 @ DMEM[0x1428] = 0x%08h", read_dmem(32'h428));
    $display("  trap frame mepc @ DMEM[0x1408] = 0x%08h", read_dmem(32'h408));
    $display("  reg x10 (a0) = 0x%08h", u_dut.u_core.u_rf.regs[10]);
    $display("  reg x8  (s0) = 0x%08h", u_dut.u_core.u_rf.regs[8]);

    #100000;  // 200us total
    $display("=== DMEM @ 200us ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  mstatus CSR = 0x%08h", u_dut.u_core.u_csr.mstatus);
    $display("  mie CSR = 0x%08h", u_dut.u_core.u_csr.mie);
    $display("  mip CSR = 0x%08h", u_dut.u_core.u_csr.mip);
    $display("  mtime = 0x%08h", u_dut.u_core.u_csr.mtime[31:0]);
    $display("  mtimecmp = 0x%08h", u_dut.u_core.u_csr.mtimecmp[31:0]);
    $display("  PC = 0x%08h", u_dut.u_core.pc);

    #800000;  // 1ms total (first timer tick should fire here)
    $display("=== DMEM @ 1ms ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  mstatus CSR = 0x%08h", u_dut.u_core.u_csr.mstatus);
    $display("  mie CSR = 0x%08h", u_dut.u_core.u_csr.mie);
    $display("  mip CSR = 0x%08h", u_dut.u_core.u_csr.mip);
    $display("  mtime = 0x%08h", u_dut.u_core.u_csr.mtime[31:0]);
    $display("  mtimecmp = 0x%08h", u_dut.u_core.u_csr.mtimecmp[31:0]);
    $display("  irq_pending = %b", u_dut.u_core.u_csr.irq_pending);
    $display("  PC = 0x%08h", u_dut.u_core.pc);

    #50000;  // 1.05ms (after first timer tick)
    $display("=== DMEM @ 1.05ms ===");
    $display("  pxCurrentTCB @ 0x1528 = 0x%08h", read_dmem(32'h528));
    $display("  ASM trap save mepc @ DMEM[0xFFC] = 0x%08h", read_dmem(32'hFFC));
    $display("  ASM restore mepc @ DMEM[0xFF8] = 0x%08h", read_dmem(32'hFF8));
    $display("  C handler entry pxContext @ DMEM[0x1F0] = 0x%08h", read_dmem(32'h1F0));
    $display("  C handler entry mepc @ DMEM[0x1F4] = 0x%08h", read_dmem(32'h1F4));
    $display("  C handler switch @ DMEM[0x1E8] = 0x%08h", read_dmem(32'h1E8));
    $display("  C handler mepc after skip @ DMEM[0x1EC] = 0x%08h", read_dmem(32'h1EC));
    $display("  C handler new ctx @ DMEM[0x1E0] = 0x%08h", read_dmem(32'h1E0));
    $display("  C handler new mepc @ DMEM[0x1E4] = 0x%08h", read_dmem(32'h1E4));
    $display("  C handler exit ctx @ DMEM[0x1D8] = 0x%08h", read_dmem(32'h1D8));
    $display("  C handler exit mepc @ DMEM[0x1DC] = 0x%08h", read_dmem(32'h1DC));
    $display("  mepc CSR = 0x%08h", u_dut.u_core.u_csr.mepc);
    $display("  mcause CSR = 0x%08h", u_dut.u_core.u_csr.mcause);
    $display("  mstatus CSR = 0x%08h", u_dut.u_core.u_csr.mstatus);
    $display("  PC = 0x%08h", u_dut.u_core.pc);

    // Monitor until PC goes out of range or X
    // ~1.05ms already elapsed. Need ~5ms for tasks to complete.
    // Run for 5ms total (~395,000 more cycles)
    repeat(395_000) begin
      @(posedge clk);
      #1;
      cycle_cnt = cycle_cnt + 1;

      // Print only trap entries and context switches
      if (u_dut.u_core.irq_trap) begin
        $display("[TRAP] t=%0t PC=0x%08h mepc=0x%08h mcause=0x%08h mstatus=0x%08h",
                 $time, u_dut.u_core.pc,
                 u_dut.u_core.u_csr.mepc,
                 u_dut.u_core.u_csr.mcause,
                 u_dut.u_core.u_csr.mstatus);
      end

      // Detect PC going out of range or X
      if (u_dut.u_core.pc >= 32'h1000 || u_dut.u_core.pc === 32'hxxxxxxxx) begin
        if (cycle_cnt > 100) begin
          $display("PC out of range at t=%0t PC=0x%08h", $time, u_dut.u_core.pc);
          $display("  mepc=0x%08h mcause=0x%08h mstatus=0x%08h",
                   u_dut.u_core.u_csr.mepc,
                   u_dut.u_core.u_csr.mcause,
                   u_dut.u_core.u_csr.mstatus);
          $display("  DMEM[0] = 0x%08h", read_dmem(0));
          $display("  DMEM[4] = 0x%08h", read_dmem(4));
          #100;
          $finish;
        end
      end
      if (u_dut.u_core.pc < 32'h1000 && u_dut.u_core.pc !== 32'hxxxxxxxx) cycle_cnt = 0;
    end

    gpio_result = read_dmem(32'hFE0);
    uart_result = read_dmem(32'hFE4);

    $display("");
    $display("===== FreeRTOS Task Results =====");
    check(gpio_result, 32'hAAAA5555, "GPIO task output");
    check(uart_result, 32'h00000055, "UART task RX loopback");

    $display("");
    $display("===== Results: %0d PASS, %0d FAIL =====", pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED!");
    else $display("SOME TESTS FAILED!");
    $display("");
    $finish;
  end

  // Debug: watch for mepc changes every cycle
  initial prev_mepc = 32'h0;
  always @(posedge clk) begin
    #1;
    if (u_dut.u_core.u_csr.mepc !== prev_mepc) begin
      $display("[MEPC CHANGE] t=%0t mepc=0x%08h->0x%08h mcause=0x%08h PC=0x%08h irq_trap=%b memwb_is_ecall=%b trap=%b csr_we=%b csr_addr=0x%03h csr_wdata=0x%08h",
               $time, prev_mepc, u_dut.u_core.u_csr.mepc, u_dut.u_core.u_csr.mcause,
               u_dut.u_core.pc, u_dut.u_core.irq_trap,
               u_dut.u_core.memwb_is_ecall,
               u_dut.u_core.u_csr.trap,
               u_dut.u_core.u_csr.we,
               u_dut.u_core.u_csr.addr,
               u_dut.u_core.u_csr.wdata);
      prev_mepc = u_dut.u_core.u_csr.mepc;
    end
  end

endmodule
