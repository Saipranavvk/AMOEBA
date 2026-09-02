# Hardware bring-up: FreeRTOS on the PYNQ-Z2

The order here is deliberate. FreeRTOS first because it needs no DDR, no DMA and
no trace path — it exercises the core, the clock, the reset, the memory backend
and the console, and nothing else. Every later capability is added against a
board that is already known to run code.

## Where things stand

| | state |
|---|---|
| PL RTL | written, lints at every config |
| Block design | builds and validates against the real board part |
| Full-design synthesis | 29.8% LUT, 77.1% BRAM, Fmax 33.3 MHz at a 25 MHz target |
| Cache at 4×4 KiB | verified: FreeRTOS 5/5, Linux boots in 216.6M cycles (2.57× faster) |
| Bitstream | not built |
| PS software | written: driver, register drift check, runner, heartbeat app |

## Phase 0 — four things that must change before any hardware run — **done**

Ordered by how badly they bite. All four are now in; kept here because the
reasoning is what stops them being undone.

### 0.1 `tohost` currently aliases onto the reset vector

`freertos_wally.ld` fixes `tohost` at `0x8080_0000`, 8 MB above RAM base. The
FPGA memory is `MEM_KB` = 128 KiB, and `amoeba_mem_bram` truncates the index
rather than faulting, so:

```
0x8080_0000 & 0x1_FFFF  =  0x0_0000
```

`tohost` lands on **offset 0 — the reset vector**. The exit write would
overwrite the first instructions of the program it is reporting on. In
simulation this never showed up because the testbench memory is 128 MB and the
address is real.

The stack aliases too, and lands in the same place. `freertos_crt.S` sets
`sp = __freertos_irq_stack_top - 4096`, and the script puts that symbol at
`ORIGIN + LENGTH` = `0x8800_0000`, so `sp` starts at `0x87FF_F000`, which masks
to `0x1_F000` — the top page of the array. So on hardware today the stack and
`tohost` would both be placed by accident, one on the reset vector and one where
the other should be.

Fixed in `testcode/freertos/freertos_pynq.ld`, a copy of `freertos_wally.ld`
with

```
RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K

/* Top page for HTIF, the page below it as a guard, and the IRQ stack under
   that.  crt0 starts the main stack a further 4 KiB down. */
PROVIDE(tohost   = 0x8001F000);
PROVIDE(fromhost = 0x8001F008);
__freertos_irq_stack_top = 0x8001E000;
```

which gives, from the top down: `tohost`/`fromhost` at `0x8001_F000`, a free
page, the IRQ stack in `0x8001_D000`–`0x8001_E000`, and the main stack growing
down from `0x8001_D000`. `_end` is around `0x8001_3AA0`, so there is roughly
37 KiB of slack between the heap and the stack.

Keep `tohost` **4 KiB-aligned**. The conflict-eviction sweep in
`syscalls_amoeba.c` depends on `tohost` landing in set 0, and with the new
geometry — 4 KiB ways, 64-byte lines, 64 sets — set index is `(addr >> 6) & 63`,
which is 0 for every 4 KiB-aligned address. The existing sweep (stride 512,
128 iterations) then puts 16 distinct tags into set 0 against 4 ways, which is
still comfortably enough to evict. No change needed to the sweep itself.

`amoeba_bus_mon`'s `TOHOST_ADDR` is now **derived** in `amoeba_pynq_top` rather
than written down a second time:

```systemverilog
localparam logic [63:0] TOHOST_ADDR = MEM_BRAM
    ? (P.EXT_MEM_BASE + 64'(MEM_KB) * 64'd1024 - 64'd4096)
    : 64'h8080_0000;
```

The linker script uses the same formula. These two are the classic pair to get
out of step, and the symptom is a run that produces correct console output and
then hangs forever waiting for an exit the monitor never saw.

### 0.2 The FreeRTOS tick is calibrated for 100 MHz

`FreeRTOSConfig.h` has `configCPU_CLOCK_HZ = 100000000` with
`configTICK_RATE_HZ = 10000`. CVW's `clint_apb` increments MTIME once per PCLK,
and PCLK here is FCLK_CLK0 at **25 MHz**, so every tick interval is 4× too long.

FreeRTOS still runs — this is a rate error, not a correctness one — but
`tc_timer_preempt` and anything with a wall-clock expectation will read wrong,
and comparing hardware timing against simulation becomes meaningless. Make the
constant come from the build:

```c
#ifndef configCPU_CLOCK_HZ
#define configCPU_CLOCK_HZ ( ( uint32_t ) 100000000 )
#endif
```

and pass `-DconfigCPU_CLOCK_HZ=25000000` from the FPGA build. Both are in:
`FreeRTOSConfig.h` guards the constant, and `TARGET=pynq` in the FreeRTOS
Makefile supplies it from `FPGA_CLOCK_HZ`. Deriving it from
one place matters more than the value: `FCLK_MHZ` in `fpga/pynq/Makefile`, the
`timebase-frequency` in any device tree, and this constant all describe the same
physical clock, and there is currently nothing stopping them from disagreeing.

### 0.3 The build has no flat-binary target

`testcode/freertos/Makefile` hardcoded `-Tfreertos_wally.ld` and emitted only an
ELF. It now takes `TARGET=sim` (default, unchanged behaviour) or `TARGET=pynq`,
which selects the linker script and the clock constant together — they are never
independently correct — and adds a `bin` target:

```bash
make -C testcode/freertos bin TARGET=pynq
# flat image: 9816 bytes -> load at ORIGIN(RAM)
```

`freertos_crt.S` zeroes `.bss` at startup, so only the file-backed sections need
loading: 9.8 KiB, not the 79 KiB memory footprint.

### 0.4 Re-runs need memory cleared — *for the Phase 3 loader*

Block RAM inferred without an init block comes up zeroed *in the bitstream*, so
the first run after programming is clean. The second is not: it starts on the
previous run's memory. The loader should zero the image region before writing,
which is cheap over the 128 KiB window and removes a class of "it only fails the
second time" that is genuinely unpleasant to chase.

## Phase 1 — bitstream

```bash
source ~/Xilinx/Vivado/2024.1/settings64.sh
make -C fpga/pynq bitstream CONFIG=baremetal_linux
```

Produces `fpga/pynq/bit/baremetal_linux-BRAM/amoeba.{bit,hwh}`. Roughly an hour.

Check before taking it to the board:

- **post-route WNS ≥ 0.** `build.tcl` prints it and warns if negative. Synthesis
  said +9.994 ns; placement will erode that, and only the post-route number is
  real.
- **the `.hwh` exists.** `build.tcl` warns if it does not. Without it
  `Overlay()` cannot discover the address map, and this is the single most
  common way a Vivado-2024.1-built overlay fails on a PYNQ image.
- **both files share the basename `amoeba`** and sit in the same directory.
  PYNQ requires this and the error when they do not is unhelpful.

## Phase 2 — board

PYNQ **v3.1** image for PYNQ-Z2, written to SD. v3.1 is built with Vivado
2024.1, which is why the toolchain was pinned there; a v3.0 image (Vivado
2022.1) will fail to parse this `.hwh`.

Copy `amoeba.bit`, `amoeba.hwh` and `fpga/pynq/sw/` to the board. Jupyter or SSH
both work; SSH is easier to script against.

## Phase 3 — PS software — **done**

```
fpga/pynq/sw/
├── amoeba/regs.py     register offsets, bit fields, base addresses
├── amoeba/mmio.py     /dev/mem word access
├── amoeba/image.py    ELF64 -> load segments, and the tohost symbol
├── amoeba/device.py   the Amoeba class
├── check_regs.py      asserts regs.py still matches the RTL
└── run_freertos.py    load, run, stream console, exit with the HTIF code
```

Plus `testcode/freertos/heartbeat_app.c`, the first workload to run.

Python under PYNQ, but with one MMIO path over `/dev/mem` rather than a pynq
backend and a fallback — PYNQ's own `MMIO` is a `/dev/mem` mapping underneath,
so a second path buys nothing but a second thing that can be subtly different.
`pynq` is imported only to download a bitstream. That also means the driver runs
on a plain Zynq Linux with no PYNQ installed.

See [sw/README.md](sw/README.md) for the details. Three things there are worth
repeating because they are the ones that prevent bad afternoons:

- **`check_regs.py`** parses `amoeba_ctl.sv`, `amoeba_trace.sv` and
  `bd_pynq.tcl` and asserts `regs.py` agrees — 21 offsets, 4 trace modes, 3 base
  addresses, the ID magic. These are the only things in the system with no
  compile-time link between hardware and software, and a mismatch reads as a
  dead board rather than an error.
- **`load()` compares the ELF's `tohost` symbol** against the address the bus
  monitor watches, before the core starts. That is §0.1 turned into a check.
- **`load()` zeroes memory first.** Block RAM comes up zeroed in the bitstream,
  so run one is clean and run two starts on run one's memory.

## Phase 4 — what a successful run looks like

The heartbeat, not the regression tests. A terminating test tells you it passed;
a heartbeat tells you the core is *still running*, which is what you want while
probing a board for the first time — and it measures the clock rather than
assuming it.

```bash
make -C testcode/freertos bin TARGET=pynq PROG=$PWD/testcode/freertos/heartbeat_app.c
sudo ./run_freertos.py --bitstream amoeba.bit --image freertos_wally.elf --soak 30
```

```
# amoeba v0.1.0  mem=128 KiB  backend=BRAM  trace=yes
HB start period_ms=100 tick_hz=10000 cpu_hz=25000000
HB seq=1 tick=1000
HB seq=2 tick=2000
...
# ran 30.002 s wall, 750050000 cycles, 219847112 retired, 0 traps
# fabric clock (PL cycles / wall time): 25.000 MHz
# heartbeat: 299 beats, mean 100.03 ms, jitter 0.15 ms (guest intends 100 ms)
# clock calibration OK (+0.0% off the intended period)
# clock cross-check: guest timer says 25.000 MHz, PL counter says 25.000 MHz (+0.0%, consistent)
```

Five independent things have to hold for that:

| | proves |
|---|---|
| `ID` reads `AMOB` | bitstream loaded, register map correct |
| `cycles` advances | core is clocked and out of reset |
| `retired` advances, `traps` = 0 | it is executing, and not trapping in a loop |
| console text is well-formed | the whole store → AHB → snoop → FIFO → PS path works |
| beats land on 100 ms | CLINT, the FreeRTOS tick, and `configCPU_CLOCK_HZ` all agree |

The last one is the one nothing else can catch. Every terminating test verifies
ordering and results, not rates, so a 4× wrong `configCPU_CLOCK_HZ` passes the
entire suite while every interval in the system is wrong. Here it shows up as
400 ms beats and the runner prints the exact constant to rebuild with.

### Then equivalence

Once the heartbeat is steady, the five regression tests, and three numbers per
test compared against simulation:

- the **tohost code** matches
- the **console output** is byte-identical
- the **retired count** matches *exactly*

The third is the strong one. This configuration is deterministic from reset — no
DDR refresh, no external interrupts, one clock — so the hardware should retire
exactly the instructions the simulator did. A mismatch localises to a known
instruction count, which is precisely the input the Phase 6 trace window takes.

`cycles` will **not** match and should not be expected to: simulation memory has
a fixed 3-cycle latency and block RAM has one.

## Phase 5 — regression integration

Add an FPGA tier that runs the same five FreeRTOS tests on the board and diffs
against the simulation results, so the config freeze has a hardware gate and not
only a simulation one.

The board is a physical, single-user resource, so this is a nightly or
pre-freeze gate rather than a per-commit one. Shape it as a Makefile target that
takes a host (`AMOEBA_BOARD=pynq.local`), rsyncs the artifacts, runs
`run_freertos.py` per test over SSH, and diffs three things per test: the tohost
code, the console text, and the retired count. Failing on the retired count is
the point — the other two can both pass while the core is quietly executing
something different.

## Phase 6 — commit trace

The RTL is written and synthesized. None of the software is.

**On the board**, `pynq.allocate()` for the capture buffer, then the S2MM
channel is three registers: write the buffer's physical address, write the
length, poll `DMASR` for completion. No scatter-gather, which is why the DMA was
configured without it — descriptors would otherwise have to live in the same DDR
the core uses in AXI builds.

**Decoding** is a 32-byte little-endian record: `pc`, `insn`, `rd_wdata`, `rd`,
`trap`, `priv`, and `seq`. Check `seq` for gaps before anything else — the
hardware is built so gaps cannot happen (`ExternalStall` backpressures the core
before the FIFO fills), so a gap means a bug in the DMA plumbing, not a dropped
record, and every comparison after it would be garbage.

**The reference model is where to be careful about sequencing.** The eventual
goal is a model on the PS, so long runs do not have to ship records off-board.
But the first version should not be that:

1. **Diff against the simulator.** Verilator already produces a commit log for
   the same image, the sim is already trusted, and this is a diff rather than a
   model. It needs no new correctness-critical code, and it is the fastest path
   to knowing whether the hardware executes what the simulator does.
2. **Then** put a model on the PS, once the record format, the DMA path and the
   windowing are all known-good and the only remaining problem is throughput.

Doing these in the other order means debugging a new model, a new DMA path and a
new record format simultaneously, with no known-good reference for any of them.

**Windowing is what makes this usable**, and is worth restating because the
instinct is to capture everything. A full Linux boot is ~217 M cycles at ~0.33
IPC, so roughly 70 M records — about 2.3 GB, and capture caps the core at about
one instruction per four cycles because each record is four 64-bit beats. The
workflow is: run once with the tap **off** (the retire and cycle counters run in
every mode and cost nothing) to find the retire count where behaviour diverges,
then run again with `TRIG_START` just before it and `TRIG_COUNT` around it. A
100 k-instruction window is 3.2 MB.

This depends on runs being reproducible, which is why the BRAM build stays
useful after DDR works: no refresh, no external interrupts, one clock, so the
same image retires the same instructions in the same order every time. Under
DDR that is no longer guaranteed.

## Phase 7 — Linux on DDR

`MEM_BACKEND=AXI` rebuilds the same design with the AHB leaving the PL for
`ahblite_axi_bridge` instead of block RAM. That path exists so cache-line fills
stay 8-beat bursts to the HP port; converting to `mem_itf` first flattens them
into eight single transfers, which costs almost nothing against 1-cycle block
RAM and roughly 7× against DDR latency.

Three things are needed beyond the rebuild:

- **A carve-out the PS kernel will not touch.** `reserved-memory` in the PS
  device tree, or `mem=` on its command line. Nothing in the PL can stop Linux
  from allocating at `0x1000_0000`, and the bridge's address window is clamped
  to the carve-out precisely so that a runaway core address errors instead of
  overwriting the PS kernel.
- **Images loaded into the carve-out** rather than the BRAM window:
  `fw_payload.bin` from `testcode/linux/build/baremetal_linux`, at the offset
  `EXT_MEM_BASE` maps to.
- **A longer patience budget.** The boot is 217 M cycles in simulation; at
  25 MHz with real DDR latency, expect tens of seconds rather than the
  simulator's minutes — this is the phase where the FPGA finally pays for
  itself.

The `timebase-frequency` in `dts/amoeba_baremetal_linux.dts` has the same
problem `configCPU_CLOCK_HZ` had: it describes FCLK, not the simulation's
100 MHz, and nothing currently keeps it in step with `FCLK_MHZ`.
