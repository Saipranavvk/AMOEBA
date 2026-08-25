# Linux boot test

Boots Linux 6.6 on the CVW core under Verilator and checks that it reached
userspace. The pass criterion is a string printed by PID 1 over the SoC's
NS16550 UART.

## Why this tier exists

The bare-metal, ISA-level and FreeRTOS tiers all run in M-mode. None of them
exercise the parts of CVW that are hardest to get right: S/U privilege
transitions, Sv39 page-table walks, hardware A/D bit updates, `sfence.vma`,
cache-block operations, or PLIC-routed device interrupts. A Linux boot hits all
of them, continuously, for hundreds of millions of cycles.

## Layout

```
Makefile                 image build: shim + OpenSBI + kernel + initramfs
boot_shim.S              reset-vector entry; sets a0=hartid, jumps to firmware
uart_smoke.S             console-path pre-flight (no firmware needed)
dts/amoeba.dts           device tree; forked from cvw/linux/devicetree/wally-virt.dts
configs/linux_amoeba.config   kernel fragment merged over riscv defconfig
initramfs/init.S         PID 1: prints the pass string, never exits
initramfs/initramfs.spec gen_init_cpio spec (creates /dev/console without root)
build/                   downloads and build products (gitignored)
```

## Memory layout

| Address | Contents |
|---|---|
| `0x8000_0000` | `boot_shim.bin` — reset vector |
| `0x8020_0000` | OpenSBI `fw_payload.bin` (device tree embedded) |
| `0x8040_0000` | Linux `Image`, with the initramfs built in |

OpenSBI starts 2 MB up so its payload lands on the 2 MB boundary the RISC-V boot
protocol expects. The gap costs nothing: the `.lst` format stores each blob
under its own `@address`, and the testbench memory is a sparse associative
array.

## Building and running

```bash
# Console-path pre-flight -- seconds, no kernel needed.  Run this first
# whenever the testbench changes.
make -C testcode/linux smoke
make -C sim linux_boot LINUX_MEMLST=$PWD/testcode/linux/build/uart_smoke.lst \
                       LINUX_PASS=AMOEBA_UART_OK LINUX_TIMEOUT=400000

# Full boot image (downloads Linux 6.6 + OpenSBI 1.4, both checksum-pinned)
make -C testcode/linux

# Build the simulator, then boot
make -C sim build_linux
make -C sim linux_boot
```

`make -C sim linux_boot` takes these overrides:

| Variable | Default | Purpose |
|---|---|---|
| `LINUX_PASS` | `AMOEBA_LINUX_BOOT_OK` | UART string that ends the run successfully |
| `LINUX_FAIL` | `Kernel panic\|Unable to handle kernel\|Oops:\|SBI panic` | `\|`-separated abort patterns |
| `LINUX_TIMEOUT` | `2000000000` | cycle budget |
| `LINUX_MEMLST` | `build/boot.lst` | image to load |

## Milestones

`LINUX_PASS` selects how far the boot has to get, so an early stage can be a
cheap CI gate while a full boot stays a nightly job. `boot_report.py` turns any
boot log into a table of these with per-phase cycle costs.

| | `LINUX_PASS=` | Proves |
|---|---|---|
| M0 | `OpenSBI v1.` | Shim, image loader, UART, M-mode firmware |
| M1 | `Linux version 6.6` | Kernel entry, SBI console |
| M2 | `printk: bootconsole` | Console handover to the 8250 driver |
| M3 | `Initmem setup node 0` | MMU enabled, page tables walked, memblock done |
| M4 | `Freeing unused kernel image` | Full kernel init, drivers probed |
| M5 | `AMOEBA_LINUX_BOOT_OK` | Userspace reached, U-mode syscalls work |

```bash
python3 testcode/linux/boot_report.py sim/verilator/linux_boot/simulation.log --wall 385
```

## Two things that make this finish in hours instead of weeks

**Waveforms are compiled out, not disabled.** `make -C sim build_linux` builds
without `--trace-fst`. `+NO_DUMP_ALL_ECE411` is not enough — the SV-side
`$dumpvars` keeps writing regardless of the plusarg. Measured on a 20-core host
over 5M cycles: 2.2 kHz with tracing live, 116 kHz without, and a boot-length
trace would run to hundreds of GB. The build is also single-threaded on purpose:
on a single-hart in-order core, `--threads 4` measured 11% *slower* than
`--threads 1` at four times the CPU.

**The device tree understates the timer by 100x.** CVW's CLINT increments MTIME
once per system clock, so the real rate is 100 MHz. At that rate one jiffy
(`HZ=100`) costs 1,000,000 simulated cycles and every `msleep(20)` costs two
million. `dts/amoeba.dts` declares 1 MHz instead (`TIMEBASE_HZ` in the Makefile),
which cuts every timer-based wait in the boot by 100x. Timer interrupts become
proportionally more frequent — one per 10,000 cycles — which is negligible.

The kernel command line also carries `no5lvl no4lvl`. Linux probes SATP for
Sv57, then Sv48, then Sv39, keeping the deepest the hardware accepts; CVW
accepts all three, so an unhinted kernel would pick Sv57 and pay a five-level
page walk on every TLB miss. These force Sv39 and its three-level walk.

## Toolchain

Everything builds with the bare-metal `riscv64-unknown-elf-` toolchain the repo
already requires. `/init` is freestanding assembly against the Linux syscall
ABI, so no musl, glibc or buildroot is needed to answer "did we reach
userspace". A richer busybox userland would need a `riscv64-*-linux-gnu`
toolchain; that is deliberately out of scope here.

## Console plumbing

Two things about the console are worth knowing before debugging a silent boot.

**The console tap must come from the UART peripheral, not RVFI.** `monitor_mem_addr`
is driven from `IEUAdrW`, which is a *virtual* address. An RVFI-based snoop on
physical `0x10000000` therefore works only while the MMU is off -- it captures
OpenSBI perfectly and then goes silent at the exact moment Linux enables paging,
which looks identical to the kernel hanging. Under `ECE411_LINUX` the testbench
instead watches the 16550's own write strobe
(`dut.soc.uncoregen.uncore.uartgen.uart.uartPC`), which is physical by
construction and works in every privilege mode.

**Characters used to appear twice.** That was two independent printers -- the
ungated RVFI capture in `hvl/common/monitor.sv` and the CVW model's own
`$write` in `uartPC16550D.sv` -- each firing once per store, not a duplicated
bus write. Both are compiled out under `ECE411_LINUX`, leaving the single
cycle-stamped `[UART @<cycle>]` stream.

## A verification-IP bug this test found

The riscv-formal monitor's `clz` and `ctz` models were both wrong, and a Linux
boot is what exposed them. The generated loops assign on *every* set bit instead
of stopping at the first, so each ended up reporting the bit at the far end of
the word -- `ctz` returned the highest set bit and `clz` the lowest. The two
instructions were effectively swapped.

The boot died at 53.5M cycles on `ctz x6, x6` with `rs1 = 0xffffff0000000000`.
The core returned 40, which is correct -- that value has 40 trailing zeros. The
monitor demanded 63, the index of its highest set bit. A value whose lowest and
highest set bits differ is required to tell the two apart, which is why no
bare-metal test had ever caught it; the kernel's `__ffs()` hits it constantly.

`hvl/common/rvfimon.v` is patched locally for all four variants (`clz64`,
`clz32`, `ctz64`, `ctz32`) by reversing the iteration order. **That file is
generated**, so the same fix belongs upstream in `third_party/riscv-formal`, and
`make -C sim check-generated` will report `rvfimon.v` as stale until it lands
there. Note that the riscv-formal submodule's working tree is currently empty in
this checkout, so the file cannot be regenerated here in any case.
