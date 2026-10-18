# Capture an OpenHW CV32E40X RVFI trace under Verilator.
#
# Produces cv32e40x_rvfi.fst by simulating OpenHW's cv32e40x_wrapper (the
# core plus its behavioural RVFI monitor), running a small hand-assembled
# RV32I + Zicsr program, and trimming the resulting waveform down to clock,
# reset and the 21 RVFI channels WaveCrux knows about. `make debug` builds
# the debug-entry / Zcmp variant, cv32e40x_rvfi_debug.fst, from the same
# simulator binary.
#
# This is a recipe only: no fixture built here is committed, so there is no
# install target. See README.md.
#
# CV32E40X is NOT vendored: upstream's manifest lists 52 RTL and behavioural
# files. The core is fetched at a pinned commit instead, so the build is
# still exactly reproducible.
#
# No RISC-V toolchain is required: assemble.py hand-encodes the program.
#
# Requirements: verilator (>= 5.0, built with FST support), gtkwave's
# fst2vcd + vcd2fst, python3, git. Set TOOLS=<dir> to prepend a tool
# directory (an oss-cad-suite bin/, say) to PATH.
#
# Usage:
#   make            # fetch + build + run + trim, emit cv32e40x_rvfi.fst
#   make debug      # same simulator, debug/Zcmp program -> cv32e40x_rvfi_debug.fst
#   make clean      # remove build products (keeps the core clone)
#   make distclean  # also remove the core clone

ifneq ($(TOOLS),)
  export PATH := $(TOOLS):$(PATH)
endif

FIXTURE  := cv32e40x_rvfi.fst
DEBUG_FIXTURE := cv32e40x_rvfi_debug.fst
CORE_URL := https://github.com/openhwfoundation/cv32e40x.git
CORE_SHA := d952cd63bc1b4eb58cd893c28ef8283c781e345e
CORE     := core

# Homebrew keeps lz4 (needed by Verilator's FST writer) outside the default
# search paths on macOS. Harmless elsewhere.
LZ4_PREFIX ?= $(shell brew --prefix lz4 2>/dev/null)
ifneq ($(LZ4_PREFIX),)
  LZ4_CFLAGS  := -CFLAGS "-I$(LZ4_PREFIX)/include"
  LZ4_LDFLAGS := -LDFLAGS "-L$(LZ4_PREFIX)/lib"
endif

all: $(FIXTURE)

# Shallow single-commit fetch: pins exactly, without pulling CV32E40X's history.
$(CORE)/.pinned:
	rm -rf $(CORE)
	git init -q $(CORE)
	cd $(CORE) && git remote add origin $(CORE_URL)
	cd $(CORE) && git fetch -q --depth 1 origin $(CORE_SHA)
	cd $(CORE) && git checkout -q --detach FETCH_HEAD
	touch $@

# Verilator crashes on one interface-port connection in the upstream wrapper;
# patch_wrapper.py writes a copy with that connection rewritten.
cv32e40x_wrapper_vl.sv: $(CORE)/.pinned patch_wrapper.py
	python3 patch_wrapper.py $(CORE)/bhv/cv32e40x_wrapper.sv $@

# Upstream's own file list, with ${DESIGN_RTL_DIR} resolved and the wrapper
# swapped for the patched copy.
cv32e40x.f: $(CORE)/.pinned
	sed "s#\$${DESIGN_RTL_DIR}#$(CURDIR)/$(CORE)/rtl#g" $(CORE)/cv32e40x_manifest.flist \
	  | grep -v '^//' \
	  | sed "s#^.*bhv/cv32e40x_wrapper.sv\$$#$(CURDIR)/cv32e40x_wrapper_vl.sv#" > $@

prog.hex prog.lst: assemble.py
	python3 assemble.py prog.hex prog.lst

prog_debug.hex prog_debug.lst: assemble.py
	python3 assemble.py --debug prog_debug.hex prog_debug.lst

# COREV_ASSERT_OFF drops the wrapper's SVA `include`s and `bind`s
# (bhv/cv32e40x_wrapper.sv:15-25 and 169-544). The sva/ files are not on the
# manifest, and a capture does not need them.
obj_dir/cvsim: cv32e40x.f cv32e40x_wrapper_vl.sv tb_cv32e40x_rvfi.sv
	verilator --binary --timing --trace-fst \
	  -Wno-fatal -Wno-lint -Wno-style \
	  +define+COREV_ASSERT_OFF \
	  $(LZ4_CFLAGS) $(LZ4_LDFLAGS) \
	  -f cv32e40x.f tb_cv32e40x_rvfi.sv \
	  --top tb_cv32e40x_rvfi -o cvsim -j 0

# Verilator ignores the scope/level arguments to $dumpvars, so the raw dump
# holds the whole hierarchy. trim.py does the selection afterwards.
raw.fst: obj_dir/cvsim prog.hex
	./obj_dir/cvsim +prog=prog.hex +dump=$@

raw_debug.fst: obj_dir/cvsim prog_debug.hex
	./obj_dir/cvsim +prog=prog_debug.hex +dump=$@

$(FIXTURE): raw.fst trim.py
	fst2vcd raw.fst > raw.vcd
	python3 trim.py raw.vcd trimmed.vcd
	vcd2fst trimmed.vcd $@

$(DEBUG_FIXTURE): raw_debug.fst trim.py
	fst2vcd raw_debug.fst > raw_debug.vcd
	python3 trim.py raw_debug.vcd trimmed_debug.vcd
	vcd2fst trimmed_debug.vcd $@

debug: $(DEBUG_FIXTURE)

clean:
	rm -rf obj_dir cv32e40x.f cv32e40x_wrapper_vl.sv \
	  prog.hex prog.lst raw.fst raw.vcd trimmed.vcd $(FIXTURE) \
	  prog_debug.hex prog_debug.lst raw_debug.fst raw_debug.vcd trimmed_debug.vcd $(DEBUG_FIXTURE)

distclean: clean
	rm -rf $(CORE)

.PHONY: all debug clean distclean
