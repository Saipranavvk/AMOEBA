SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

PKG_SRCS  := $(shell find $(CURDIR)/../pkg -name '*.sv')
CORE_SV   := $(CURDIR)/../hdl/core/cvw.sv
# cvw.sv listed explicitly first in VER/VCS_SRCS (package must precede modules); exclude from CORE_SRCS.
CORE_SRCS := $(filter-out $(CORE_SV), $(shell find $(CURDIR)/../hdl/core -name '*.sv' -o -name '*.v' 2>/dev/null))
# Exclude hdl/cvw/ and hdl/core/ from generic hdl find; CORE_SV + CORE_SRCS handle hdl/core/.
HDL_SRCS  := $(filter-out $(CURDIR)/../hdl/cvw/% $(CURDIR)/../hdl/core/%, $(shell find $(CURDIR)/../hdl -name '*.sv')) $(CORE_SRCS)
COMM_HVL  := $(shell find $(CURDIR)/../hvl/common                -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VCS_HVL   := $(COMM_HVL) $(shell find $(CURDIR)/../hvl/vcs       -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VER_HVL   := $(COMM_HVL) $(shell find $(CURDIR)/../hvl/verilator -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so' -o -name '*.cpp')
SRAM_SRCS := $(shell find $(CURDIR)/../sram/output -name '*.v')
HDRS      := $(shell find $(CURDIR)/../hvl -name '*.svh') $(CURDIR)/../hvl/common/rvfi_reference.json
DW_IP     := $(shell python3 $(CURDIR)/../bin/get_options.py dw_ip)
VCS_SRCS  := $(PKG_SRCS) $(CORE_SV) $(HDL_SRCS) $(VCS_HVL) $(SRAM_SRCS) $(DW_IP)
VER_SRCS  := $(PKG_SRCS) $(CORE_SV) $(HDL_SRCS) $(VER_HVL) $(SRAM_SRCS) $(DW_IP)

# ── Waveform tracing for the baremetal / ISA / FreeRTOS tiers ─────────────────
# Off by default.  Verilator's trace hooks cost roughly 50x in wall time -- the
# ISA regression drops from hours to minutes without them -- and every one of
# these tests reports pass/fail through tohost, so a waveform is only wanted once
# something has already failed.
#
# Turn it back on per-invocation; the traced binaries build into their own
# directories, so both coexist and switching costs no rebuild of the other:
#
#     make run_verilator_top_tb_no_spike TRACE=1 PROG=../testcode/isa_level_testing/tc_mul_div.c
#     make regression TRACE=1
#
# Output lands in sim/verilator/<testname>/dump.fst as before.
TRACE ?= 0
ifeq ($(TRACE),1)
  TRACE_VFLAGS     := --trace-fst --trace-structs
  TRACE_DEF        :=
  TRACE_CFLAGS     :=
  BUILD_DIR        := build_trace
  NO_SPIKE_DIR     := build_no_spike_trace
else
  TRACE_VFLAGS     :=
  TRACE_DEF        := +define+ECE411_NO_TRACE
  TRACE_CFLAGS     := -DECE411_NO_TRACE
  BUILD_DIR        := build
  NO_SPIKE_DIR     := build_no_spike
endif

TIMEOUT      ?= 10000000
PROG_NAME ?= $(notdir $(basename $(PROG)))

ECE411_NO_FLOAT = $(shell python3 $(CURDIR)/../bin/get_options.py no_float)

# ── Pruned hardware configurations ────────────────────────────────────────────
# CONFIG selects which pkg/ parameter set the no-Spike testbench is built
# against, in place of the full RV64GC pkg/config.vh:
#
#     CONFIG=freertos           pkg/config_freertos.vh
#                               only what the FreeRTOS images execute
#     CONFIG=freertos_keystone  pkg/config_freertos_keystone.vh
#                               that, plus what the Keystone SM and OpenSBI need
#     CONFIG=baremetal_linux    pkg/config_baremetal_linux.vh
#                               smallest core that boots a soft-float Linux
#
#     make freertos_regression CONFIG=freertos
#     make linux_boot          CONFIG=baremetal_linux
#
# None of them has an FPU, so those builds must also drop the RVFI float channel:
# without ECE411_NO_FLOAT the wrapper taps soc.core.fpu.fpu.fregfile, which is
# no longer elaborated.  hvl/common/rvfi_reference.svh is generated per build
# and is shared, so switching CONFIG rewrites it and the other Verilator
# binaries rebuild on their next invocation.  The binaries themselves live in
# separate -Mdir trees and coexist.
CONFIG ?=
ifeq ($(CONFIG),)
  CONFIG_DEF   :=
  NO_FLOAT_ARG := $(if $(ECE411_NO_FLOAT),no_float,)
else ifeq ($(CONFIG),freertos)
  CONFIG_DEF   := +define+AMOEBA_CONFIG_FREERTOS +define+ECE411_NO_FLOAT
  NO_FLOAT_ARG := no_float
  NO_SPIKE_DIR := $(NO_SPIKE_DIR)_freertos
else ifeq ($(CONFIG),freertos_keystone)
  CONFIG_DEF   := +define+AMOEBA_CONFIG_FREERTOS_KEYSTONE +define+ECE411_NO_FLOAT
  NO_FLOAT_ARG := no_float
  NO_SPIKE_DIR := $(NO_SPIKE_DIR)_freertos_keystone
else ifeq ($(CONFIG),baremetal_linux)
  CONFIG_DEF   := +define+AMOEBA_CONFIG_BAREMETAL_LINUX +define+ECE411_NO_FLOAT
  NO_FLOAT_ARG := no_float
  NO_SPIKE_DIR := $(NO_SPIKE_DIR)_baremetal_linux
else
  $(error CONFIG=$(CONFIG) is not a known configuration -- use freertos, freertos_keystone, baremetal_linux, or leave it unset)
endif

export VCS_ARCH_OVERRIDE=linux
CVW_INCDIRS  = +incdir+$(CURDIR)/../hdl/core +incdir+$(CURDIR)/../pkg +incdir+$(CURDIR)/../third_party/cvw/config/rv64gc
COMMON_FLAGS = +incdir+$(CURDIR)/../hvl/common $(CVW_INCDIRS) $(ECE411_NO_FLOAT) +define+DW_SUPPRESS_WARN +incdir+$(DW)/sim_ver
VCS_FLAGS    = $(COMMON_FLAGS) +incdir+$(CURDIR)/../hvl/vcs -licqueue -full64 -lca -sverilog -timescale=1ps/1ps -debug_acc+all -kdb -suppress=LCA_FEATURES_ENABLED -msg_config=../vcs_warn.config -xprop=../xprop.config -xprop=flowctrl -assert svaext
VER_FLAGS    = $(COMMON_FLAGS) +incdir+$(CURDIR)/../hvl/verilator $(TRACE_DEF) -Wall --timescale 1ps/1ps -Mdir $(BUILD_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG $(TRACE_CFLAGS)" -LDFLAGS "-flto" --x-assign fast --x-initial fast $(TRACE_VFLAGS) --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)
NO_SPIKE_VER_FLAGS = $(COMMON_FLAGS) $(CONFIG_DEF) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER $(TRACE_DEF) +incdir+$(CURDIR)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir $(NO_SPIKE_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG $(TRACE_CFLAGS)" -LDFLAGS "-flto" --x-assign fast --x-initial fast $(TRACE_VFLAGS) --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)


# ── No-Spike simulator (shared by ISA-level tests and FreeRTOS tests) ──────────
verilator/$(NO_SPIKE_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) $(CURDIR)/Makefile
	mkdir -p verilator/$(NO_SPIKE_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(NO_FLOAT_ARG)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(NO_SPIKE_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(NO_SPIKE_DIR)/compile.log
	cd verilator/$(NO_SPIKE_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb_no_spike
run_verilator_top_tb_no_spike: verilator/$(NO_SPIKE_DIR)/Vtop_tb $(PROG)
	mkdir -p verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./$(NO_SPIKE_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		|& tee $(PROG_NAME)/simulation.log
	-cp verilator/dump.fst verilator/$(PROG_NAME)/dump.fst 2>/dev/null

# Convenience aliases — both ISA tests and FreeRTOS tests use the no-spike simulator
.PHONY: run_isa_level
run_isa_level: verilator/$(NO_SPIKE_DIR)/Vtop_tb $(PROG)
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(PROG)

.PHONY: run_verilator_top_tb_freertos
run_verilator_top_tb_freertos: verilator/$(NO_SPIKE_DIR)/Vtop_tb $(PROG)
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(PROG)

.PHONY: build_isa_tests
build_isa_tests: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@echo "ISA/FreeRTOS simulator built (ECE411_NO_SPIKE_DPI)"

.PHONY: build_freertos
build_freertos: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@echo "FreeRTOS simulator built (ECE411_NO_SPIKE_DPI)"

# ── Linux boot simulator (no waveforms, no co-simulation) ──────────────────────
# Waveform tracing is compiled out rather than merely disabled: +NO_DUMP_ALL only
# suppresses the C++ tracer, while the SV-side $dumpvars keeps writing regardless.
# Measured on a 20-core host at 5M cycles -- 2.2 kHz traced vs 116 kHz here, and a
# boot-length trace would run to hundreds of GB.  --threads 1 is deliberate: on a
# single-hart in-order core, 4 threads measured 11% SLOWER at 4x the CPU.
# ECE411_LINUX additionally narrows halt detection (Linux and OpenSBI both run
# through `j .` park loops) and makes untouched DRAM read as zero instead of 'x.
# RVFI shadow checker for the Linux tier.  Default OFF, which is a real loss of
# coverage and deliberate -- see testcode/linux/README.md.  The generated
# riscv-formal monitor hardcodes "a misaligned data access traps", but CVW sets
# ZICCLSM_SUPPORTED and handles misaligned accesses in hardware, so a Linux boot
# trips a false trap mismatch.  LINUX_RVFI=1 builds with the checker into a
# separate directory so both binaries can coexist.
LINUX_RVFI ?= 0
ifeq ($(LINUX_RVFI),1)
  LINUX_BUILD_DIR := build_linux_rvfi
  LINUX_RVFI_DEF  :=
else
  LINUX_BUILD_DIR := build_linux
  LINUX_RVFI_DEF  := +define+ECE411_NO_RVFI
endif
# CONFIG applies to the Linux simulator too, into its own -Mdir.  Note for
# CONFIG=baremetal_linux: that config sets ZICCLSM_SUPPORTED = 0, so misaligned
# accesses trap exactly as the generated monitor assumes, and LINUX_RVFI=1 is
# expected to work there without the false mismatch that forces it off on the
# main config.
ifneq ($(CONFIG),)
  LINUX_BUILD_DIR := $(LINUX_BUILD_DIR)_$(CONFIG)
endif

LINUX_VER_FLAGS = $(COMMON_FLAGS) $(CONFIG_DEF) +define+ECE411_NO_SPIKE_DPI +define+ECE411_NO_SPIKE_PRINTER \
	+define+ECE411_LINUX +define+ECE411_NO_TRACE $(LINUX_RVFI_DEF) +incdir+$(CURDIR)/../hvl/verilator \
	-Wall --timescale 1ps/1ps -Mdir $(LINUX_BUILD_DIR) -O3 --output-split 20000 --output-split-cfuncs 200 \
	-CFLAGS "-O3 -flto -DNDEBUG -DECE411_NO_TRACE" -LDFLAGS "-flto" --x-assign fast --x-initial fast \
	--cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads 1

# Depends on this Makefile too: LINUX_RVFI changes the compiled defines, and
# without it make would leave a stale binary in place and silently ignore the
# flag change.
verilator/$(LINUX_BUILD_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) $(CURDIR)/Makefile
	mkdir -p verilator/$(LINUX_BUILD_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(NO_FLOAT_ARG)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(LINUX_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(LINUX_BUILD_DIR)/compile.log
	cd verilator/$(LINUX_BUILD_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: build_linux
build_linux: verilator/$(LINUX_BUILD_DIR)/Vtop_tb
	@echo "Linux boot simulator built (ECE411_LINUX, waveforms compiled out)"

# ── Linux boot run ────────────────────────────────────────────────────────────
# LINUX_PASS selects the milestone: override it to stop at an earlier point in
# the boot, e.g. LINUX_PASS='Linux version 6.6' for a ~5M-cycle smoke test.
LINUX_DIR     ?= $(CURDIR)/../testcode/linux
# The image has to match the hardware: testcode/linux builds a per-CONFIG image
# into its own subdirectory, because the device tree must not advertise an
# extension the core does not implement.  CONFIG=baremetal_linux gets the
# soft-float image; unset gets the full RV64GC one, at the path it has always
# been at.  Override LINUX_MEMLST to boot something else (e.g. the uart smoke).
LINUX_IMG_DIR := $(LINUX_DIR)/build$(if $(CONFIG),/$(CONFIG))
LINUX_MEMLST  ?= $(LINUX_IMG_DIR)/boot.lst
LINUX_TIMEOUT ?= 2000000000
LINUX_PASS    ?= AMOEBA_LINUX_BOOT_OK
LINUX_FAIL    ?= Kernel panic|Unable to handle kernel|Oops:|SBI panic
LINUX_RUN_DIR ?= verilator/linux_boot

$(LINUX_MEMLST):
	$(MAKE) -C $(LINUX_DIR) CONFIG=$(CONFIG)

.PHONY: linux_boot
linux_boot: verilator/$(LINUX_BUILD_DIR)/Vtop_tb $(LINUX_MEMLST)
	mkdir -p $(LINUX_RUN_DIR)
	cd verilator && ./$(LINUX_BUILD_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(LINUX_TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+MEMLST_ECE411="$(LINUX_MEMLST)" \
		+UART_PASS_ECE411="$(LINUX_PASS)" \
		+UART_FAIL_ECE411="$(LINUX_FAIL)" \
		+UARTLOG_ECE411="$(CURDIR)/$(LINUX_RUN_DIR)/boot_uart.log" \
		|& tee $(CURDIR)/$(LINUX_RUN_DIR)/simulation.log

.PHONY: freertos
freertos: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	$(MAKE) -C $(CURDIR)/../testcode/freertos build
	$(MAKE) run_verilator_top_tb_no_spike PROG=$(CURDIR)/../testcode/freertos/freertos_wally.elf

vcs/top_tb: $(VCS_SRCS) $(HDRS)
	mkdir -p vcs
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd vcs && vcs $(VCS_SRCS) $(VCS_FLAGS) -l compile.log -top top_tb -o top_tb
	bash check_compile_error.sh

.PHONY: run_vcs_top_tb
run_vcs_top_tb: vcs/top_tb $(PROG)
	mkdir -p spike
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	rm -f vcs/dump.fsdb
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd vcs && ./top_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		+ELF_ECE411="$(CURDIR)/bin/spike_dpi.elf"

../hvl/common/spike.so: ../hvl/common/spike_dpi.cpp
	g++ -shared -fPIC -O2 $< -o $@

# ── Spike DPI simulator (baremetal co-simulation) ───────────────────────────────
verilator/$(BUILD_DIR)/Vtop_tb: $(VER_SRCS) $(HDRS) ../hvl/common/spike.so $(CURDIR)/Makefile
	mkdir -p verilator/$(BUILD_DIR)
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee $(BUILD_DIR)/compile.log
	cd verilator/$(BUILD_DIR) ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: build
build: verilator/$(BUILD_DIR)/Vtop_tb

.PHONY: run_verilator_top_tb
run_verilator_top_tb: verilator/$(BUILD_DIR)/Vtop_tb $(PROG)
	mkdir -p spike verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./$(BUILD_DIR)/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		+ELF_ECE411="$(CURDIR)/bin/spike_dpi.elf" \
		|& tee $(PROG_NAME)/simulation.log
	-cp verilator/dump.fst verilator/$(PROG_NAME)/dump.fst 2>/dev/null

.PHONY: covrep
covrep: vcs/top_tb.vdb
	cd vcs && urg -dir top_tb.vdb

.PHONY: verdi
verdi:
	mkdir -p verdi
	cd verdi && timeout $(ECE411_GUI_TIMEOUT) $(VERDI_HOME)/bin/verdi -ssf $(CURDIR)/vcs/dump.fsdb

.PHONY: spike
spike: $(ELF)
	mkdir -p spike
	spike --isa=$(shell python3 $(CURDIR)/../bin/get_options.py arch) -m0x80000000:0x10000000 --log-commits $(ELF) |& tail -n +6 > spike/spike.log

.PHONY: interactive_spike
interactive_spike: $(ELF)
	spike --isa=$(shell python3 $(CURDIR)/../bin/get_options.py arch) -m0x80000000:0x10000000 --log-commits -d $(ELF)

REGRESSION_TESTS  ?= $(shell find $(CURDIR)/../testcode/baremetal -name '*.c')
ISA_LEVEL_TESTS   ?= $(shell find $(CURDIR)/../testcode/isa_level_testing -name '*.c' ! -name 'test_utils.h')
FREERTOS_TESTS    ?= $(shell find $(CURDIR)/../testcode/freertos -name 'tc_*.c')

RISCV_FORMAL_MONITOR_DIR = $(CURDIR)/../third_party/riscv-formal/monitor
RISCV_FORMAL_MONITOR     = $(RISCV_FORMAL_MONITOR_DIR)/generate.py
RVFIMON_ISA          ?= rv64imafdc_zb
# Local fix on top of the generated monitor.  Applied by generated-files and
# re-applied by check-generated, so regenerating cannot silently drop it.
RVFIMON_PATCH        = $(CURDIR)/../patches/rvfimon-clz-ctz.patch

.PHONY: generate-rtl
generate-rtl:
	bash $(CURDIR)/../bin/generate_rtl.sh

.PHONY: generated-files
generated-files:
	python3 $(CURDIR)/../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd $(RISCV_FORMAL_MONITOR_DIR) && \
	    python3 generate.py -i $(RVFIMON_ISA) -a -r 0 -c 1 > $(CURDIR)/../hvl/common/rvfimon.v
	patch -s $(CURDIR)/../hvl/common/rvfimon.v < $(RVFIMON_PATCH)

.PHONY: check-generated
check-generated:
	@tmp=$$(mktemp -d); \
	python3 $(CURDIR)/../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT); \
	cd $(RISCV_FORMAL_MONITOR_DIR) && python3 generate.py -i $(RVFIMON_ISA) -a -r 0 -c 1 > $$tmp/rvfimon.v; \
	patch -s $$tmp/rvfimon.v < $(RVFIMON_PATCH) || (echo "ERROR: $(RVFIMON_PATCH) no longer applies to the generated monitor." && echo "The submodule moved; rebase or drop the patch if it is upstream now." && rm -rf $$tmp && exit 1); \
	diff $(CURDIR)/../hvl/common/rvfimon.v $$tmp/rvfimon.v || (echo "ERROR: rvfimon.v is stale — run 'make generated-files'" && rm -rf $$tmp && exit 1); \
	rm -rf $$tmp; \
	echo "Generated files are up to date."

# ── Regression targets ──────────────────────────────────────────────────────────

.PHONY: baremetal_regression
baremetal_regression: verilator/$(BUILD_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for test in $(REGRESSION_TESTS); do \
		total=$$((total+1)); \
		echo "=== [$$total] Running $$test ==="; \
		if $(MAKE) -s run_verilator_top_tb PROG=$$test; then \
			echo "  PASS: $$test"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$test"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== Baremetal Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: isa_regression
isa_regression: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for test in $(ISA_LEVEL_TESTS); do \
		total=$$((total+1)); \
		echo "=== [$$total] Running $$test ==="; \
		if $(MAKE) -s run_verilator_top_tb_no_spike PROG=$$test; then \
			echo "  PASS: $$test"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$test"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== ISA Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: freertos_regression
freertos_regression: verilator/$(NO_SPIKE_DIR)/Vtop_tb
	@pass=0; fail=0; total=0; \
	for test in $(FREERTOS_TESTS); do \
		total=$$((total+1)); \
		name=$$(basename $$test .c); \
		echo "=== [$$total] Running $$name ==="; \
		if rm -f $(CURDIR)/../testcode/freertos/freertos_wally.elf && \
		   $(MAKE) -C $(CURDIR)/../testcode/freertos build PROG=$$test && \
		   $(MAKE) -s run_verilator_top_tb_no_spike PROG=$(CURDIR)/../testcode/freertos/freertos_wally.elf; then \
			echo "  PASS: $$name"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$name"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo ""; \
	echo "=== FreeRTOS Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: regression
regression:
	$(MAKE) baremetal_regression
	$(MAKE) isa_regression
	$(MAKE) freertos_regression

.PHONY: clean
clean:
	rm -rf bin vcs verdi verilator spike
