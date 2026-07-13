SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

PKG_SRCS  := $(PWD)/../pkg/types.sv
CVW_SV    := $(PWD)/../hdl/cvw/src/cvw.sv
CVW_SRCS  := $(CVW_SV) $(filter-out $(CVW_SV), $(shell find $(PWD)/../hdl/cvw/src -name '*.sv' -o -name '*.v' 2>/dev/null))
# Exclude legacy RV32I CPU files (replaced by CVW) and the CVW submodule dir itself
LEGACY    := $(PWD)/../hdl/cpu.sv $(PWD)/../hdl/regfile.sv $(PWD)/../hdl/provided_cache.sv
HDL_SRCS  := $(filter-out $(PWD)/../hdl/cvw/% $(LEGACY), $(shell find $(PWD)/../hdl -name '*.sv')) $(CVW_SRCS)
COMM_HVL  := $(shell find $(PWD)/../hvl/common                -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VCS_HVL   := $(COMM_HVL) $(shell find $(PWD)/../hvl/vcs       -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so')
VER_HVL   := $(COMM_HVL) $(shell find $(PWD)/../hvl/verilator -name '*.sv' -o -name '*.v' -o -name '*.o' -o -name '*.so' -o -name '*.cpp')
SRAM_SRCS := $(shell find $(PWD)/../sram/output -name '*.v')
HDRS      := $(shell find $(PWD)/../hvl -name '*.svh') $(PWD)/../hvl/common/rvfi_reference.json
DW_IP     := $(shell python3 $(PWD)/../bin/get_options.py dw_ip)
VCS_SRCS  := $(PKG_SRCS) $(CVW_SV) $(HDL_SRCS) $(VCS_HVL) $(SRAM_SRCS) $(DW_IP)
VER_SRCS  := $(PKG_SRCS) $(CVW_SV) $(HDL_SRCS) $(VER_HVL) $(SRAM_SRCS) $(DW_IP)

TIMEOUT   ?= 10000000

ECE411_NO_FLOAT = $(shell python3 $(PWD)/../bin/get_options.py no_float)

export VCS_ARCH_OVERRIDE=linux
CVW_INCDIRS  = +incdir+$(PWD)/../hdl/cvw/src +incdir+$(PWD)/../hdl/cvw_config +incdir+$(PWD)/../hdl/cvw/config/rv64gc +incdir+$(PWD)/../hdl/cvw/config/shared
COMMON_FLAGS = +incdir+$(PWD)/../hvl/common $(CVW_INCDIRS) $(ECE411_NO_FLOAT) +define+DW_SUPPRESS_WARN +incdir+$(DW)/sim_ver
VCS_FLAGS    = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/vcs -licqueue -full64 -lca -sverilog -timescale=1ps/1ps -debug_acc+all -kdb -suppress=LCA_FEATURES_ENABLED -msg_config=../vcs_warn.config -xprop=../xprop.config -xprop=flowctrl -assert svaext
# VER_FLAGS      = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build -O3 -CFLAGS "-Ofast -march=native" --x-assign fast --x-initial fast --noassert --cc --exe ../verilator_warn.vlt --trace-fst --trace-structs --trace-max-array 1048576 --trace-max-width 1048576 +define+ECE411_VERILATOR --threads 5
VER_FLAGS 	   = $(COMMON_FLAGS) +incdir+$(PWD)/../hvl/verilator -Wall --timescale 1ps/1ps -Mdir build -O3 --output-split 20000 --output-split-cfuncs 200 -CFLAGS "-O3 -march=native -flto -DNDEBUG" -LDFLAGS "-flto" --x-assign fast --x-initial fast --trace-fst --trace-structs --cc --exe ../verilator_warn.vlt +define+ECE411_VERILATOR --threads $(shell nproc)


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
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd vcs && ./top_tb -l simulation.log -exitstatus -suppress=ASLR_DETECTED_INFO \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_8.lst" \
		+ELF_ECE411="$(PWD)/bin/spike_dpi.elf"

../hvl/common/spike.so: ../hvl/common/spike_dpi.cpp
	g++ -shared -fPIC -O2 $< -o $@

verilator/build/Vtop_tb: $(VER_SRCS) $(HDRS) ../hvl/common/spike.so
	mkdir -p verilator/build
	python3 check_sus.py
	python3 ../bin/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	cd verilator ;\
	PERL5LIB="$(PWD)/perl5:$${PERL5LIB}" verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb |& tee build/compile.log
	cd verilator/build ;\
	$(MAKE) --jobs=$(shell echo $(shell nproc)-2 | bc) -f Vtop_tb.mk |& tee -a compile.log

.PHONY: run_verilator_top_tb
run_verilator_top_tb: verilator/build/Vtop_tb $(PROG)
	mkdir -p spike
	find ./verilator -maxdepth 1 -type f -delete
	python3 ../bin/generate_memory_file.py -8 $(PROG)
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py bmem_x
	cd verilator && ./build/Vtop_tb \
		+TIMEOUT_ECE411=$(TIMEOUT) \
		+CLOCK_PERIOD_PS_ECE411=$(shell python3 $(PWD)/../bin/get_options.py clock) \
		+BRAM_0_ON_X_ECE411=$(shell python3 $(PWD)/../bin/get_options.py bmem_x) \
		+MEMLST_ECE411="$(PWD)/bin/memory_8.lst" \
		+ELF_ECE411="$(PWD)/bin/spike_dpi.elf" \
		|& tee simulation.log

.PHONY: covrep
covrep: vcs/top_tb.vdb
	cd vcs && urg -dir top_tb.vdb

.PHONY: verdi
verdi:
	mkdir -p verdi
	cd verdi && timeout $(ECE411_GUI_TIMEOUT) $(VERDI_HOME)/bin/verdi -ssf $(PWD)/vcs/dump.fsdb

.PHONY: spike
spike: $(ELF)
	mkdir -p spike
	spike --isa=$(shell python3 $(PWD)/../bin/get_options.py arch) -m0x80000000:0x10000000 --log-commits $(ELF) |& tail -n +6 > spike/spike.log

.PHONY: interactive_spike
interactive_spike: $(ELF)
	spike --isa=$(shell python3 $(PWD)/../bin/get_options.py arch) -m0x80000000:0x10000000 --log-commits -d $(ELF)

REGRESSION_TESTS ?= $(wildcard $(PWD)/../testcode/baremetal/*.elf)

.PHONY: regression
regression: verilator/build/Vtop_tb
	@for test in $(REGRESSION_TESTS); do \
		echo "=== Running $$test ==="; \
		ln -sf "$$test" "$(PWD)/bin/spike_dpi.elf"; \
		$(MAKE) run_verilator_top_tb PROG=$$test || exit 1; \
	done
	@echo "All regression tests passed."

.PHONY: clean
clean:
	rm -rf bin vcs verdi verilator spike
