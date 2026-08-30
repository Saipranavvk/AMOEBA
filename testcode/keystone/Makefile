# Boot-image build for the AMOEBA Keystone test (milestones K0 and K1).
#
#   make            build/boot.lst -- OpenSBI+SM + kernel + initramfs
#   make clean      remove build products, keep downloaded tarballs
#   make distclean  remove everything including downloads
#
# Siloed from testcode/linux on purpose: this image pins a different OpenSBI,
# uses a different memory map, and builds a kernel with a different config.  It
# has its own source trees so the two never thrash each other's build state.
#
# One image serves both milestones; they differ only in how far the boot has to
# get, selected by the pass string (see README):
#   K0  "[SM] Keystone security monitor has been initialized!"   ~4M cycles
#   K1  "AMOEBA_KEYSTONE_DRV_OK"                                ~216M cycles

LINUX_VERSION   := 6.6
OPENSBI_VERSION := 1.1
KEYSTONE_COMMIT := 73aeab79b97f4cea3e418897841e5534fc978f4b

LINUX_SHA256    := d926a06c63dd8ac7df3f86ee1ffc2ce2a3b81a2d168484e76b5b389aba8e56d0
OPENSBI_SHA256  := d183cb890130983a4f01e75fc03ee4f7ea0e16a7923b8af9c6dff7deb2fedaec
# GitHub's per-commit archives are not contractually byte-stable.  If this
# checksum ever fails, verify the commit still exists and re-pin -- a loud
# failure is the point.
KEYSTONE_SHA256 := 7ddeea5c072d16870c01811b65c248aebcb0e66c0a1c2f10f8a0e10f4c5d5dd9

# OpenSBI 1.1, not the 1.4 the Linux test uses.  That is Keystone's own target
# (their buildroot defconfig pins it) and the SM does not build against 1.4
# without porting.  Siloing is what makes taking their version free.

# Memory layout -- different from the Linux test, and not by choice.  Keystone's
# opensbi-firmware-secure-boot patch hardcodes the Sanctum key page at
# 0x801ff000, described as "the last page before the payload", which fixes the
# firmware at 0x80000000 and the payload at 0x80200000.  There is therefore no
# room for the boot shim the Linux image puts on the reset vector.  Dropping it
# is safe: the shim only set a0=hartid=0, and a0 is already 0 at reset.
FW_TEXT_START := 0x80000000

TIMEBASE_HZ ?= 100000000
NPROC       ?= $(shell nproc)

TOP        := $(CURDIR)
BUILD      := $(TOP)/build
DL         := $(BUILD)/dl
LINUX_SRC  := $(BUILD)/linux-$(LINUX_VERSION)
SBI_SRC    := $(BUILD)/opensbi-$(OPENSBI_VERSION)
KS_SRC     := $(BUILD)/keystone-$(KEYSTONE_COMMIT)
REPO       := $(TOP)/../..

# The device tree is shared with the Linux test rather than copied: it
# describes the same silicon, and a second copy would drift.  Fork it here only
# when Keystone needs something Linux does not (a reserved-memory pool for
# enclave EPM is the likely first reason, at K3).
DTS := $(TOP)/../linux/dts/amoeba.dts

# ---- toolchain --------------------------------------------------------------
# Same rationale as testcode/linux: the kernel VDSO needs a Linux-targeting
# cross compiler, which the bare-metal riscv64-unknown-elf- toolchain is not.
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
DRV_DIR      := $(LINUX_SRC)/drivers/keystone

KMAKE := $(MAKE) -C $(LINUX_SRC) ARCH=riscv CROSS_COMPILE=$(CROSS_COMPILE)

.PHONY: all clean distclean check-toolchain
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

$(DL)/linux-$(LINUX_VERSION).tar.xz:
	mkdir -p $(DL)
	curl -fsSL -o $@ https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$(LINUX_VERSION).tar.xz
	echo "$(LINUX_SHA256)  $@" | sha256sum -c -

$(DL)/opensbi-$(OPENSBI_VERSION).tar.gz:
	mkdir -p $(DL)
	curl -fsSL -o $@ https://github.com/riscv-software-src/opensbi/archive/refs/tags/v$(OPENSBI_VERSION).tar.gz
	echo "$(OPENSBI_SHA256)  $@" | sha256sum -c -

$(DL)/keystone-$(KEYSTONE_COMMIT).tar.gz:
	mkdir -p $(DL)
	curl -fsSL -o $@ https://github.com/keystone-enclave/keystone/archive/$(KEYSTONE_COMMIT).tar.gz
	echo "$(KEYSTONE_SHA256)  $@" | sha256sum -c -

$(LINUX_SRC)/Makefile: $(DL)/linux-$(LINUX_VERSION).tar.xz
	mkdir -p $(BUILD)
	tar -C $(BUILD) -xf $<
	touch $@

# ---- keystone sources + our platform patch ----------------------------------
# Keystone's generic platform_override matches only QEMU's compatible strings,
# so without this patch sm_init() is never called and the SM is silently
# linked-but-dead.  See patches/keystone-sm-amoeba-platform.patch.

$(KS_SRC)/.patched: $(DL)/keystone-$(KEYSTONE_COMMIT).tar.gz $(REPO)/patches/keystone-sm-amoeba-platform.patch
	mkdir -p $(BUILD)
	rm -rf $(KS_SRC)
	tar -C $(BUILD) -xf $<
	patch -s -d $(KS_SRC) -p1 < $(REPO)/patches/keystone-sm-amoeba-platform.patch
	touch $@

# ---- opensbi + keystone's own patches ---------------------------------------
# change-basename fixes PLATFORM_DIR handling; firmware-secure-boot adds the
# Sanctum key region the SM reads for attestation.  Both ship with Keystone.

$(SBI_SRC)/.patched: $(DL)/opensbi-$(OPENSBI_VERSION).tar.gz $(KS_SRC)/.patched
	mkdir -p $(BUILD)
	rm -rf $(SBI_SRC)
	tar -C $(BUILD) -xf $<
	for p in $(KS_SRC)/overlays/keystone/patches/opensbi/*.patch; do \
	    patch -s -d $(SBI_SRC) -p1 < $$p || exit 1; \
	done
	touch $@

# ---- driver injection -------------------------------------------------------
# The driver ships as an out-of-tree module (obj-m), but CONFIG_MODULES is off,
# so it is copied into the kernel tree and built in: module_init then becomes a
# device_initcall and the initramfs needs no module loader.  It compiles against
# 6.6 unmodified -- only the build glue below is ours.

$(DRV_DIR)/.stamp: $(KS_SRC)/.patched $(LINUX_SRC)/Makefile
	mkdir -p $(DRV_DIR)
	cp $(KS_SRC)/linux-keystone-driver/*.c $(KS_SRC)/linux-keystone-driver/*.h $(DRV_DIR)/
	cp $(KS_SRC)/sdk/include/shared/*.h $(DRV_DIR)/
	printf '%s\n' \
	  'config KEYSTONE_DRIVER' \
	  '	bool "Keystone enclave driver"' \
	  '	depends on RISCV_SBI' \
	  '	help' \
	  '	  Built-in Keystone enclave driver.  Registers the misc device' \
	  '	  /dev/keystone_enclave and forwards enclave lifecycle calls to' \
	  '	  the security monitor over SBI.' \
	  > $(DRV_DIR)/Kconfig
	printf '%s\n' \
	  'obj-y += keystone-driver.o' \
	  'keystone-driver-y := keystone.o keystone-page.o keystone-ioctl.o \' \
	  '                     keystone-enclave.o keystone-sbi.o' \
	  'ccflags-y := -I$$(src)' \
	  > $(DRV_DIR)/Makefile
	grep -q 'drivers/keystone/Kconfig' $(LINUX_SRC)/drivers/Kconfig || \
	  sed -i '/^endmenu/i source "drivers/keystone/Kconfig"' $(LINUX_SRC)/drivers/Kconfig
	grep -q 'keystone/' $(LINUX_SRC)/drivers/Makefile || \
	  echo 'obj-$$(CONFIG_KEYSTONE_DRIVER) += keystone/' >> $(LINUX_SRC)/drivers/Makefile
	touch $@

# ---- userland ---------------------------------------------------------------

$(BUILD)/init: initramfs/init.S | check-toolchain
	mkdir -p $(BUILD)
	$(CROSS_COMPILE)gcc -march=rv64imac -mabi=lp64 -nostdlib -nostartfiles -static \
	    -Wl,--build-id=none -o $@ $<
	$(CROSS_COMPILE)strip $@

$(BUILD)/initramfs.spec: initramfs/initramfs.spec $(BUILD)/init
	sed 's|@INIT@|$(BUILD)/init|' $< > $@

# ---- device tree ------------------------------------------------------------

$(BUILD)/amoeba.dtb: $(DTS)
	mkdir -p $(BUILD)
	cpp -nostdinc -undef -D__DTS__ -DAMOEBA_TIMEBASE_HZ=$(TIMEBASE_HZ) \
	    -x assembler-with-cpp $< -o $(BUILD)/amoeba.dts.pre
	dtc -I dts -O dtb -o $@ $(BUILD)/amoeba.dts.pre

# ---- kernel -----------------------------------------------------------------
# linux_amoeba.config is the base and keystone.config the overlay: that file is
# the only known-good configuration for this core, so it is merged, not forked.

$(KERNEL_IMAGE): $(LINUX_SRC)/Makefile $(DRV_DIR)/.stamp $(BUILD)/initramfs.spec \
                 configs/keystone.config $(TOP)/../linux/configs/linux_amoeba.config \
                 | check-toolchain
	$(KMAKE) defconfig
	$(LINUX_SRC)/scripts/kconfig/merge_config.sh -m -O $(LINUX_SRC) \
	    $(LINUX_SRC)/.config \
	    $(TOP)/../linux/configs/linux_amoeba.config \
	    $(TOP)/configs/keystone.config
	cd $(LINUX_SRC) && ./scripts/config --file .config \
	    --set-str INITRAMFS_SOURCE "$(BUILD)/initramfs.spec"
	$(KMAKE) olddefconfig
	@grep -q '^CONFIG_KEYSTONE_DRIVER=y' $(LINUX_SRC)/.config || { \
	  echo "error: CONFIG_KEYSTONE_DRIVER did not survive olddefconfig"; exit 1; }
	$(KMAKE) -j$(NPROC) Image

# ---- security monitor firmware ----------------------------------------------
# The SM is an out-of-tree OpenSBI platform: PLATFORM_DIR points at it and
# OpenSBI builds the SM sources into the firmware.

$(FW_PAYLOAD): $(SBI_SRC)/.patched $(KERNEL_IMAGE) $(BUILD)/amoeba.dtb | check-toolchain
	$(MAKE) -C $(SBI_SRC) -j$(NPROC) \
	    PLATFORM=generic \
	    PLATFORM_DIR=$(KS_SRC)/sm/plat \
	    KEYSTONE_SM=$(KS_SRC)/sm \
	    KEYSTONE_SDK_DIR=$(KS_SRC)/sdk \
	    KEYSTONE_PLATFORM=generic \
	    CROSS_COMPILE=$(CROSS_COMPILE) \
	    FW_TEXT_START=$(FW_TEXT_START) \
	    FW_PAYLOAD=y \
	    FW_PAYLOAD_PATH=$(KERNEL_IMAGE) \
	    FW_FDT_PATH=$(BUILD)/amoeba.dtb
	@$(CROSS_COMPILE)nm $(SBI_SRC)/build/platform/generic/firmware/fw_payload.elf \
	    | grep -q ' T sbi_sm_create_enclave' || { \
	  echo "error: security monitor is not linked into the firmware"; exit 1; }

# ---- final image ------------------------------------------------------------

$(BUILD)/boot.lst: $(FW_PAYLOAD)
	python3 $(REPO)/bin/linux_image_to_lst.py -o $@ $(FW_PAYLOAD)@$(FW_TEXT_START)

clean:
	rm -rf $(BUILD)/boot.lst $(BUILD)/init $(BUILD)/initramfs.spec \
	       $(BUILD)/amoeba.dt* $(SBI_SRC)/build

distclean:
	rm -rf $(BUILD)
