# Boot-image build for the AMOEBA Linux boot test.
#
#   make                          build/boot.lst -- shim + OpenSBI + kernel + initramfs
#   make CONFIG=baremetal_linux   build/baremetal_linux/boot.lst -- the soft-float image
#   make smoke                    uart_smoke.lst -- console-path pre-flight, no firmware
#   make clean                    remove build products, keep downloaded tarballs
#   make distclean                remove everything including downloads
#
# This is the image-build path, run locally or by a dedicated CI workflow.  The
# nightly boot job must NOT run it: fetching and building a kernel costs 10-30
# minutes that would come straight out of the simulation budget.  Publish
# build/boot.lst as an artifact instead.

# ---- configuration ----------------------------------------------------------
# CONFIG selects which pkg/ parameter set the image is built for, matching the
# name sim/Makefile and synth/Makefile use:
#
#   (unset)          pkg/config.vh              full RV64GC, hard-float kernel
#   baremetal_linux  pkg/config_baremetal_linux.vh  no FPU, no B, no Zicbom,
#                                                   no PLIC, Sv39 only
#
# The two images differ in the kernel config fragment and the device tree, and
# nothing else -- same kernel version, same OpenSBI, same initramfs.  Each gets
# its own kbuild and OpenSBI output directory so both can exist at once; the
# kernel source tree is shared and never carries a .config of its own.
#
# The device tree must not advertise an extension the core does not implement,
# so the .dts and the config fragment are always selected together.  Adding a
# third config means adding one of each and one line here.
CONFIG ?=
ifeq ($(CONFIG),)
  CONFIG_FRAG :=
  DTS_SRC     := dts/amoeba.dts
  OUT         := $(CURDIR)/build
  # OpenSBI inherits the toolchain's default ISA, which includes f/d.  Harmless
  # for the full config: the firmware itself uses no FP either way.
  SBI_ISA     :=
else ifeq ($(CONFIG),baremetal_linux)
  CONFIG_FRAG := configs/linux_amoeba_baremetal_linux.config
  DTS_SRC     := dts/amoeba_baremetal_linux.dts
  OUT         := $(CURDIR)/build/baremetal_linux
  # Pin OpenSBI to the core's actual ISA.  Without this the firmware is compiled
  # against the toolchain default (rv64gc/lp64d); it would still not execute an
  # FP instruction, but the ABI mismatch against a soft-float kernel payload is
  # not worth leaving to chance.
  SBI_ISA     := PLATFORM_RISCV_ISA=rv64imac_zicsr_zifencei PLATFORM_RISCV_ABI=lp64
else
  $(error CONFIG=$(CONFIG) is not a known configuration -- use baremetal_linux, or leave it unset)
endif

LINUX_VERSION   := 6.6
OPENSBI_VERSION := 1.4

LINUX_SHA256    := d926a06c63dd8ac7df3f86ee1ffc2ce2a3b81a2d168484e76b5b389aba8e56d0
OPENSBI_SHA256  := 319b62a4186fbce9b81a0c5f0ec9f003a10c808397a72138bc9745d9b87b1eb1

# Memory layout.  The shim sits on the reset vector; OpenSBI starts 2 MB up so
# that its payload -- the kernel -- lands on a 2 MB boundary, which is what the
# RISC-V boot protocol wants.  Nothing is wasted by the gap: the .lst format
# stores each blob under its own @address, so unused space costs no image bytes
# and no simulator memory.
SHIM_ADDR    := 0x80000000
OPENSBI_ADDR := 0x80200000

# Declared timebase.  MUST match the real CLINT rate: MTIME increments once per
# 100 MHz system clock.  Understating it was tried and livelocks the kernel --
# see dts/amoeba.dts.
#
# On FPGA this is not 100 MHz.  MTIME ticks off HCLK (TIMECLK is tied low), so
# the truth there is whatever FCLK_CLK0 ends up being -- pass TIMEBASE_HZ to
# match, or the kernel's idea of a nanosecond is wrong by that ratio.
TIMEBASE_HZ ?= 100000000

NPROC ?= $(shell nproc)

TOP        := $(CURDIR)
BUILD      := $(TOP)/build
DL         := $(BUILD)/dl
LINUX_SRC  := $(BUILD)/linux-$(LINUX_VERSION)
SBI_SRC    := $(BUILD)/opensbi-$(OPENSBI_VERSION)
REPO       := $(TOP)/../..

# Per-config output trees.  Both the kernel and OpenSBI are built out-of-tree
# (O=) so switching CONFIG does not invalidate the other image's objects.  The
# shared source trees stay clean, which kbuild requires once O= is in use.
KBUILD_OUT := $(OUT)/kbuild
SBI_OUT    := $(OUT)/opensbi

# ---- toolchain --------------------------------------------------------------
# The kernel's VDSO is a shared object, and the bare-metal riscv64-unknown-elf-
# toolchain the rest of the repo uses cannot link one -- it fails with
# "-shared not supported".  A Linux-targeting cross compiler is mandatory here.
#
# If the host already has one, use it.  Otherwise fetch kernel.org's nolibc
# cross toolchain, which exists precisely for building kernels: 33 MB rather
# than a full distro toolchain, no root needed, and pinned by checksum like
# every other input.  Override by setting CROSS_COMPILE on the command line.
TC_VERSION := 13.2.0
TC_SHA256  := 07c58f4551e636cbe8ba16707909e94ac262f45dc8fe28034011842bdc0c7417
TC_BIN     := $(BUILD)/gcc-$(TC_VERSION)-nolibc/riscv64-linux/bin

HOST_CROSS := $(shell for p in riscv64-linux-gnu- riscv64-unknown-linux-gnu-; do \
                  command -v $${p}gcc >/dev/null 2>&1 && echo $$p && break; done)

ifndef CROSS_COMPILE
  ifeq ($(HOST_CROSS),)
    CROSS_COMPILE := $(TC_BIN)/riscv64-linux-
    TOOLCHAIN_DEP := $(TC_BIN)/riscv64-linux-gcc
  else
    CROSS_COMPILE := $(HOST_CROSS)
  endif
endif

KERNEL_IMAGE := $(KBUILD_OUT)/arch/riscv/boot/Image
FW_PAYLOAD   := $(SBI_OUT)/platform/generic/firmware/fw_payload.bin

KMAKE := $(MAKE) -C $(LINUX_SRC) O=$(KBUILD_OUT) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE)

.PHONY: all smoke clean distclean check-toolchain
all: $(OUT)/boot.lst

check-toolchain: $(TOOLCHAIN_DEP)
	@command -v $(CROSS_COMPILE)gcc >/dev/null 2>&1 || { \
	  echo "error: $(CROSS_COMPILE)gcc not usable"; exit 1; }
	@echo "using CROSS_COMPILE=$(CROSS_COMPILE)"
	@echo "building CONFIG=$(if $(CONFIG),$(CONFIG),<default: pkg/config.vh>) into $(OUT)"

$(TC_BIN)/riscv64-linux-gcc: $(DL)/riscv64-cross.tar.xz
	mkdir -p $(BUILD)
	tar -C $(BUILD) -xf $<
	touch $@

$(DL)/riscv64-cross.tar.xz:
	mkdir -p $(DL)
	curl -fsSL -o $@ https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/x86_64/$(TC_VERSION)/x86_64-gcc-$(TC_VERSION)-nolibc-riscv64-linux.tar.xz
	echo "$(TC_SHA256)  $@" | sha256sum -c -

# ---- sources ----------------------------------------------------------------
# Checksums are pinned so a boot regression can never be an upstream tarball
# quietly changing underneath us.

$(DL)/linux-$(LINUX_VERSION).tar.xz:
	mkdir -p $(DL)
	curl -fsSL -o $@ https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$(LINUX_VERSION).tar.xz
	echo "$(LINUX_SHA256)  $@" | sha256sum -c -

$(DL)/opensbi-$(OPENSBI_VERSION).tar.gz:
	mkdir -p $(DL)
	curl -fsSL -o $@ https://github.com/riscv-software-src/opensbi/archive/refs/tags/v$(OPENSBI_VERSION).tar.gz
	echo "$(OPENSBI_SHA256)  $@" | sha256sum -c -

$(LINUX_SRC)/Makefile: $(DL)/linux-$(LINUX_VERSION).tar.xz
	mkdir -p $(BUILD)
	tar -C $(BUILD) -xf $<
	touch $@

$(SBI_SRC)/Makefile: $(DL)/opensbi-$(OPENSBI_VERSION).tar.gz
	mkdir -p $(BUILD)
	tar -C $(BUILD) -xf $<
	touch $@

# ---- userland ---------------------------------------------------------------
# /init is freestanding assembly against the Linux syscall ABI, so the newlib
# bare-metal toolchain is all that is needed -- no musl, no glibc, no buildroot.
#
# Config-independent, and shared by every config: rv64imac/lp64 is already the
# soft-float ABI and init.S contains no FP instruction, so there is no
# soft-float userland to rebuild when the FPU goes away.
$(BUILD)/init: initramfs/init.S | check-toolchain
	mkdir -p $(BUILD)
	$(CROSS_COMPILE)gcc -march=rv64imac -mabi=lp64 -nostdlib -nostartfiles -static \
	    -Wl,--build-id=none -o $@ $<
	$(CROSS_COMPILE)strip $@

# gen_init_cpio reads this and creates /dev/console without needing root.
$(BUILD)/initramfs.spec: initramfs/initramfs.spec $(BUILD)/init
	sed 's|@INIT@|$(BUILD)/init|' $< > $@

# ---- device tree ------------------------------------------------------------

$(OUT)/amoeba.dtb: $(DTS_SRC)
	mkdir -p $(OUT)
	cpp -nostdinc -undef -D__DTS__ -DAMOEBA_TIMEBASE_HZ=$(TIMEBASE_HZ) \
	    -x assembler-with-cpp $< -o $(OUT)/amoeba.dts.pre
	dtc -I dts -O dtb -o $@ $(OUT)/amoeba.dts.pre

# ---- kernel -----------------------------------------------------------------
# merge_config.sh takes the fragments in order and the later one wins, so the
# per-config delta only has to state what differs from configs/linux_amoeba.config.

# kbuild refuses to run with O= against a source tree that holds objects from a
# previous in-tree build ("the source tree is not clean").  Every config builds
# out-of-tree now, so convert the tree once and stamp it.  Idempotent, and only
# ever fires for a checkout that predates the CONFIG split.
$(LINUX_SRC)/.amoeba-outoftree: $(LINUX_SRC)/Makefile
	$(MAKE) -C $(LINUX_SRC) ARCH=riscv mrproper
	touch $@

$(KERNEL_IMAGE): $(LINUX_SRC)/Makefile $(LINUX_SRC)/.amoeba-outoftree $(BUILD)/initramfs.spec configs/linux_amoeba.config $(CONFIG_FRAG) | check-toolchain
	mkdir -p $(KBUILD_OUT)
	$(KMAKE) defconfig
	$(LINUX_SRC)/scripts/kconfig/merge_config.sh -m -O $(KBUILD_OUT) \
	    $(KBUILD_OUT)/.config $(TOP)/configs/linux_amoeba.config \
	    $(if $(CONFIG_FRAG),$(TOP)/$(CONFIG_FRAG),)
	cd $(LINUX_SRC) && ./scripts/config --file $(KBUILD_OUT)/.config \
	    --set-str INITRAMFS_SOURCE "$(BUILD)/initramfs.spec"
	$(KMAKE) olddefconfig
	$(KMAKE) -j$(NPROC) Image

# ---- firmware ---------------------------------------------------------------
# fw_payload embeds both the kernel and the device tree, so the whole boot is a
# single flat blob with no runtime FDT plumbing.

$(FW_PAYLOAD): $(SBI_SRC)/Makefile $(KERNEL_IMAGE) $(OUT)/amoeba.dtb | check-toolchain
	$(MAKE) -C $(SBI_SRC) -j$(NPROC) O=$(SBI_OUT) \
	    PLATFORM=generic \
	    CROSS_COMPILE=$(CROSS_COMPILE) \
	    $(SBI_ISA) \
	    FW_TEXT_START=$(OPENSBI_ADDR) \
	    FW_PAYLOAD=y \
	    FW_PAYLOAD_PATH=$(KERNEL_IMAGE) \
	    FW_FDT_PATH=$(OUT)/amoeba.dtb

# ---- shim + final image -----------------------------------------------------

$(OUT)/boot_shim.bin: boot_shim.S | check-toolchain
	mkdir -p $(OUT)
	$(CROSS_COMPILE)gcc -march=rv64imac -mabi=lp64 -nostdlib -nostartfiles -static \
	    -DOPENSBI_ADDR=$(OPENSBI_ADDR) -Wl,--build-id=none -Wl,-Ttext=$(SHIM_ADDR) \
	    -o $(OUT)/boot_shim.elf $<
	$(CROSS_COMPILE)objcopy -O binary $(OUT)/boot_shim.elf $@

$(OUT)/boot.lst: $(OUT)/boot_shim.bin $(FW_PAYLOAD)
	python3 $(REPO)/bin/linux_image_to_lst.py -o $@ \
	    $(OUT)/boot_shim.bin@$(SHIM_ADDR) \
	    $(FW_PAYLOAD)@$(OPENSBI_ADDR)

# ---- console-path pre-flight ------------------------------------------------
# Drives the CVW NS16550 directly from the reset vector.  Cheap (a few thousand
# cycles) and worth running first whenever the testbench changes: it proves the
# UART tap, the .lst loader and the pass matcher all still work, without waiting
# on a kernel build.
#
# Built rv64imac/lp64 rather than rv64gc/lp64d so the same binary runs on every
# config.  It contains no FP instruction, so this costs nothing on the full
# config and is the difference between running and trapping on a pruned one.

smoke: $(OUT)/uart_smoke.lst

$(OUT)/uart_smoke.lst: uart_smoke.S | check-toolchain
	mkdir -p $(OUT)
	$(CROSS_COMPILE)gcc -march=rv64imac -mabi=lp64 -mcmodel=medany -ffreestanding \
	    -nostartfiles -nostdlib -static -Wl,--no-relax -T $(REPO)/bin/link.ld \
	    -o $(OUT)/uart_smoke.elf $<
	$(CROSS_COMPILE)objcopy -O binary $(OUT)/uart_smoke.elf $(OUT)/uart_smoke.bin
	python3 $(REPO)/bin/linux_image_to_lst.py -o $@ $(OUT)/uart_smoke.bin@$(SHIM_ADDR)

# clean removes this config's products only, so cleaning one image does not
# force a rebuild of the other.  The shared init/initramfs.spec go too; they
# cost seconds.
clean:
	rm -rf $(OUT)/boot.lst $(OUT)/boot_shim.* $(OUT)/amoeba.dt* \
	       $(OUT)/uart_smoke.* $(KBUILD_OUT) $(SBI_OUT)
	rm -f  $(BUILD)/init $(BUILD)/initramfs.spec

distclean:
	rm -rf $(BUILD)
