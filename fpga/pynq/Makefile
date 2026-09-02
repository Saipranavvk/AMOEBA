# FPGA build for the PYNQ-Z2 (Zynq XC7Z020-1CLG400).
#
#   make lint                      Verilator elaboration check -- no Vivado needed
#   make dryrun                    exercise the synthesis TCL with Vivado stubbed out
#   make utilization               out-of-context synthesis, area + timing reports
#   make utilization-all           the same for every config, into one summary
#   make clean
#
# The utilization target is the gate that turns the LUT estimates in the plan
# into facts.  It needs Vivado (ML Standard covers xc7z020 at no cost) and
# nothing else -- no board, no bitstream, no block design.
#
# `lint` is the only part that runs without Vivado.  There is no local
# substitute for the area number: Verilator is a simulator and does not count
# flip-flops or LUTs, and yosys cannot read this SystemVerilog without sv2v --
# and would map to its own primitives, not Xilinx's, so the answer would be
# wrong in a way that looks right.  Run lint here, run the gate on a Vivado box.

SHELL := /bin/bash -o pipefail
.SHELLFLAGS += -e

REPO      := $(abspath $(CURDIR)/../..)
BUILD     := $(CURDIR)/build
REPORTS   := $(CURDIR)/reports

# ---- part ------------------------------------------------------------------
# PYNQ-Z2: Zynq-7020, -1 speed grade, CLG400 package.
XILINX_PART ?= xc7z020clg400-1

# Wally's own Arty A7 build runs at 20 MHz on the same -1 grade 7-series fabric,
# so 25 MHz is a starting point, not a target.  Read the WNS and move.
FCLK_MHZ    ?= 25
CLK_PERIOD_NS = $(shell echo "scale=3; 1000 / $(FCLK_MHZ)" | bc)

# ---- configuration ---------------------------------------------------------
# Same CONFIG names as sim/Makefile, synth/Makefile and testcode/linux/Makefile.
# baremetal_linux is the tapeout config; the others are here so the gate can
# report all of them side by side and show what the pruning bought.
CONFIG ?= baremetal_linux
ifeq ($(CONFIG),)
  CONFIG_DEFINES :=
else ifeq ($(CONFIG),freertos)
  CONFIG_DEFINES := AMOEBA_CONFIG_FREERTOS
else ifeq ($(CONFIG),freertos_keystone)
  CONFIG_DEFINES := AMOEBA_CONFIG_FREERTOS_KEYSTONE
else ifeq ($(CONFIG),baremetal_linux)
  CONFIG_DEFINES := AMOEBA_CONFIG_BAREMETAL_LINUX
else
  $(error CONFIG=$(CONFIG) is not a known configuration -- use freertos, freertos_keystone, baremetal_linux, or leave it unset for pkg/config.vh)
endif

CONFIG_TAG := $(if $(CONFIG),$(CONFIG),full)
REPORT_TAG := $(CONFIG_TAG)$(if $(filter-out amoeba_soc_wrapper,$(TOP)),-$(TOP))

# ---- sources ---------------------------------------------------------------
# Mirrors sim/Makefile's discovery so the two never drift.  Package files must
# precede the modules that import them, for Verilator and for Vivado alike.
# TOP selects what gets elaborated.  Two are meaningful:
#
#   amoeba_soc_wrapper  the DUT alone -- core plus the minimal uncore.  This is
#                       the utilization gate's top, and it is what decides the
#                       tapeout cache geometry, so it must stay free of debug
#                       scaffolding.
#   amoeba_pynq_top     the whole PL: DUT plus control, monitor, trace and the
#                       memory backend.  Synthesize this to size the bitstream.
#
# Running the gate at both tops separates "what does the core cost" from "what
# does the debug plumbing cost", which are different questions with different
# answers and only one of them goes to the ASIC.
TOP        ?= amoeba_soc_wrapper
DESIGN_TOP := $(TOP)

# The two tops name their clock and reset differently, and synth_ooc.tcl needs
# to be told: create_clock on a nonexistent port is only a CRITICAL WARNING, so
# getting this wrong yields a fully synthesized, entirely unconstrained design
# that reports an empty WNS and exits 0.
ifeq ($(TOP),amoeba_pynq_top)
  CLK_PORT ?= aclk
  RST_PORT ?= aresetn
else
  CLK_PORT ?= clk
  RST_PORT ?= reset_ext
endif

PKG_SRCS   := $(REPO)/pkg/types.sv
CORE_PKG   := $(REPO)/hdl/core/cvw.sv
CORE_SRCS  := $(shell find $(REPO)/hdl/core -name '*.sv' -o -name '*.v' | grep -v '/cvw\.sv$$' | sort)
# ahb_to_memitf is shared with the Verilator tier: the FPGA's block RAM backend
# speaks the same mem_itf protocol the simulation memory does, so the adapter is
# not FPGA-only code that could rot.
SHARED_SRCS := $(REPO)/hdl/ahb_to_memitf.sv
FPGA_SRCS  := $(sort $(wildcard $(CURDIR)/rtl/*.sv) $(wildcard $(CURDIR)/rtl/*.v))

ALL_SRCS   := $(PKG_SRCS) $(CORE_PKG) $(CORE_SRCS) $(SHARED_SRCS) $(FPGA_SRCS)

INCDIRS    := $(REPO)/hdl/core $(REPO)/pkg $(REPO)/third_party/cvw/config/rv64gc

SRCS_F     := $(BUILD)/srcs_$(CONFIG_TAG).f

.PHONY: all lint dryrun utilization utilization-all bd synth-bd bitstream deploy check-regs clean

all: lint

# One source path per line.  Consumed by Verilator via -f and by
# tcl/synth_ooc.tcl via a plain read, so there is one list, not two.
$(SRCS_F): $(CURDIR)/Makefile
	@mkdir -p $(BUILD)
	@printf '%s\n' $(ALL_SRCS) > $@
	@echo "filelist: $(words $(ALL_SRCS)) sources -> $@"

# ---- lint ------------------------------------------------------------------
# Elaborates the real design at the real config.  Catches the errors that would
# otherwise surface an hour into synthesis.
.PHONY: test-mem
# The AXI image-load port, which the RTL testbenches never touch: they
# backdoor-load memory with $$readmemh, so port B first ran on hardware, where
# it deadlocked the PS.  This is that failure, reproduced.
test-mem:
	@mkdir -p $(BUILD)/tb
	verilator --binary -sv --top-module tb_mem_axi --timing \
	    --timescale 1ns/1ps -Wno-fatal -Mdir $(BUILD)/tb \
	    $(REPO)/fpga/pynq/tb/tb_mem_axi.sv \
	    $(REPO)/fpga/pynq/rtl/amoeba_mem_bram.sv \
	    $(REPO)/hdl/ahb_to_memitf.sv \
	    +incdir+$(REPO)/hdl/core +incdir+$(REPO)/pkg > $(BUILD)/tb/build.log 2>&1
	@$(BUILD)/tb/Vtb_mem_axi | grep -v '^-'
	@$(BUILD)/tb/Vtb_mem_axi | grep -q 'tb_mem_axi PASS'

lint: $(SRCS_F)
	verilator --lint-only -sv --top-module $(DESIGN_TOP) \
	    $(addprefix +incdir+,$(INCDIRS)) \
	    $(addprefix +define+,$(CONFIG_DEFINES)) \
	    $(REPO)/sim/verilator_warn.vlt \
	    -f $(SRCS_F)
	@echo "lint OK: $(DESIGN_TOP) @ CONFIG=$(CONFIG_TAG)"

# ---- TCL dry run -----------------------------------------------------------
# Runs tcl/synth_ooc.tcl in plain tclsh with every Vivado command stubbed.
# Proves the script's argument handling, control flow and command construction
# in about a second, so a typo does not surface an hour into a synthesis run on
# the one machine that has a licence.  It cannot prove Vivado likes the options.
dryrun: $(SRCS_F)
	@tclsh $(CURDIR)/scripts/tcl_dryrun.tcl $(SRCS_F)
	@bash $(CURDIR)/scripts/fit_report.sh $(BUILD)/dryrun_reports DRYRUN-STUBBED | tail -4
	@echo "dryrun OK -- synth_ooc.tcl runs end to end"

# ---- the gate --------------------------------------------------------------
# Vivado is not on PATH until settings64.sh is sourced, and the failure without
# it ("vivado: command not found", three lines into a recipe) is more confusing
# than it needs to be.
.PHONY: check-vivado
check-vivado:
	@command -v vivado >/dev/null 2>&1 || { \
	  echo "error: vivado is not on PATH."; \
	  echo "  source it first, e.g.:"; \
	  echo "    source ~/Xilinx/Vivado/2024.1/settings64.sh"; \
	  echo "  see fpga/pynq/README.md for the version this project targets"; \
	  exit 1; }
	@echo "vivado: $$(vivado -version 2>/dev/null | head -1)"

# Vivado 2024.1 predates Ubuntu 24.04 and links librdi_commontasks.so against
# libtinfo.so.5, which Noble dropped.  This is nastier than a plain missing
# dependency because `vivado -version` does NOT load that library: the tool
# reports its version happily and then dies on the first batch run with
# "application-specific initialization failed".  So the check above is not
# enough on its own.
#
# When the real libtinfo.so.5 is absent we point Vivado at a libtinfo.so.6
# symlink for the duration of the run.  That is the standard workaround, it is
# what the jammy-pool .deb would give you, and unlike the .deb it needs no root
# and touches nothing outside build/.  Set AMOEBA_NO_TINFO_SHIM=1 to skip it if
# you would rather install the real library.
TINFO_SHIM  := $(BUILD)/tinfo-shim
HAVE_TINFO5 := $(shell ldconfig -p 2>/dev/null | grep -c 'libtinfo\.so\.5')
TINFO6      := $(shell ldconfig -p 2>/dev/null | awk '/libtinfo\.so\.6 /{print $$NF; exit}')

ifeq ($(AMOEBA_NO_TINFO_SHIM)$(HAVE_TINFO5),0)
  VIVADO_ENV := LD_LIBRARY_PATH=$(TINFO_SHIM):$$LD_LIBRARY_PATH
  TINFO_DEP  := $(TINFO_SHIM)/libtinfo.so.5
else
  VIVADO_ENV :=
  TINFO_DEP  :=
endif

$(TINFO_SHIM)/libtinfo.so.5:
	@test -n "$(TINFO6)" || { echo "error: no libtinfo.so.6 to shim from; install libtinfo5"; exit 1; }
	@mkdir -p $(TINFO_SHIM)
	@ln -sfn $(TINFO6) $@
	@echo "tinfo shim: $@ -> $(TINFO6)  (libtinfo.so.5 is absent on this host)"

utilization: $(SRCS_F) check-vivado $(TINFO_DEP)
	mkdir -p $(REPORTS)/$(REPORT_TAG) $(BUILD)
	cd $(BUILD) && $(VIVADO_ENV) vivado -mode batch -nojournal -notrace \
	    -log $(REPORTS)/$(REPORT_TAG)/vivado.log \
	    -source $(CURDIR)/tcl/synth_ooc.tcl \
	    -tclargs $(SRCS_F) $(DESIGN_TOP) $(XILINX_PART) $(CLK_PERIOD_NS) \
	             $(REPORTS)/$(REPORT_TAG) "$(CONFIG_DEFINES)" "$(INCDIRS)" \
             $(CLK_PORT) $(RST_PORT)
	@bash $(CURDIR)/scripts/fit_report.sh $(REPORTS)/$(REPORT_TAG) $(REPORT_TAG)

# Every config, so the report shows what the pruning actually bought rather
# than asserting it.  Runs serially; each is roughly an hour.
utilization-all:
	@for c in baremetal_linux freertos ""; do \
	    $(MAKE) --no-print-directory utilization CONFIG=$$c || exit 1; \
	done
	@echo; echo "=== summary ==="
	@for c in baremetal_linux freertos full; do \
	    bash $(CURDIR)/scripts/fit_report.sh $(REPORTS)/$$c $$c 2>/dev/null || true; \
	done

# ---- bitstream -------------------------------------------------------------
# The block design is where this flow actually breaks, and finding that out an
# hour into synthesis is a bad trade.  `make bd` stops as soon as the design
# validates, which takes minutes.
# BOARD=none skips the PS7 preset: a structural check of the block design that
# needs no board files.  It cannot produce a usable bitstream and build.tcl will
# refuse to try.  BOARD_REPO points at unpacked board files if they are not
# installed into Vivado itself.
XILINX_BOARD ?= tul.com.tw:pynq-z2:part0:1.0
BOARD        ?= $(XILINX_BOARD)
BOARD_REPO   ?= none
MEM_BACKEND  ?= BRAM
MEM_KB       ?= 128
TRACE        ?= 1
BITDIR       := $(CURDIR)/bit/$(CONFIG_TAG)-$(MEM_BACKEND)

define run_build
	@mkdir -p $(BITDIR)
	cd $(BUILD) && $(VIVADO_ENV) vivado -mode batch -nojournal -notrace \
	    -log $(BITDIR)/vivado.log \
	    -source $(CURDIR)/tcl/build.tcl \
	    -tclargs $(SRCS_F) $(XILINX_PART) $(BOARD) $(BITDIR) \
	             "$(CONFIG_DEFINES)" "$(INCDIRS)" \
	             $(FCLK_MHZ) $(MEM_BACKEND) $(MEM_KB) $(TRACE) $(1) $(BOARD_REPO)
endef

.PHONY: bd synth-bd bitstream
bd: TOP := amoeba_pynq_top
bd: $(SRCS_F) check-vivado $(TINFO_DEP)
	$(call run_build,bd)

synth-bd: TOP := amoeba_pynq_top
synth-bd: $(SRCS_F) check-vivado $(TINFO_DEP)
	$(call run_build,synth)

bitstream: TOP := amoeba_pynq_top
bitstream: $(SRCS_F) check-vivado $(TINFO_DEP)
	$(call run_build,bit)
	@echo "bitstream: $(BITDIR)/amoeba.bit + amoeba.hwh"

# ---- board ------------------------------------------------------------------
# BOARD_HOST is what a PYNQ-Z2 self-assigns on a direct Ethernet link.
BOARD_HOST ?= xilinx@192.168.2.99
IMAGES     ?= $(REPO)/testcode/freertos/freertos_wally.elf

.PHONY: deploy
deploy:
	@test -f $(BITDIR)/amoeba.bit || { \
	  echo "no bitstream at $(BITDIR)/amoeba.bit"; \
	  echo "  run: make bitstream"; exit 1; }
	BITDIR=$(BITDIR) $(CURDIR)/sw/deploy.sh $(BOARD_HOST) $(IMAGES)

# regs.py has no compile-time link to the RTL; this is the only thing that
# notices when they diverge.  Runs on the development machine.
.PHONY: check-regs
check-regs:
	@python3 $(CURDIR)/sw/check_regs.py

clean:
	rm -rf $(BUILD) $(REPORTS) $(CURDIR)/bit vivado*.jou vivado*.log .Xil
