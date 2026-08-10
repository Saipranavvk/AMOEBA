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

TIMEOUT      ?= 10000000
PROG_NAME ?= $(notdir $(basename $(PROG)))

ECE411_NO_FLOAT = $(shell python3 $(CURDIR)/../bin/get_options.py no_float)

export VCS_ARCH_OVERRIDE=linux
CVW_INCDIRS  = +incdir+$(CURDIR)/../hdl/core +incdir+$(CURDIR)/../pkg +incdir+$(CURDIR)/../third_party/cvw/config/rv64gc
COMMON_FLAGS = +incdir+$(CURDIR)/../hvl/common $(CVW_INCDIRS) $(ECE411_NO_FLOAT) +define+DW_SUPPRESS_WARN +incdir+$(DW)/sim_ver
VCS_FLAGS    = $(COMMON_FLAGS) +incdir+$(CURDIR)/../hvl/vcs -licqueue -full64 -lca -sverilog -timescale=1ps/1ps -debug_acc+all -kdb -suppress=LCA_FEATURES_ENABLED -msg_config=../vcs_warn.config -xprop=../xprop.config -xprop=flowctrl -assert svaext
# VER_FLAGS      = $(COMMON_FLAGS) +incdir+$(CURDIR)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build -O3 -CFLAGS "-Ofast -march=native" --x-assign fast --x-initial fast --noassert --cc --exe ../verilator_warn.vlt --trace-fst --trace-structs --trace-max-array 1048576 --trace-max-width 1048576 +define+ECE411_VERILATOR --threads 5
VER_FLAGS 	   = $(COMMON_FLAGS) +incdir+$(CURDIR)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG" -LDFLAGS "-flto" --x-assign fast --x-initial fast --trace-fst --trace-structs --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)
FREERTOS_VER_FLAGS = $(COMMON_FLAGS) +define+ECE411_NO_SPIKE_DPI +incdir+$(CURDIR)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build_freertos -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -flto -DNDEBUG" -LDFLAGS "-flto" --x-assign fast --x-initial fast --trace-fst --trace-structs --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)


verilator/build_freertos/Vtop_tb: $(VER_SRCS) $(HDRS)
	mkdir -p verilator/build_freertos
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(FREERTOS_VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee build_freertos/compile.log
	cd verilator/build_freertos ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb_freertos
run_verilator_top_tb_freertos: verilator/build_freertos/Vtop_tb $(PROG)
	mkdir -p verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./build_freertos/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(CURDIR)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(CURDIR)/bin/memory_8.lst" \
		+ELF_ECE411="$(CURDIR)/bin/spike_dpi.elf" \
		|& tee $(PROG_NAME)/simulation.log
	-cp verilator/dump.fst verilator/$(PROG_NAME)/dump.fst 2>/dev/null

.PHONY: build_freertos
build_freertos: verilator/build_freertos/Vtop_tb
	@echo "FreeRTOS simulation built with ECE411_NO_SPIKE_DPI flag"

.PHONY: freertos
freertos: verilator/build_freertos/Vtop_tb
	$(MAKE) -C $(CURDIR)/../testcode/freertos build
	$(MAKE) run_verilator_top_tb_freertos PROG=$(CURDIR)/../testcode/freertos/freertos_wally.elf

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

verilator/build/Vtop_tb: $(VER_SRCS) $(HDRS) ../hvl/common/spike.so
	mkdir -p verilator/build
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(CURDIR)/perl5:$${PERL5LIB}" verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee build/compile.log
	cd verilator/build ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb
run_verilator_top_tb: verilator/build/Vtop_tb $(PROG)
	mkdir -p spike verilator/$(PROG_NAME)
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(CURDIR)/../bin/get_options.py clock
	python3 $(CURDIR)/../bin/get_options.py bmem_x
	cd verilator && ./build/Vtop_tb \
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

REGRESSION_TESTS ?= $(shell find $(CURDIR)/../testcode/baremetal -name '*.c')

RISCV_FORMAL_MONITOR_DIR = $(CURDIR)/../third_party/riscv-formal/monitor
RISCV_FORMAL_MONITOR     = $(RISCV_FORMAL_MONITOR_DIR)/generate.py
RVFIMON_ISA          ?= rv64imafdc_zb

.PHONY: generate-rtl
generate-rtl:
	bash $(CURDIR)/../bin/generate_rtl.sh

.PHONY: generated-files
generated-files:
	python3 $(CURDIR)/../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd $(RISCV_FORMAL_MONITOR_DIR) && \
	    python3 generate.py -i $(RVFIMON_ISA) -a -r 0 -c 1 > $(CURDIR)/../hvl/common/rvfimon.v

.PHONY: check-generated
check-generated:
	@tmp=$$(mktemp -d); \
	python3 $(CURDIR)/../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT); \
	cd $(RISCV_FORMAL_MONITOR_DIR) && python3 generate.py -i $(RVFIMON_ISA) -a -r 0 -c 1 > $$tmp/rvfimon.v; \
	diff $(CURDIR)/../hvl/common/rvfimon.v $$tmp/rvfimon.v || (echo "ERROR: rvfimon.v is stale — run 'make generated-files'" && rm -rf $$tmp && exit 1); \
	rm -rf $$tmp; \
	echo "Generated files are up to date."

.PHONY: regression
regression: verilator/build/Vtop_tb
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
	echo "=== Regression Summary: $$pass/$$total tests passed ==="; \
	[ $$fail -eq 0 ] || exit 1

.PHONY: clean
clean:
	rm -rf bin vcs verdi verilator spike
