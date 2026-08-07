SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

# ---- Repo layout ----
REPO_ROOT := $(abspath ../..)
BIN_DIR   := $(REPO_ROOT)/bin
HVL_DIR   := $(REPO_ROOT)/hvl
HDL_DIR   := $(REPO_ROOT)/hdl
PKG_DIR   := $(REPO_ROOT)/pkg
SIM_DIR   := $(REPO_ROOT)/sim
CVW_DIR   := $(REPO_ROOT)/third_party/cvw

# ---- FreeRTOS kernel ----
# Default: ~/FreeRTOS-Kernel clone; override with FREERTOS_KERNEL_DIR env var
# Future: will become $(REPO_ROOT)/third_party/FreeRTOS-Kernel once submodule is added
FREERTOS_KERNEL_DIR ?= $(HOME)/FreeRTOS-Kernel
FREERTOS_PORT       := $(FREERTOS_KERNEL_DIR)/portable/GCC/RISC-V
FREERTOS_PORT_CHIP  := $(FREERTOS_PORT)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

# ---- Userland workload (must define void app_main(void)) ----
PROG ?= $(abspath sorting_algo_app.c)

# ---- Toolchain ----
CC      := $(firstword $(foreach t,riscv64-unknown-elf-gcc riscv64-elf-gcc,$(if $(shell which $(t) 2>/dev/null),$(t))))
OBJDUMP := $(firstword $(foreach t,riscv64-unknown-elf-objdump riscv64-elf-objdump,$(if $(shell which $(t) 2>/dev/null),$(t))))

# ---- ISA: rv64imac (no FPU, matches AMOEBA amoeba config) ----
MARCH := rv64imac_zicsr
MABI  := lp64

CFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany \
          -O2 -gdwarf-2 \
          -nostdlib -static \
          -fno-tree-loop-distribute-patterns \
          -ffunction-sections -fdata-sections \
          -Wa,-march=$(MARCH)

INC := -I$(abspath .) \
       -I$(FREERTOS_KERNEL_DIR)/include \
       -I$(FREERTOS_PORT) \
       -I$(FREERTOS_PORT_CHIP)

LDFLAGS := -Tfreertos_wally.ld \
           -Wl,--gc-sections \
           -Wl,--build-id=none

# ---- Sources ----
BSP_SRCS := freertos_crt.S syscalls_amoeba.c

FREERTOS_SRCS := \
    $(FREERTOS_KERNEL_DIR)/tasks.c \
    $(FREERTOS_KERNEL_DIR)/queue.c \
    $(FREERTOS_KERNEL_DIR)/list.c \
    $(FREERTOS_KERNEL_DIR)/timers.c \
    $(FREERTOS_KERNEL_DIR)/event_groups.c \
    $(FREERTOS_KERNEL_DIR)/portable/MemMang/heap_4.c \
    $(FREERTOS_PORT)/port.c \
    $(FREERTOS_PORT)/portASM.S

APP_SRCS := freertos_main.c $(PROG)
ALL_SRCS := $(BSP_SRCS) $(FREERTOS_SRCS) $(APP_SRCS)

ELF := freertos_wally.elf

# ====================================================================
# Verilator source lists (mirrors sim/Makefile; spike.so excluded)
# ====================================================================
PKG_SRCS  := $(shell find $(PKG_DIR) -name '*.sv')
CORE_SV   := $(REPO_ROOT)/hdl/core/cvw.sv
# cvw.sv listed first (package must precede modules); exclude from CORE_SRCS.
CORE_SRCS := $(filter-out $(CORE_SV), $(shell find $(REPO_ROOT)/hdl/core -name '*.sv' -o -name '*.v' 2>/dev/null))
# Exclude hdl/cvw/ and hdl/core/ from generic hdl find; CORE_SV + CORE_SRCS handle hdl/core/.
HDL_SRCS  := $(filter-out $(REPO_ROOT)/hdl/cvw/% $(REPO_ROOT)/hdl/core/%, $(shell find $(HDL_DIR) -name '*.sv')) $(CORE_SRCS)

COMM_HVL := $(shell find $(HVL_DIR)/common  -name '*.sv' -o -name '*.v')
VER_HVL  := $(COMM_HVL) \
             $(shell find $(HVL_DIR)/verilator -name '*.sv' -o -name '*.v' -o -name '*.cpp')

DW_IP    := $(shell python3 $(BIN_DIR)/get_options.py dw_ip)
VER_SRCS := $(PKG_SRCS) $(CORE_SV) $(HDL_SRCS) $(VER_HVL) $(DW_IP)
HDRS     := $(shell find $(HVL_DIR) -name '*.svh') $(HVL_DIR)/common/rvfi_reference.json

ECE411_NO_FLOAT := $(shell python3 $(BIN_DIR)/get_options.py no_float)

CVW_INCDIRS := \
    +incdir+$(REPO_ROOT)/hdl/core \
    +incdir+$(PKG_DIR) \
    +incdir+$(CVW_DIR)/config/rv64gc

COMMON_FLAGS := \
    +incdir+$(HVL_DIR)/common \
    $(CVW_INCDIRS) \
    $(ECE411_NO_FLOAT) \
    +define+DW_SUPPRESS_WARN \
    +define+ECE411_NO_SPIKE_DPI \
    +define+ECE411_NO_SPIKE_PRINTER

VER_FLAGS := $(COMMON_FLAGS) \
    +incdir+$(HVL_DIR)/verilator \
    -Wall --timescale 1ps/1ps \
    -Mdir $(abspath build) \
    -O3 --output-split 20000 --output-split-cfuncs 200 \
    -CFLAGS "-O3 -march=native -flto -DNDEBUG" \
    -LDFLAGS "-flto" \
    --x-assign fast --x-initial fast \
    --trace-fst --trace-structs \
    --cc \
    --exe $(abspath $(HVL_DIR)/verilator/verilator_harness.cpp) \
    $(SIM_DIR)/verilator_warn.vlt \
    +define+ECE411_VERILATOR \
    --threads $(shell nproc)

TIMEOUT ?= 50000000

# ====================================================================
.PHONY: freertos build sim verilator regression clean

freertos: sim

build: $(ELF) $(SIM_DIR)/bin/memory_8.lst

verilator: build/Vtop_tb

$(FREERTOS_KERNEL_DIR)/tasks.c:
	@echo ""
	@echo "ERROR: FreeRTOS-Kernel not found at $(FREERTOS_KERNEL_DIR)"
	@echo "       Clone it: git clone https://github.com/FreeRTOS/FreeRTOS-Kernel $(FREERTOS_KERNEL_DIR)"
	@echo ""
	@exit 1

$(ELF): $(FREERTOS_KERNEL_DIR)/tasks.c $(ALL_SRCS) freertos_wally.ld
	$(CC) $(CFLAGS) $(INC) $(LDFLAGS) -o $@ $(ALL_SRCS)
	$(OBJDUMP) -S -D $@ > $(ELF:.elf=.dis)

$(SIM_DIR)/bin/memory_8.lst: $(ELF)
	python3 $(BIN_DIR)/generate_memory_file.py -8 $<

build/Vtop_tb: $(VER_SRCS) $(HDRS)
	mkdir -p build
	python3 $(BIN_DIR)/rvfi_reference.py 1 $(ECE411_NO_FLOAT)
	PERL5LIB="$(SIM_DIR)/perl5:$${PERL5LIB}" \
	verilator $(VER_FLAGS) $(VER_SRCS) --top-module top_tb \
	    |& tee build/compile.log
	$(MAKE) --jobs=$(shell echo $$(nproc)-2 | bc) \
	    -C $(abspath build) -f Vtop_tb.mk \
	    |& tee -a build/compile.log

sim: build/Vtop_tb $(SIM_DIR)/bin/memory_8.lst
	mkdir -p spike
	find . -maxdepth 1 -name "dump.fst" -delete
	./build/Vtop_tb \
	    +TIMEOUT_ECE411=$(TIMEOUT) \
	    +CLOCK_PERIOD_PS_ECE411=$(shell python3 $(BIN_DIR)/get_options.py clock) \
	    +BRAM_0_ON_X_ECE411=$(shell python3 $(BIN_DIR)/get_options.py bmem_x) \
	    +MEMLST_ECE411="$(abspath $(SIM_DIR)/bin/memory_8.lst)" \
	    +ELF_ECE411="$(abspath $(ELF))" \
	    |& tee sim.log
	@grep -q "PASSED\|\$$finish" sim.log || \
	    (echo ""; echo "WARNING: PASSED not found in sim.log — check for FAILED or timeout"; echo "")

regression: freertos
	@echo ""
	@echo "=== Bare-metal regression (sim/Makefile) ==="
	$(MAKE) -C $(SIM_DIR) regression
	@echo ""
	@echo "=== All regressions passed ==="

clean:
	rm -rf build/ spike/ \
	       $(ELF) $(ELF:.elf=.dis) \
	       $(SIM_DIR)/bin/memory_8.lst \
	       sim.log dump.fst time.txt
