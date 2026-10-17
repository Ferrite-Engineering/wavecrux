// Copyright (c) WaveCrux contributors.
// SPDX-License-Identifier: 0BSD
//
// Minimal testbench around Chili.CHIPS' eduBOS5 RV32I core with the RISC-V
// Formal Interface (RVFI) compiled in (`define RISCV_FORMAL), used to capture
// a real-core RVFI trace for the WaveCrux fixture corpus.
//
// eduBOS5 is fetched at a pinned commit by the Makefile, not vendored, and
// nothing in it is modified. This file is ours and only provides clock,
// reset and the two memories, wired the way the core's own
// formal/rvfi_wrapper.sv wires them:
//   - IMEM: synchronous read, one clock, imem_rdy tied high.
//   - DMEM: a read is a request (dmem_vld) without write strobes, and
//     dmem_rdy answers it for one clock, on the clock after the request.
//     The wrapper leaves that timing free; this is its fastest legal choice.
//     A request with write strobes is a store and needs no answer.
//
// The RVFI channels are shown through the core's own wavecrux/soc_cpu_view.sv,
// instantiated as cpu_view the way the openPCIE simulation does, so the RVFI
// names, widths and the scope they sit in are upstream's, not ours.
//
// Reset (arst_n, active low) is asserted from time zero across two rising
// clock edges and released on a falling edge. The program image is produced
// by assemble.py; no RISC-V toolchain is required.

`timescale 1ns / 1ps

module tb_edubos5_rvfi;

  localparam int unsigned MemWords = 256;  // 1 KiB per memory
  localparam int unsigned RunClocks = 49;  // clocks after reset release

  logic clk = 1'b0;
  logic arst_n = 1'b0;

  always #5 clk = ~clk;  // 100 MHz, first rising edge at 5 ns

  // ---------------------------------------------------------------------
  // RVFI, as eduBOS5 drives it
  // ---------------------------------------------------------------------
  logic        rvfi_valid;
  logic [63:0] rvfi_order;
  logic [31:0] rvfi_insn;
  logic        rvfi_trap;
  logic        rvfi_halt;
  logic        rvfi_intr;
  logic [ 1:0] rvfi_mode;
  logic [ 1:0] rvfi_ixl;
  logic [ 4:0] rvfi_rs1_addr;
  logic [ 4:0] rvfi_rs2_addr;
  logic [31:0] rvfi_rs1_rdata;
  logic [31:0] rvfi_rs2_rdata;
  logic [ 4:0] rvfi_rd_addr;
  logic [31:0] rvfi_rd_wdata;
  logic [31:0] rvfi_pc_rdata;
  logic [31:0] rvfi_pc_wdata;
  logic [31:0] rvfi_mem_addr;
  logic [ 3:0] rvfi_mem_rmask;
  logic [ 3:0] rvfi_mem_wmask;
  logic [31:0] rvfi_mem_rdata;
  logic [31:0] rvfi_mem_wdata;

  // ---------------------------------------------------------------------
  // Instruction memory
  // ---------------------------------------------------------------------
  logic [31:0] imem[MemWords];
  logic [29:0] imem_addr;  // word address
  logic [31:0] imem_rdat;

  always_ff @(posedge clk) imem_rdat <= imem[imem_addr[7:0]];

  // ---------------------------------------------------------------------
  // Data memory
  // ---------------------------------------------------------------------
  logic [31:0] dmem[MemWords];
  logic [31:0] dmem_addr;  // byte address
  logic [ 3:0] dmem_we;
  logic [31:0] dmem_wdat;
  logic [31:0] dmem_rdat;
  logic        dmem_vld;
  logic        load_wait;  // a read is pending: answer it now

  always_ff @(posedge clk) begin
    load_wait <= arst_n && dmem_vld && dmem_we == 4'b0000 && !load_wait;
    dmem_rdat <= dmem[dmem_addr[9:2]];
    if (dmem_vld) begin
      for (int unsigned b = 0; b < 4; b++) begin
        if (dmem_we[b]) dmem[dmem_addr[9:2]][8*b+:8] <= dmem_wdat[8*b+:8];
      end
    end
  end

  // ---------------------------------------------------------------------
  // DUT: eduBOS5, 2-stage pipeline (EN_WAIT4REGS = 0, the default)
  // ---------------------------------------------------------------------
  edubos5 #(
      .EN_WAIT4REGS(0)
  ) u_edubos5 (
      .clk   (clk),
      .arst_n(arst_n),

      .rvfi_valid    (rvfi_valid),
      .rvfi_order    (rvfi_order),
      .rvfi_insn     (rvfi_insn),
      .rvfi_trap     (rvfi_trap),
      .rvfi_halt     (rvfi_halt),
      .rvfi_intr     (rvfi_intr),
      .rvfi_mode     (rvfi_mode),
      .rvfi_ixl      (rvfi_ixl),
      .rvfi_rs1_addr (rvfi_rs1_addr),
      .rvfi_rs2_addr (rvfi_rs2_addr),
      .rvfi_rs1_rdata(rvfi_rs1_rdata),
      .rvfi_rs2_rdata(rvfi_rs2_rdata),
      .rvfi_rd_addr  (rvfi_rd_addr),
      .rvfi_rd_wdata (rvfi_rd_wdata),
      .rvfi_pc_rdata (rvfi_pc_rdata),
      .rvfi_pc_wdata (rvfi_pc_wdata),
      .rvfi_mem_addr (rvfi_mem_addr),
      .rvfi_mem_rmask(rvfi_mem_rmask),
      .rvfi_mem_wmask(rvfi_mem_wmask),
      .rvfi_mem_rdata(rvfi_mem_rdata),
      .rvfi_mem_wdata(rvfi_mem_wdata),

      .imem_addr(imem_addr),
      .imem_rdat(imem_rdat),
      .imem_rdy (1'b1),
      .imem_vld (),

      .dmem_addr  (dmem_addr),
      .dmem_we    (dmem_we),
      .dmem_strobe(),
      .dmem_wdat  (dmem_wdat),
      .dmem_rdat  (dmem_rdat),
      .dmem_rdy   (load_wait),
      .dmem_vld   (dmem_vld)
  );

  // ---------------------------------------------------------------------
  // The core's own RVFI view (wavecrux/soc_cpu_view.sv)
  // ---------------------------------------------------------------------
  soc_cpu_view cpu_view (
      .clk      (clk),
      .valid    (rvfi_valid),
      .order    (rvfi_order),
      .insn     (rvfi_insn),
      .trap     (rvfi_trap),
      .halt     (rvfi_halt),
      .intr     (rvfi_intr),
      .rs1_addr (rvfi_rs1_addr),
      .rs2_addr (rvfi_rs2_addr),
      .rs1_rdata(rvfi_rs1_rdata),
      .rs2_rdata(rvfi_rs2_rdata),
      .rd_addr  (rvfi_rd_addr),
      .rd_wdata (rvfi_rd_wdata),
      .pc_rdata (rvfi_pc_rdata),
      .pc_wdata (rvfi_pc_wdata),
      .mem_addr (rvfi_mem_addr),
      .mem_rmask(rvfi_mem_rmask),
      .mem_wmask(rvfi_mem_wmask),
      .mem_rdata(rvfi_mem_rdata),
      .mem_wdata(rvfi_mem_wdata)
  );

  // ---------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------
  initial begin
    $readmemh("prog.hex", imem);
    for (int unsigned k = 0; k < MemWords; k++) dmem[k] = 32'h0;

    $dumpfile("riscv_edubos5_rvfi_reset.fst");
    $dumpvars;

    repeat (2) @(negedge clk);
    arst_n = 1'b1;  // at 20 ns, after rising edges at 5 and 15 ns

    // Three passes through the loop body: stop on the falling edge after the
    // third jal has retired, before the fourth pass begins.
    repeat (RunClocks) @(negedge clk);
    $finish;
  end

  // A plain-text account of the RVFI stream, for cross-checking the capture
  // against prog.lst by eye. Sampled mid-cycle on the falling edge, plus once
  // at 1 ns, inside the window before the first rising edge.
  task automatic show();
    if (rvfi_valid) begin
      $display("%0d ns  arst_n=%0d  order=%0d  pc=%08h  insn=%08h  rd=x%0d<=%08h  pc_wdata=%08h",
               $time, arst_n, rvfi_order, rvfi_pc_rdata, rvfi_insn, rvfi_rd_addr,
               rvfi_rd_wdata, rvfi_pc_wdata);
    end
  endtask

  initial #1 show();
  always @(negedge clk) show();

endmodule
