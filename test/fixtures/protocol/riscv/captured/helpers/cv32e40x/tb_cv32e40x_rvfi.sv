// Copyright (c) WaveCrux contributors.
// SPDX-License-Identifier: 0BSD
//
// Minimal testbench around OpenHW's cv32e40x_wrapper (bhv/), which
// instantiates cv32e40x_core and the behavioural cv32e40x_rvfi monitor
// (instance rvfi_i). Used to capture a real-core RVFI trace for WaveCrux.
//
// CV32E40X is fetched at a pinned commit by the Makefile, not vendored.
// The core RTL and the RVFI monitor are used unmodified; the wrapper is
// compiled from a copy with one port connection rewritten for Verilator
// (see patch_wrapper.py). Port tie-offs follow cv32e40x-dv's
// tb/uvmt/uvmt_cv32e40x_dut_wrap.sv; parameters are the wrapper defaults
// (RV32I + M, no A/B/X, no CLIC, DEBUG=1, PMA_NUM_REGIONS=0). Zca/Zcb/Zcmp
// are always present: ZC_EXT is a localparam of cv32e40x_core.
//
// Plusargs: +prog=<hex> (default prog.hex), +dump=<fst> (default raw.fst).
//
// Memory: 2 KiB, separate OBI instruction and data ports, gnt = req
// (combinational), rvalid one cycle later, in order.
// Doorbells (data port only): store to 0x3F0 raises irq_i[7] (MTIP);
// store to 0x3F4 clears it; store to 0x3F8 raises debug_req_i, held until
// debug_halted_o.

// (no timescale: CV32E40X RTL declares none)

module tb_cv32e40x_rvfi;

  localparam int unsigned MemWords = 512;  // 2 KiB
  localparam int unsigned AddrMsb  = 10;

  logic clk = 1'b0;
  // rst_n starts high and is driven low at t=1 so the asynchronous resets
  // see a real negedge. Verilator is two-state: a reset that is 0 from t=0
  // never fires 'negedge rst_n', and flops on CV32E40X's gated clock (which
  // does not toggle during reset) would keep Verilator's zero init instead of
  // their RESETVALUE (mtvec.MODE comes up 0, direct, instead of 1).
  logic rst_n = 1'b1;
  always #5 clk = ~clk;

  logic [31:0] mem[MemWords];

  logic        instr_req, instr_gnt, instr_rvalid;
  logic [31:0] instr_addr, instr_rdata;

  logic        data_req, data_gnt, data_rvalid, data_we;
  logic [ 3:0] data_be;
  logic [31:0] data_addr, data_wdata, data_rdata;

  logic        irq_mti = 1'b0;
  logic        dbg_req = 1'b0;
  logic        dbg_halted;
  logic [63:0] mcycle;

  assign instr_gnt = instr_req;
  assign data_gnt  = data_req;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid <= 1'b0;
      instr_rdata  <= 32'h0;
      data_rvalid  <= 1'b0;
      data_rdata   <= 32'h0;
      irq_mti      <= 1'b0;
      dbg_req      <= 1'b0;
    end else begin
      if (dbg_halted) dbg_req <= 1'b0;
      instr_rvalid <= instr_req;
      if (instr_req) instr_rdata <= mem[instr_addr[AddrMsb:2]];

      data_rvalid <= data_req;
      if (data_req) begin
        if (data_we) begin
          for (int unsigned b = 0; b < 4; b++)
            if (data_be[b]) mem[data_addr[AddrMsb:2]][8*b+:8] <= data_wdata[8*b+:8];
          data_rdata <= 32'h0;
          if (data_addr == 32'h3F0) irq_mti <= 1'b1;
          if (data_addr == 32'h3F4) irq_mti <= 1'b0;
          if (data_addr == 32'h3F8) dbg_req <= 1'b1;
        end else begin
          data_rdata <= mem[data_addr[AddrMsb:2]];
        end
      end
    end
  end

  cv32e40x_if_xif xif ();

  cv32e40x_wrapper #(
      .CORE_LOG_ENABLE(0)
  ) wrapper_i (
      .clk_i (clk),
      .rst_ni(rst_n),
      .scan_cg_en_i(1'b0),

      .boot_addr_i        (32'h0000_0080),
      .mtvec_addr_i       (32'h0000_0000),
      .dm_halt_addr_i     (32'h0000_0600),
      .mhartid_i          (32'h0),
      .mimpid_patch_i     (4'h0),
      .dm_exception_addr_i(32'h1A11_0808),

      .instr_req_o    (instr_req),
      .instr_gnt_i    (instr_gnt),
      .instr_rvalid_i (instr_rvalid),
      .instr_addr_o   (instr_addr),
      .instr_memtype_o(),
      .instr_prot_o   (),
      .instr_dbg_o    (),
      .instr_rdata_i  (instr_rdata),
      .instr_err_i    (1'b0),

      .data_req_o    (data_req),
      .data_gnt_i    (data_gnt),
      .data_rvalid_i (data_rvalid),
      .data_we_o     (data_we),
      .data_be_o     (data_be),
      .data_addr_o   (data_addr),
      .data_memtype_o(),
      .data_prot_o   (),
      .data_dbg_o    (),
      .data_wdata_o  (data_wdata),
      .data_rdata_i  (data_rdata),
      .data_err_i    (1'b0),
      .data_atop_o   (),
      .data_exokay_i (1'b0),

      .mcycle_o(mcycle),
      .time_i  (mcycle),

      .xif_compressed_if(xif.cpu_compressed),
      .xif_issue_if     (xif.cpu_issue),
      .xif_commit_if    (xif.cpu_commit),
      .xif_mem_if       (xif.cpu_mem),
      .xif_mem_result_if(xif.cpu_mem_result),
      .xif_result_if    (xif.cpu_result),

      .irq_i   ({24'b0, irq_mti, 7'b0}),
      .wu_wfe_i(1'b0),

      .clic_irq_i      (1'b0),
      .clic_irq_id_i   ('0),
      .clic_irq_level_i(8'h0),
      .clic_irq_priv_i (2'h0),
      .clic_irq_shv_i  (1'b0),

      .fencei_flush_req_o(),
      .fencei_flush_ack_i(1'b1),

      .debug_req_i      (dbg_req),
      .debug_havereset_o(),
      .debug_running_o  (),
      .debug_halted_o   (dbg_halted),
      .debug_pc_valid_o (),
      .debug_pc_o       (),

      .fetch_enable_i(1'b1),
      .core_sleep_o  ()
  );

  string prog_file = "prog.hex";
  string dump_file = "raw.fst";

  initial begin
    void'($value$plusargs("prog=%s", prog_file));
    void'($value$plusargs("dump=%s", dump_file));
    $readmemh(prog_file, mem);
    $dumpfile(dump_file);
    $dumpvars;
    #1 rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n <= 1'b1;
    repeat (400) @(posedge clk);
    $finish;
  end

endmodule
