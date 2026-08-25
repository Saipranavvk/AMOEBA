# Boot-image build for the AMOEBA Linux boot test.
#
#   make            build/boot.lst -- shim + OpenSBI + kernel + initramfs
#   make smoke      build/uart_smoke.lst -- console-path pre-flight, no firmware
#   make clean      remove build products, keep downloaded tarballs
#   make distclean  remove everything including downloads
#
# This is the image-build path, run locally or by a dedicated CI workflow.  The
# nightly boot job must NOT run it: fetching and building a kernel costs 10-30
# minutes that would come straight out of the simulation budget.  Publish
# build/boot.lst as an artifact instead.

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
TIMEBASE_HZ ?= 100000000

NPROC ?= $(shell nproc)

TOP        := $(CURDIR)
BUILD      := $(TOP)/build
DL         := $(BUILD)/dl
LINUX_SRC  := $(BUILD)/linux-$(LINUX_VERSION)
SBI_SRC    := $(BUILD)/opensbi-$(OPENSBI_VERSION)
REPO       := $(TOP)/../..

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

KERNEL_IMAGE := $(LINUX_SRC)/arch/riscv/boot/Image
FW_PAYLOAD   := $(SBI_SRC)/build/platform/generic/firmware/fw_payload.bin

KMAKE := $(MAKE) -C $(LINUX_SRC) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE)

.PHONY: all smoke clean distclean check-toolchain
all: $(BUILD)/boot.lst

check-toolchain: $(TOOLCHAIN_DEP)
	@command -v $(CROSS_COMPILE)gcc >/dev/null 2>&1 || { \
	  echo "error: $(CROSS_COMPILE)gcc not usable"; exit 1; }
	@echo "using CROSS_COMPILE=$(CROSS_COMPILE)"

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

$(BUILD)/init: initramfs/init.S | check-toolchain
	mkdir -p $(BUILD)
	$(CROSS_COMPILE)gcc -march=rv64imac -mabi=lp64 -nostdlib -nostartfiles -static \
	    -Wl,--build-id=none -o $@ $<
	$(CROSS_COMPILE)strip $@

# gen_init_cpio reads this and creates /dev/console without needing root.
$(BUILD)/initramfs.spec: initramfs/initramfs.spec $(BUILD)/init
	sed 's|@INIT@|$(BUILD)/init|' $< > $@

# ---- device tree ------------------------------------------------------------

$(BUILD)/amoeba.dtb: dts/amoeba.dts
	mkdir -p $(BUILD)
	cpp -nostdinc -undef -D__DTS__ -DAMOEBA_TIMEBASE_HZ=$(TIMEBASE_HZ) \
	    -x assembler-with-cpp $< -o $(BUILD)/amoeba.dts.pre
	dtc -I dts -O dtb -o $@ $(BUILD)/amoeba.dts.pre

# ---- kernel -----------------------------------------------------------------

$(KERNEL_IMAGE): $(LINUX_SRC)/Makefile $(BUILD)/initramfs.spec configs/linux_amoeba.config | check-toolchain
	$(KMAKE) defconfig
	$(LINUX_SRC)/scripts/kconfig/merge_config.sh -m -O $(LINUX_SRC) \
	    $(LINUX_SRC)/.config $(TOP)/configs/linux_amoeba.config
	cd $(LINUX_SRC) && ./scripts/config --file .config \
	    --set-str INITRAMFS_SOURCE "$(BUILD)/initramfs.spec"
	$(KMAKE) olddefconfig
	$(KMAKE) -j$(NPROC) Image

# ---- firmware ---------------------------------------------------------------
# fw_payload embeds both the kernel and the device tree, so the whole boot is a
# single flat blob with no runtime FDT plumbing.

$(FW_PAYLOAD): $(SBI_SRC)/Makefile $(KERNEL_IMAGE) $(BUILD)/amoeba.dtb | check-toolchain
	$(MAKE) -C $(SBI_SRC) -j$(NPROC) \
	    PLATFORM=generic \
	    CROSS_COMPILE=$(CROSS_COMPILE) \
	    FW_TEXT_START=$(OPENSBI_ADDR) \
	    FW_PAYLOAD=y \
	    FW_PAYLOAD_PATH=$(KERNEL_IMAGE) \
	    FW_FDT_PATH=$(BUILD)/amoeba.dtb

# ---- shim + final image -----------------------------------------------------

$(BUILD)/boot_shim.bin: boot_shim.S | check-toolchain
	mkdir -p $(BUILD)
	$(CROSS_COMPILE)gcc -march=rv64imac -mabi=lp64 -nostdlib -nostartfiles -static \
	    -DOPENSBI_ADDR=$(OPENSBI_ADDR) -Wl,--build-id=none -Wl,-Ttext=$(SHIM_ADDR) \
	    -o $(BUILD)/boot_shim.elf $<
	$(CROSS_COMPILE)objcopy -O binary $(BUILD)/boot_shim.elf $@

$(BUILD)/boot.lst: $(BUILD)/boot_shim.bin $(FW_PAYLOAD)
	python3 $(REPO)/bin/linux_image_to_lst.py -o $@ \
	    $(BUILD)/boot_shim.bin@$(SHIM_ADDR) \
	    $(FW_PAYLOAD)@$(OPENSBI_ADDR)

# ---- console-path pre-flight ------------------------------------------------
# Drives the CVW NS16550 directly from the reset vector.  Cheap (a few thousand
# cycles) and worth running first whenever the testbench changes: it proves the
# UART tap, the .lst loader and the pass matcher all still work, without waiting
# on a kernel build.

smoke: $(BUILD)/uart_smoke.lst

$(BUILD)/uart_smoke.lst: uart_smoke.S | check-toolchain
	mkdir -p $(BUILD)
	$(CROSS_COMPILE)gcc -march=rv64gc -mabi=lp64d -mcmodel=medany -ffreestanding \
	    -nostartfiles -nostdlib -static -Wl,--no-relax -T $(REPO)/bin/link.ld \
	    -o $(BUILD)/uart_smoke.elf $<
	$(CROSS_COMPILE)objcopy -O binary $(BUILD)/uart_smoke.elf $(BUILD)/uart_smoke.bin
	python3 $(REPO)/bin/linux_image_to_lst.py -o $@ $(BUILD)/uart_smoke.bin@$(SHIM_ADDR)

clean:
	rm -rf $(BUILD)/boot.lst $(BUILD)/boot_shim.* $(BUILD)/amoeba.dt* \
	       $(BUILD)/init $(BUILD)/initramfs.spec $(BUILD)/uart_smoke.*
	-$(MAKE) -C $(SBI_SRC) PLATFORM=generic clean 2>/dev/null
	-$(KMAKE) clean 2>/dev/null

distclean:
	rm -rf $(BUILD)
