# PL design and its semantics

This is the contract between the soft core in the fabric and the Cortex-A9 that
drives it. The RTL in [rtl/](rtl/) implements it; the PS-side tooling in `sw/`
(not written yet) consumes it.

## The organizing rule

**The PS owns the core's reset, and it comes out of configuration asserted.**

Everything else follows. After the bitstream loads, the core is halted and
fetching nothing, so the PS can load the image, arm a trigger and clear the
monitors in a quiescent design. There is no bootloader in the fabric, no
self-starting sequence, and no register whose write races the core — anything
that would race is written while the core is held.

The bring-up sequence is the same for every image:

1. load the image — the BRAM window over GP0, or the DDR carve-out
2. configure the trace — mode and triggers
3. clear the monitors — `CTRL.MON_CLEAR | CTRL.TRACE_CLEAR`
4. release `CTRL.CORE_RESET`
5. poll `UART_DATA` for the console, `STATUS` for tohost, drain the DMA

## Block diagram

```
   PS                                   PL
   ──────────────────────────────       ─────────────────────────────────────
                                        ┌─────────────────────────────────┐
   GP0 ──── AXI4-Lite ─────────────────▶│ amoeba_ctl                      │
                                        │  reset, triggers, counters,     │
                                        │  console FIFO, tohost           │
                                        └─────────────────────────────────┘
                                        ┌─────────────────────────────────┐
                                        │ amoeba_soc_wrapper  (the DUT)   │
                                        │  wallypipelinedcore  ← tapeout  │
                                        │  adrdecs / ahbapbbridge         │
                                        │  clint_apb / uart_apb           │
                                        └───┬──────────────────────┬──────┘
                                         AHB│                      │taps (XMR)
                                            ├──▶ amoeba_bus_mon ───┼──▶ console
                                            │                      │    tohost
   GP0 ──── AXI4-Lite ──────────────────────┤ amoeba_mem_bram      │
                                            │  (BRAM builds)       ▼
   HP0 ◀─── ahblite_axi_bridge ─────────────┘ (AXI builds)   amoeba_trace
   HP0 ◀─── AXI DMA S2MM ◀──── AXI4-Stream ───────────────────────┘
                                                     ExternalStall ┘
```

One clock: `aclk` is `FCLK_CLK0`, and the core, the AXI-Lite block, the
monitors, the trace FIFO and both PS-facing AXI interfaces all run on it. There
is no clock-domain crossing anywhere in this design, and it is worth keeping
that true.

## Three address spaces, kept distinct

| name | seen by | contents |
|---|---|---|
| **core PA** | the RV64 core | CLINT `0x0200_0000`, UART `0x1000_0000`, EXT_MEM `0x8000_0000`–`0x8FFF_FFFF` |
| **PL map** | the PS as a master | `amoeba_ctl` (4 KiB), the image window, the DMA |
| **PS PA** | Linux on the A9 | GP0 slaves at `0x4000_0000`+, DDR at `0x0000_0000` |

`EXT_MEM_BASE` is `0x8000_0000` in every config, so the AXI build's bridge
subtracts it and adds the DDR carve-out base. The BRAM build truncates to the
array size instead — an access past `MEM_KB` aliases rather than faulting. The
AHB decoder upstream has already limited the access to `EXT_MEM_RANGE` (256 MB),
so anything past the array is a software sizing mistake, and a wrapped write is
loud enough to find.

## The two memory backends

`MEM_BRAM` is the *only* difference between the FreeRTOS bring-up bitstream and
the Linux bitstream. Keeping it a parameter rather than a fork means a bug found
in one is fixed in both.

**`MEM_BRAM = 1`** — `ahb_to_memitf` (the same adapter the Verilator tier uses,
so it is not FPGA-only code that can rot) against a true dual-port block RAM.
Port B is an AXI4-Lite slave, which is how the image gets loaded without a
bootloader in the fabric. `ahb_to_memitf` returns to `S_IDLE` between beats, so
an 8-beat cache-line fill becomes eight single transfers; against a 1-cycle
block RAM that costs almost nothing, which is exactly why it is fine here and
not fine against DDR.

Port B is AXI rather than a raw block RAM interface deliberately. Exposing
`bram_en`/`bram_we`/`bram_addr` for an AXI BRAM Controller is the more obvious
design and the more fragile one: IPI's interface inference on an RTL module is
name-heuristic and produces loose pins when it misses. `s_axi_*` is the single
most reliable inference IPI does, and it removes a whole IP from the block
design.

**`MEM_BRAM = 0`** — the AHB leaves the top for Xilinx's `ahblite_axi_bridge` in
the block design, so bursts survive to the HP port. Converting to `mem_itf`
first would flatten them, at roughly 7× against DDR latency.

Keep the BRAM build after DDR works: it is the deterministic one. DDR refresh
jitters interrupt arrival, so a failing DDR run is not necessarily reproducible
— and reproducibility is what the trace windows below depend on.

### The two ports are not arbitrated

They are never both live: the PS writes the image while the core is held, then
releases it. A PS write while the core is running is a software bug and will
corrupt memory rather than being detected.

### FreeRTOS needs its own linker script for this target

`testcode/freertos/freertos_wally.ld` declares 128 MB of RAM, puts the IRQ stack
at `RAM_BASE + 128 MB` and `tohost` at `RAM_BASE + 8 MB`. Both are outside
anything block RAM can hold. The image itself is fine — 10 KiB of text+data and
70 KiB of bss, heap and stacks, about 79 KiB total — so a `freertos_pynq.ld`
with `LENGTH = 128K` (the `MEM_KB` default), the stack top inside it, and
`tohost` near the top of it is all that is needed. Exit detection then works exactly as it does in
simulation: the write reaches the bus as a cache-line writeback, and
`amoeba_bus_mon` snoops the beat carrying that doubleword.

## Console

Snooped off the AHB, not off the serial pin.

**Why the AHB and not the memory port.** `wallypipelinedsoc` drives `HADDR` /
`HWDATA` / `HWRITE` / `HTRANS` as the *shared* bus for every slave, the internal
CLINT and UART included; `HSELEXT` only says whether external memory is the
target. A snoop at the top sees the UART traffic. A snoop downstream of
`HSELEXT` would not.

**Why the UART peripheral still exists.** The snoop is passive — it observes the
write and does not answer it. `uart_apb` stays instantiated so LSR/THRE still
report the transmitter empty; without it the 8250 driver's `wait_for_xmitr()`
spins forever on the first character and the console never starts. Snooping is
a faster tap on a working UART, not a replacement for one.

**There are no serial pins, and the design has no PL I/O at all.** A physical
console would be redundant with the snoop, and worse, it would not work without
per-clock retuning: the 16550's divisor is programmed by the guest against
PCLK, which is FCLK_CLK0 here — 25 MHz on the board against the 100 MHz the
simulation assumes — so every divisor the FreeRTOS and Linux drivers write is
off by 4x. Retuning it would test PL scaffolding, since the tapeout boundary is
`wallypipelinedcore` one level down. The peripheral stays fully alive either
way: LSR is read over APB into the core, which preserves the TX state machine
and baud generator whether or not `SOUT` reaches a pin.

If a genuine snoop-vs-serial equivalence check is ever wanted, the cheap form is
a PL-side deserializer rather than pins. `amoeba_bus_mon` already shadows
`LCR[7]` for DLAB, so it can capture the `DLL`/`DLM` writes at the same time and
configure a receiver to whatever divisor the guest chose — no manual tuning, no
dependence on what FCLK ended up being.

**The DLAB trap.** Offset 0 of a 16550 is the transmit register only while
`LCR[7]` (DLAB) is clear; with DLAB set it is the low byte of the baud divisor.
The Linux 8250 driver opens with `LCR=0x83`, `DLL`, `DLM`, `LCR=0x03` — so a
monitor that takes every write to offset 0 emits the divisor bytes as console
characters at every port open. Shadowing `LCR[7]` costs one flop and removes a
class of "the log has garbage in it" that is otherwise very hard to place.

**Byte lanes are a non-problem.** `hdl/core/lsu/subwordwrite.sv` replicates a
byte store across all eight lanes of a 64-bit `HWDATA`, which is exactly why
`uart_apb` can wire `Din = PWDATA[7:0]` regardless of the register offset.
`HWDATA[7:0]` is the console byte no matter which offset was addressed.

**AHB timing.** `HREADY` high at a clock edge both completes the current data
phase and accepts the address on the bus. Each ready edge therefore does two
things in order: consume the write data belonging to the address latched last
time, then latch the new address. `HWDATA` is only meaningful in the first step.

## Commit trace

The point is to step a reference model on the A9 alongside the core. Two
properties make that work, and both are design decisions rather than
conveniences.

### It is windowed, because tracing everything is not a thing you can do

A record per retired instruction is roughly **5 GB** for the Linux boot the core
already completes in simulation. The stream is four 64-bit beats per 32-byte
record against a core that can retire one instruction per cycle, so capture caps
the core at about **one instruction every four cycles**.

So the workflow is two passes:

1. run with `TRACE_MODE = OFF`. The retire, trap and cycle counters still run —
   they are about 100 flops and they cost nothing — so you get the retire count
   at which behaviour diverges.
2. run again with a window around it.

| mode | behaviour |
|---|---|
| `OFF` (0) | counters only; `ExternalStall` never asserted; core at full speed |
| `ALL` (1) | capture from reset release; for short programs |
| `WINDOW` (2) | capture once `retired >= TRIG_START`, for `TRIG_COUNT` records |
| `PC_TRIG` (3) | arm on the first retire at `TRIG_PC`, then as `WINDOW` |

`TRIG_COUNT = 0` means unlimited.

### It is lossless, and it proves it

Every record carries `seq`, the retire counter, so the PS can prove it received
a contiguous run rather than silently comparing a stream with holes in it.
Holes are *prevented* rather than detected: past the FIFO high-water mark,
`ExternalStall` goes high and the core stops retiring until the DMA catches up.
`ExternalStall` folds into `StallWCause` in `hdl/core/hazard/hazard.sv` and is
tied low everywhere else in this project.

This is a lighter hand than CVW's own `packetizer.sv`, which holds `RVVIStall`
for the whole of each 92-byte Ethernet frame and so runs the core at roughly one
instruction per 25 cycles whether or not anything is congested. Here the core
only pays when the FIFO is genuinely backing up.

### Record layout — 32 bytes, little-endian

| bits | field |
|---|---|
| `63:0` | `pc` |
| `95:64` | `insn` — compressed forms zero-extended from 16 bits |
| `159:96` | `rd_wdata` — 0 when no register was written |
| `164:160` | `rd` — 0 when no register was written |
| `165` | `trap` |
| `167:166` | `priv` at writeback |
| `191:168` | reserved, zero |
| `255:192` | `seq` |

32 bytes is a power of two so the PS-side indexing is a shift. `TLAST` closes a
packet every `PKT_RECORDS` (256 → 8 KiB) so the DMA retires descriptors at a
predictable size, and also on the final record of a bounded capture so the tail
does not sit unflushed.

Dropping `rd_wdata` would halve the record and halve the stall, at the cost of
only catching control-flow divergence. It is not worth it while capture is
windowed.

### The taps are hierarchical references, on purpose

`amoeba_soc_wrapper` stays byte-identical to what the utilization gate measures
and to what goes to the ASIC — no debug ports are cut into it. `amoeba_pynq_top`
reads the commit signals out of the SoC instance by downward reference, which is
what CVW's own `third_party/cvw/fpga/src/fpgaTopArtyA7.sv` does to feed
`rvvisynth`; Vivado synthesizes read-only cross-module references. They are
reads only — nothing outside the DUT drives anything inside it except
`ExternalStall`, which is a real port.

The tap paths are the same ones `hdl/rv64_core_wrapper.sv` already uses for its
RVFI monitor, so the FPGA trace and the simulation monitor observe the same
nets. A divergence between them is a real difference, not two definitions of
"retired".

## Register map — `amoeba_ctl`, AXI4-Lite, 4 KiB

| offset | name | access | contents |
|---|---|---|---|
| `0x00` | `ID` | RO | `0x414D4F42` (`"AMOB"`) — proves the bitstream loaded |
| `0x04` | `VERSION` | RO | |
| `0x08` | `CAPS` | RO | `[31:16]` MEM_KB, `[8]` trace present, `[0]` 1 = BRAM |
| `0x0C` | `CTRL` | RW | `[0]` CORE_RESET (**resets to 1**), `[1]` MON_CLEAR, `[2]` TRACE_CLEAR |
| `0x10` | `STATUS` | RO | `[0]` core in reset, `[1]` uart valid, `[2]` uart overflow, `[3]` tohost valid, `[4]` trace overflow, `[5]` core stalled by trace |
| `0x14` | `UART_DATA` | RO | `[8]` valid, `[7:0]` byte — **reading pops** |
| `0x18` | `UART_LEVEL` | RO | |
| `0x20`/`0x24` | `CYCLES_LO/HI` | RO | cycles since reset release |
| `0x28`/`0x2C` | `RETIRED_LO/HI` | RO | |
| `0x30` | `TRAPS` | RO | |
| `0x34`/`0x38` | `TOHOST_LO/HI` | RO | |
| `0x40` | `TRACE_MODE` | RW | `[1:0]` |
| `0x44`/`0x48` | `TRIG_START_LO/HI` | RW | |
| `0x4C` | `TRIG_COUNT` | RW | 0 = unlimited |
| `0x50`/`0x54` | `TRIG_PC_LO/HI` | RW | |
| `0x58` | `TRACE_STAT` | RO | `[15:0]` FIFO level, `[17:16]` state |

**64-bit reads.** AXI-Lite is 32 bits, so a 64-bit counter takes two reads, and
a carry landing between them yields a value that never existed. Reading a `_LO`
register latches the matching high half into a shadow, and the `_HI` read
returns the shadow. **Read LO first, always** — reading HI alone returns
whatever the last LO read froze. Each counter has its own shadow, so interleaved
reads cannot alias.

**This block never errors.** Unmapped writes are dropped and unmapped reads
return `0xDEADC0DE`. A hung AXI transaction on a debug block is worse than a
wrong value, because it takes the PS down with it.

**Overflows are sticky and are failures, not hiccups.** A dropped console byte
corrupts the log silently; a dropped trace record breaks the `seq` contract the
PS-side checker relies on. The trace path avoids overflow entirely by stalling
the core off the FIFO level well before full — if `trace overflow` ever sets,
the high-water mark is wrong.

## PS address map

Fixed in [tcl/bd_pynq.tcl](tcl/bd_pynq.tcl), not left to Vivado's auto-assigner,
so the PS-side software has constants rather than whatever a given run picked.

| PS address | size | what |
|---|---|---|
| `0x4000_0000` | 64 KiB | AXI DMA control (`dma_trace/S_AXI_LITE`) — at `0x4040_0000` |
| `0x43C0_0000` | 4 KiB | `amoeba_ctl` — the register map above |
| `0x4400_0000` | `MEM_KB` | image window, BRAM builds only |
| `0x1000_0000` | 256 MiB | DDR carve-out: the DMA's target, and the core's memory in AXI builds |

Ranges matter as much as offsets. The image window is a 32-bit AXI-Lite slave,
so left alone the auto-assigner claims 512 MB of the PS map for a 128 KiB block
RAM. The DDR windows are clamped for a sharper reason: at the full 512 MB a
runaway core address in an AXI build overwrites the PS kernel instead of
erroring, which presents as the board hanging at random.

The carve-out has to be reserved on the PS side too — a `memreserve`/
`reserved-memory` node, or `mem=256M` on the PS kernel command line. Nothing in
the PL can stop Linux from allocating there.

## Building

```bash
source ~/Xilinx/Vivado/2024.1/settings64.sh
make -C fpga/pynq bd          # block design only -- minutes
make -C fpga/pynq synth-bd    # through synthesis
make -C fpga/pynq bitstream   # .bit + .hwh
```

`bd` exists because the block design is the part of this flow that breaks, and
finding that out an hour into synthesis is a bad trade. Every mistake so far —
missing headers, the SystemVerilog module-reference restriction, wrong address
ranges — surfaced there in under a minute.

`BOARD=none` skips the PS7 preset. It validates that the module references
elaborate, the interfaces infer and the addresses assign, which is where
essentially every bug lives, and it needs no board files. It cannot produce a
working bitstream and `build.tcl` refuses to try: the preset is what sets the
DDR part, its timing and the MIO map, and a design built without it synthesizes
fine and then cannot bring memory up.

The PYNQ-Z2 board files do not ship with Vivado. Install them through
**Tools > Vivado Store > Boards**, or unpack them anywhere and point the build
at them with `BOARD_REPO=/path/to/board_files`.

### Two Vivado details that cost time

**IPI will not take a SystemVerilog file as a module reference's top.**

```
ERROR: [filemgmt 56-195] Reference 'amoeba_pynq_top' contains top file
'.../amoeba_pynq_top.sv' of type SystemVerilog.  This type is not allowed
as the top file in the reference.
```

Everything *below* it may be SystemVerilog, and all of it is. Hence
[rtl/amoeba_pynq_top_v.v](rtl/amoeba_pynq_top_v.v), a pure pass-through shim
with no logic. It also forced `MEM_BACKEND` from a `string` parameter to a
`bit`, since a SystemVerilog string parameter taking a Verilog string literal is
not something to rely on.

**Header files must be *in* the project, not merely on the include path.**
Synthesis is happy with `-include_dirs` alone; IPI's module-reference
elaboration is not, and says so as `[filemgmt 56-591] Given include File '...'
needs to be addded to the project`, which reads like a missing file rather than
a missing `add_files`.

## What is not built yet

- `sw/` — the PS-side library against the register map above, and the reference
  model the trace feeds
- `testcode/freertos/freertos_pynq.ld` — see above
- A `reserved-memory` node or `mem=` argument for the PS kernel, so Linux does
  not allocate inside the carve-out
