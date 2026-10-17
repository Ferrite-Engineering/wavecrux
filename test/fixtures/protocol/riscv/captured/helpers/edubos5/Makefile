# Rebuild the captured eduBOS5 RVFI fixture.
#
# Produces riscv_edubos5_rvfi_reset.fst by simulating Chili.CHIPS' eduBOS5
# RV32I core with the RISC-V Formal Interface compiled in
# (+define+RISCV_FORMAL), running a small hand-assembled RV32I program, and
# trimming the resulting waveform down to clock, reset and the 21 RVFI
# channels of the core's own soc_cpu_view.
#
# eduBOS5 is NOT vendored into this repo. It lives inside the openPCIE
# repository, so the Makefile fetches exactly one commit of it, shallow and
# sparse: only 2.rtl/0.common.opensource/src/CPU.eduBOS5/ is checked out.
#
# No RISC-V toolchain is required: assemble.py hand-encodes the program.
#
# Requirements: verilator (>= 5.0, built with FST support), gtkwave's
# fst2vcd + vcd2fst, python3, git (>= 2.25, for sparse-checkout).
#
# Usage:
#   make            # fetch + build + run + trim, emit riscv_edubos5_rvfi_reset.fst
#   make install    # copy the FST into both fixture trees
#   make clean      # remove build products (keeps the openPCIE checkout)
#   make distclean  # also remove the openPCIE and riscv-formal checkouts

REPO_ROOT := $(realpath $(CURDIR)/../../../../../../..)
TEST_DST  := $(REPO_ROOT)/test/fixtures/protocol/riscv/captured
VERIF_DST := $(REPO_ROOT)/verification/fixtures/protocol/riscv/captured

FIXTURE      := riscv_edubos5_rvfi_reset.fst
OPENPCIE_URL := https://github.com/chili-chips-ba/openPCIE.git
OPENPCIE_SHA := a0d80cd3cb525f911cae61be4c83a44e137ed916
OPENPCIE     := openPCIE
CPU_DIR      := 2.rtl/0.common.opensource/src/CPU.eduBOS5
CPU          := $(OPENPCIE)/$(CPU_DIR)

# Homebrew keeps lz4 (needed by Verilator's FST writer) outside the default
# search paths on macOS. Harmless elsewhere.
LZ4_PREFIX ?= $(shell brew --prefix lz4 2>/dev/null)
ifneq ($(LZ4_PREFIX),)
  LZ4_CFLAGS  := -CFLAGS "-I$(LZ4_PREFIX)/include"
  LZ4_LDFLAGS := -LDFLAGS "-L$(LZ4_PREFIX)/lib"
endif

# gtkwave's converters. Override when the first ones on PATH are broken,
# e.g. FST2VCD=/opt/homebrew/bin/fst2vcd VCD2FST=/opt/homebrew/bin/vcd2fst.
FST2VCD ?= fst2vcd
VCD2FST ?= vcd2fst

RTL := \
  $(CPU)/edubos5_pkg.sv \
  $(CPU)/edubos5_rf.sv \
  $(CPU)/edubos5_alu.sv \
  $(CPU)/edubos5.sv \
  $(CPU)/wavecrux/soc_cpu_view.sv

all: $(FIXTURE)

# Shallow, sparse, single-commit fetch: pins exactly, without pulling
# openPCIE's history or the rest of its tree.
$(OPENPCIE)/.pinned:
	rm -rf $(OPENPCIE)
	git init -q $(OPENPCIE)
	cd $(OPENPCIE) && git remote add origin $(OPENPCIE_URL)
	cd $(OPENPCIE) && git sparse-checkout set --no-cone /$(CPU_DIR)/
	cd $(OPENPCIE) && git fetch -q --depth 1 --filter=blob:none origin $(OPENPCIE_SHA)
	cd $(OPENPCIE) && git checkout -q --detach FETCH_HEAD
	touch $@

prog.hex prog.lst: assemble.py
	python3 assemble.py prog.hex prog.lst

# Verilator ignores the scope/level arguments to $dumpvars, so the raw dump
# holds the whole hierarchy. trim.py does the selection afterwards.
#
# +verilator+rand+reset+0 states the default explicitly: every register the
# design does not initialise powers up at zero. The capture depends on it,
# see README.md ("What the capture shows at time zero").
raw.fst: $(OPENPCIE)/.pinned tb_edubos5_rvfi.sv prog.hex
	verilator --binary --timing --trace-fst \
	  -Wno-fatal -Wno-TIMESCALEMOD \
	  +define+RISCV_FORMAL \
	  $(LZ4_CFLAGS) $(LZ4_LDFLAGS) \
	  --top tb_edubos5_rvfi -o edubos5sim \
	  $(RTL) tb_edubos5_rvfi.sv
	./obj_dir/edubos5sim +verilator+rand+reset+0 > sim.log
	cat sim.log
	mv $(FIXTURE) raw.fst

$(FIXTURE): raw.fst trim.py
	$(FST2VCD) raw.fst > raw.vcd
	python3 trim.py raw.vcd trimmed.vcd
	$(VCD2FST) trimmed.vcd $(FIXTURE)

install: $(FIXTURE)
	cp $(FIXTURE) $(TEST_DST)/
	cp $(FIXTURE) $(VERIF_DST)/

clean:
	rm -rf obj_dir raw.fst raw.vcd trimmed.vcd sim.log prog.hex prog.lst $(FIXTURE)

distclean: clean
	rm -rf $(OPENPCIE) riscv-formal/riscv-formal-src

.PHONY: all install clean distclean
