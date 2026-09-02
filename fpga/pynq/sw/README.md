# PS-side driver

Runs on the Cortex-A9, under PYNQ v3.1 or any Zynq Linux with `/dev/mem`.
Needs root, and no Python packages — `pynq` is imported only to download a
bitstream, and only if you ask for one.

```
amoeba/regs.py     register offsets, bit fields, base addresses
amoeba/mmio.py     /dev/mem word access
amoeba/image.py    ELF64 -> load segments, and the tohost symbol
amoeba/device.py   the Amoeba class
check_regs.py      asserts regs.py still matches the RTL  (dev machine)
run_freertos.py    load, run, stream the console, exit with the HTIF code
```

## Getting the files onto the board

**The SD card is not optional.** The PYNQ-Z2 has no storage of its own large
enough for a Linux root filesystem, so the PS boots from SD every time: the FAT
partition carries `BOOT.BIN` (FSBL + u-boot) and the kernel, and the ext4
partition is the rootfs. Flash the PYNQ v3.1 image to a card, leave it in the
board, and never take it out again.

What follows is about **transport** — how your bitstream, driver and program
images reach the card once the board is running. Three ways, in descending order
of how pleasant the edit-run loop is.

### 1. `deploy.sh` — rsync over SSH (recommended)

```bash
make -C fpga/pynq bitstream                       # once
make -C testcode/freertos bin TARGET=pynq \
     PROG=$PWD/testcode/freertos/heartbeat_app.c
./fpga/pynq/sw/deploy.sh xilinx@192.168.2.99 \
     testcode/freertos/freertos_wally.elf
```

`192.168.2.99` is what a PYNQ-Z2 self-assigns on a direct Ethernet link to a
laptop; login `xilinx` / `xilinx`. Everything lands in `~/amoeba` on the board,
and the notebook is symlinked into the Jupyter tree.

Re-running it after an edit takes a second, which is the whole point.

### 2. Jupyter, in the browser

`http://192.168.2.99:9090` (password `xilinx`), then `amoeba/amoeba_demo.ipynb`.
Check the port against your image — PYNQ has served Jupyter on both 9090 and 80
across releases.

**PYNQ's Jupyter kernel runs as root**, so `/dev/mem` works from a notebook with
no `sudo`. That is the main reason a notebook is nicer for interactive poking.
You can also drag files into the Jupyter file browser, which writes them into
`~/jupyter_notebooks` — fine for one file, tedious as a loop.

### 3. Pulling the card and mounting it on your laptop

Works, and is the worst option. The rootfs partition is ext4, so you need Linux
to write into `/home/xilinx`, and every iteration costs a power-down, a card
swap, a mount, a swap back and a boot. Use it to recover a board you cannot
reach over the network, not as a workflow.

## Programming the PL, and the clock that goes with it

`amoeba/pl.py` does both, because doing only the first is a silent failure.

**Programming.** It uses `pynq.Bitstream` when `pynq` imports, and the kernel's
`fpga_manager` when it does not. The fallback needs no packages: it strips the
Xilinx `.bit` header, byte-swaps every 32-bit word (the PCAP DMA reads
little-endian words; the configuration stream is defined big-endian, so the sync
word `AA 99 55 66` has to become `66 55 99 AA`), drops the result in
`/lib/firmware`, and writes the name to `/sys/class/fpga_manager/fpga0/firmware`.

That fallback exists because of a specific trap: **on PYNQ v3.x, `pynq` lives in
a venv, so `sudo python3` cannot import it.** If you want the pynq path, use

```bash
sudo /usr/local/share/pynq-venv/bin/python3 run_freertos.py ...
```

but you no longer have to — plain `sudo python3` now works.

**The clock.** The block design asks for FCLK_CLK0 = 25 MHz and the `.hwh`
records it, but nothing programs it at runtime unless you go through
`pynq.Overlay`, which reads that field. We use `Bitstream` on purpose (see
below), and the cost of that choice is that FCLK0 stays wherever the PYNQ boot
default left it — usually **100 MHz, against a design that closed timing at
25.5**. The PL configures, the registers read back, and the core produces
garbage. So `pl.program()` sets FCLK0 from the SLCR every time.

Then it is checked, by measurement rather than readback:

```
# fabric clock verified: 25.000 MHz
```

`Amoeba.check_fclk()` counts PL cycles against host wall time and refuses to run
if the answer is more than 5% off. Reading the SLCR back would prove only that
the write landed; counting real cycles is the only claim that does not depend on
`pl.py`'s own divider arithmetic being right. `--fclk 0` turns both off.

## You do not need the `.hwh` for this part

The driver addresses the control block at a fixed address out of `regs.py`
rather than discovering it from the overlay, and uses `pynq.Bitstream` rather
than `pynq.Overlay`. So a `.hwh` that PYNQ cannot parse — the classic
Vivado-version-skew failure — does not block FreeRTOS bring-up. It matters later,
for the trace DMA, which does want `pynq.lib.dma`.

## The two commands

On the board, over SSH:

```bash
cd ~/amoeba/sw

# soak: heartbeat, liveness, clock calibration
sudo python3 run_freertos.py --bitstream ../amoeba.bit \
     --image ../images/freertos_wally.elf --soak 30

# regression: run to completion, exit with the program's code
sudo python3 run_freertos.py --image ../images/tc_semaphore.elf --expect-exit 0
```

`sudo` is needed over SSH (`/dev/mem`) but not in a notebook, where the kernel
already runs as root.

## What a good soak run looks like

```
# amoeba v0.1.0  mem=128 KiB  backend=BRAM  trace=yes
# image heartbeat.elf: 0x80000000..0x80012ae8, 10136 bytes to load, entry 0x80000000
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

Four independent things have to be true for that, which is why it is the first
thing to run:

- the bitstream loaded and the register map is right — `ID` read `AMOB`
- the core is clocked and out of reset — `cycles` advanced
- it is executing correctly — `retired` advanced, `traps` is 0, and the console
  text is well-formed rather than garbage
- the timer is calibrated — beats land on 100 ms

## The clock checks, and why there are two

They answer different questions and the distinction is easy to get wrong.

**Calibration** compares the measured beat period against the period the guest
*intended*. The guest schedules `configCPU_CLOCK_HZ × 0.1` mtime increments per
beat and mtime advances once per fabric clock, so beats arrive late by exactly
`configCPU_CLOCK_HZ / FCLK`. A 4× wrong constant gives 400 ms beats. This is the
only check in the whole test suite that can catch it: every terminating test
verifies ordering and results, not rates, and passes just as happily on a wrong
clock.

**Cross-check** compares two independent estimates of the fabric clock — one
from the guest's timer, one from the PL's free-running counter against host wall
time. These agree whether or not `configCPU_CLOCK_HZ` is right, so this is *not*
a calibration check; it verifies that mtime and the PL counter are counting the
same clock, which they are both supposed to be.

Getting these confused produces a check that looks thorough and silently passes
a 4× error, which is what the first version of this file did.

## Register drift

`regs.py` has no compile-time link to the RTL. `check_regs.py` parses
`amoeba_ctl.sv`, `amoeba_trace.sv` and `bd_pynq.tcl` and asserts they agree:

```bash
python3 check_regs.py
# register map OK: 21 offsets, 4 trace modes, 3 base addresses, ID magic
```

Run it on the development machine whenever the RTL changes. A mismatch does not
produce an error at runtime; it produces a board that reads plausible nonsense.

## Load-time checks

`Amoeba.load()` refuses three things rather than letting them become confusing
failures later:

- **loading while the core runs.** The two block RAM ports are not arbitrated —
  they are never meant to be live at once — so this corrupts memory silently.
- **an image that does not fit.** `amoeba_mem_bram` truncates rather than
  faulting, so an over-large image wraps onto its own reset vector.
- **a `tohost` mismatch.** The ELF's `tohost` symbol is compared against the
  address the bus monitor watches. If they differ the run would print correct
  console output and then hang forever waiting for an exit nobody saw — so this
  is checked before the core ever starts.

It also zeroes memory before loading. Block RAM comes up zeroed in the
bitstream, so the first run after programming is clean; the second starts on the
first run's memory.

## On timeout

`run_freertos.py` walks the diagnostic ladder automatically rather than just
reporting a timeout:

| reading | conclusion |
|---|---|
| `cycles` = 0 | not clocked, or reset never released |
| `cycles` > 0, `retired` = 0 | fetching but nothing commits — image or reset vector |
| `retired` > 0, `traps` > 0 | trapping in a loop |
| all advanced, no tohost | ran fine but the exit was never seen — check the tohost address |
