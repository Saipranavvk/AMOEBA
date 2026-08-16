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
FREERTOS_KERNEL_DIR ?= $(REPO_ROOT)/third_party/FreeRTOS-Kernel
FREERTOS_PORT       := $(FREERTOS_KERNEL_DIR)/portable/GCC/RISC-V
FREERTOS_PORT_CHIP  := $(FREERTOS_PORT)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

# ---- Userland workload (must define int app_main(void)) ----
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

# Add stub headers when the cross-sysroot lacks newlib (e.g. Ubuntu gcc-riscv64-unknown-elf)
_SYSROOT := $(shell $(CC) -print-sysroot 2>/dev/null)
ifeq ($(wildcard $(_SYSROOT)/include/stdlib.h),)
_STUB_INC := -isystem $(abspath stub_include)
endif

INC := -I$(abspath .) \
       -I$(FREERTOS_KERNEL_DIR)/include \
       -I$(FREERTOS_PORT) \
       -I$(FREERTOS_PORT_CHIP) \
       $(_STUB_INC)

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
.PHONY: build clean

build: $(ELF) $(SIM_DIR)/bin/memory_8.lst

$(FREERTOS_KERNEL_DIR)/tasks.c:
	@echo ""
	@echo "ERROR: FreeRTOS-Kernel not found at $(FREERTOS_KERNEL_DIR)"
	@echo "       Run: git submodule update --init third_party/FreeRTOS-Kernel"
	@echo ""
	@exit 1

$(ELF): $(FREERTOS_KERNEL_DIR)/tasks.c $(ALL_SRCS) freertos_wally.ld
	$(CC) $(CFLAGS) $(INC) $(LDFLAGS) -o $@ $(ALL_SRCS)
	$(OBJDUMP) -S -D $@ > $(ELF:.elf=.dis)

$(SIM_DIR)/bin/memory_8.lst: $(ELF)
	python3 $(BIN_DIR)/generate_memory_file.py -8 $<

clean:
	rm -rf $(ELF) $(ELF:.elf=.dis) dump.fst
