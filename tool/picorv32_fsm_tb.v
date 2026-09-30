// Minimal self-contained testbench that drives the upstream picorv32 core
// through a tiny hand-encoded RV32I program and dumps its one-hot `cpu_state`
// FSM register. Used to capture a real-IP FSM fixture for WaveCrux's FSM
// golden sweep. No RISC-V toolchain required — the program is inlined as hex.
`timescale 1ns / 1ps

module tb;
  reg clk = 0;
  reg resetn = 0;
  always #5 clk = ~clk; // 100 MHz

  wire        trap;
  wire        mem_valid;
  wire        mem_instr;
  reg         mem_ready;
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  wire [ 3:0] mem_wstrb;
  reg  [31:0] mem_rdata;

  // Behavioral 1-cycle-latency memory holding the program.
  reg [31:0] memory [0:255];

  initial begin
    // addi x1, x0, 5
    memory[0] = 32'h00500093;
    // addi x2, x0, 3
    memory[1] = 32'h00300113;
    // add  x3, x1, x2
    memory[2] = 32'h002081b3;
    // sll  x4, x1, x2   (exercises the `shift` state)
    memory[3] = 32'h00209233;
    // sw   x3, 64(x0)   (exercises the `stmem` state)
    memory[4] = 32'h04302023;
    // lw   x5, 64(x0)   (exercises the `ldmem` state)
    memory[5] = 32'h04002283;
    // jal  x0, 0        (spin in place — bounded, no trap)
    memory[6] = 32'h0000006f;
  end

  always @(posedge clk) begin
    mem_ready <= 0;
    if (mem_valid && !mem_ready) begin
      mem_ready <= 1;
      if (mem_wstrb == 4'b0000) begin
        mem_rdata <= memory[mem_addr >> 2];
      end else begin
        if (mem_wstrb[0]) memory[mem_addr >> 2][ 7: 0] <= mem_wdata[ 7: 0];
        if (mem_wstrb[1]) memory[mem_addr >> 2][15: 8] <= mem_wdata[15: 8];
        if (mem_wstrb[2]) memory[mem_addr >> 2][23:16] <= mem_wdata[23:16];
        if (mem_wstrb[3]) memory[mem_addr >> 2][31:24] <= mem_wdata[31:24];
      end
    end
  end

  picorv32 #(
    .ENABLE_COUNTERS(0),
    .ENABLE_IRQ(0),
    .BARREL_SHIFTER(0),
    .ENABLE_REGS_DUALPORT(0) // force the separate ld_rs2 state
  ) uut (
    .clk(clk),
    .resetn(resetn),
    .trap(trap),
    .mem_valid(mem_valid),
    .mem_instr(mem_instr),
    .mem_ready(mem_ready),
    .mem_addr(mem_addr),
    .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb),
    .mem_rdata(mem_rdata),
    .mem_la_read(),
    .mem_la_write(),
    .mem_la_addr(),
    .mem_la_wdata(),
    .mem_la_wstrb(),
    .pcpi_valid(),
    .pcpi_insn(),
    .pcpi_rs1(),
    .pcpi_rs2(),
    .pcpi_wr(1'b0),
    .pcpi_rd(32'b0),
    .pcpi_wait(1'b0),
    .pcpi_ready(1'b0),
    .irq(32'b0),
    .eoi(),
    .trace_valid(),
    .trace_data()
  );

  initial begin
    $dumpfile("picorv32_state.vcd");
    // Dump only the FSM register — that is all the fixture needs.
    $dumpvars(0, tb.uut.cpu_state);
    repeat (4) @(posedge clk);
    resetn <= 1;
    repeat (120) @(posedge clk);
    $finish;
  end
endmodule
