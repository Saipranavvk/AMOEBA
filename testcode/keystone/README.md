# Keystone enclave boot test

Boots Linux 6.6 under the [Keystone](https://github.com/keystone-enclave/keystone)
security monitor on the AMOEBA CVW core, and checks that the enclave device is
usable from userspace.

What this proves is a fact about the **hardware**: that the core's 16 PMP
entries, its M/S/U privilege transitions and its SBI path are correct enough to
run a real security monitor. See [Scope](#scope-what-this-does-not-prove) before
quoting it as anything else.

## Milestones

One image serves both; they differ only in how far the boot must get, selected
by `LINUX_PASS`. Measured on a 20-core desktop:

| | `LINUX_PASS=` | Cycles | Wall | Proves |
|---|---|---|---|---|
| K0 | `[SM] Keystone security monitor has been initialized` | 4,054,809 | 27 s | SM init, PMP regions configured |
| K1 | `AMOEBA_KEYSTONE_DRV_OK` | 213,109,912 | 1,329 s | `/dev/keystone_enclave` opens |

K1 costs **under 0.5% more than the plain Linux boot** (212,140,674 cycles).
The SM's work is front-loaded before the kernel starts and the driver is a
single `misc_register()`, so neither shows up at this scale.

K0 is cheap enough to be a PR gate on its own, and worth running *before* K1:
it separates "the SM did not come up" from "the boot did not finish", which a
K1 failure alone cannot distinguish.

## Build and run

```bash
make -C testcode/keystone                 # ~2m12s from scratch -> build/boot.lst
make -C sim build_linux                   # the Linux simulator; see below

make -C sim linux_boot \
    LINUX_MEMLST=$PWD/testcode/keystone/build/boot.lst \
    LINUX_RUN_DIR=verilator/keystone_k1 \
    LINUX_PASS=AMOEBA_KEYSTONE_DRV_OK \
    LINUX_TIMEOUT=400000000
```

`build_linux` is reused deliberately. Keystone needs identical testbench
behaviour -- same UART tap, same halt instruction, same misaligned waiver, same
`ECE411_LINUX`/`ECE411_NO_TRACE` defines -- so sharing the simulator avoids a
second Verilator build and guarantees both tests exercise the same RTL.

## How it differs from the Linux boot

**OpenSBI 1.1, not 1.4.** That is Keystone's own target, pinned in their
buildroot defconfig. The SM does not build against 1.4 without porting, and
siloing the two tests is what makes taking their version free.

**No boot shim, and a different memory map.** Keystone's
`opensbi-firmware-secure-boot` patch hardcodes the Sanctum key page at
`0x801ff000`, described as "the last page before the payload". That fixes the
firmware at `0x80000000` and the payload at `0x80200000`, leaving no room for
the shim the Linux image puts on the reset vector. Dropping it is safe: the
shim only set `a0`=hartid=0, and `a0` is already 0 at reset.

**Its own kernel tree.** The two configs differ, so a shared tree would force a
full kernel rebuild on every alternation between the tests.

**Shared DTS and base config.** `dts/amoeba.dts` and `configs/linux_amoeba.config`
come from `testcode/linux` rather than being copied: they describe the same
silicon and the same known-good kernel configuration, and a second copy would
drift. `configs/keystone.config` is merged *on top* as an overlay. Fork the DTS
only when Keystone needs something Linux does not -- a `reserved-memory` pool
for enclave EPM is the likely first reason, at K3.

## The security monitor

The SM is an **out-of-tree OpenSBI platform**. `PLATFORM_DIR` points at it and
OpenSBI compiles the SM sources into the firmware:

```
make -C opensbi PLATFORM=generic PLATFORM_DIR=<keystone>/sm/plat \
     KEYSTONE_SM=<keystone>/sm KEYSTONE_SDK_DIR=<keystone>/sdk \
     KEYSTONE_PLATFORM=generic
```

Three patches are applied, two of which ship with Keystone:

| Patch | Source | Purpose |
|---|---|---|
| `opensbi-change-basename` | Keystone | `PLATFORM_DIR` handling in OpenSBI's Makefile |
| `opensbi-firmware-secure-boot` | Keystone | adds the Sanctum key region at `0x801ff000` |
| `keystone-sm-amoeba-platform` | ours, in `patches/` | registers `amoeba,cvw` with the SM |

That last one is not optional, and its absence is invisible. OpenSBI selects a
`platform_override` module by matching the device tree root's `compatible`
string, and Keystone's table lists only QEMU's `riscv-virtio` and
`riscv-virtio,qemu`. Without an entry for `amoeba,cvw`, `generic_final_init()`
is never called, `sm_init()` never runs, and the result **looks exactly like
success**: the firmware boots, Linux boots, nothing errors, and the only
symptom is that no `[SM]` line ever appears.

## The driver

Keystone ships the driver as an out-of-tree module (`obj-m`), but
`CONFIG_MODULES` is off in the base config. It is therefore copied into the
kernel tree as `drivers/keystone` and built in, so its `module_init` becomes a
`device_initcall` and the initramfs needs no module loader.

**It compiles against 6.6 unmodified** -- only the `Kconfig`/`Makefile` glue in
`testcode/keystone/Makefile` is ours. Keystone targets ~6.1 (via buildroot
2023.02.2), but the driver uses only stable APIs.

`/init` mounts devtmpfs itself because `CONFIG_DEVTMPFS_MOUNT` by design does
not cover initramfs, and the driver registers a misc device with
`MISC_DYNAMIC_MINOR` -- so its minor is assigned at registration and a static
cpio node would break whenever it shifts.

## Why K1 opens the device instead of matching a log line

The driver prints `keystone_enclave: keystone enclave v1.0.0` on success. That
is *not* what K1 matches. The driver is built in, so its initcall runs
unconditionally; if `misc_register()` fails, Linux boots normally and the only
symptom is that `/dev/keystone_enclave` is absent. Matching the `pr_info()`
would pass in exactly that case. `openat()` returning a valid descriptor cannot.

`/init` writes `AMOEBA_KEYSTONE_DRV_FAIL` when the open fails, so a broken
device fails in ~213M cycles rather than timing out at 400M.

The same reasoning drives two assertions in the Makefile, which run on every
build:

- the firmware link fails if `sbi_sm_create_enclave` is absent
- the kernel build fails if `CONFIG_KEYSTONE_DRIVER` did not survive `olddefconfig`

Both target the linked-but-dead failure mode, which otherwise produces a clean
build and a silent no-op.

## Scope: what this does *not* prove

**This is a functional result, not a security one.** The SM compiles with:

```
#pragma message("Platform has no entropy source, this is unsafe. TEST ONLY")
```

The SoC has no TRNG, so attestation keys are not securely derived. A TEE cannot
meaningfully attest without an entropy source; that is a hardware gap no choice
of TEE software fixes, and it needs closing before tape-out.

**Upstream is end-of-life.** Keystone entered the Confidential Computing
Consortium's Emeritus process in 2026 (issue #499); the maintainers confirmed
there is no lead maintainer and no active development, and the repos are
expected to be archived. The last substantive commit to the SM was June 2024.
Everything here is pinned by checksum, so the tests keep working -- but treat
Keystone as a **test workload that exercises PMP**, not as a maintained
dependency, unless someone explicitly signs up to own the fork.

The hardware constraint behind that choice: this core has no H extension
(`kvm: hypervisor extension not available` in any boot log), so CoVE/AP-TEE --
the standards-track successor -- is not available to it. A PMP-based TEE is
what this silicon can support.

## Next milestones

| | Proves | Needs |
|---|---|---|
| K2 | libc userspace runs | musl or buildroot toolchain |
| K3 | enclave created, PMP region installed | contiguous physical memory (`reserved-memory`) |
| K4 | Eyrie runtime entered, eapp runs | enclave image layout |
| K5 | attestation report verified | K4 plus a verifier |

K3 onward is where cost becomes unpredictable: the SM SHA-3 hashes every page
of an enclave at creation. Price that with a measurement before committing to a
design -- the SM's own boot-time self-measurement is the cheapest way to get
cycles-per-byte on real RTL.
