# PYNQ-Z2 FPGA build

Target: **Zynq XC7Z020-1CLG400** — 53,200 LUT6, 106,400 FF, 140 BRAM36
(630 KiB), 220 DSP48E1. Dual Cortex-A9 PS with 512 MB DDR3 attached to the
**PS**, not the fabric.

This directory holds the **utilization gate** and the **PL design**. The gate
came first because its answer decides the cache geometry, and the cache geometry
is a tapeout parameter.

[DESIGN.md](DESIGN.md) is the contract between the soft core and the PS: reset
ownership, the memory backends, how the console is snooped, what a trace record
contains, and the register map. Read it before touching `rtl/`. The block
design, the constraints and the PS-side software are still to be written; the
last section of DESIGN.md lists them.

## Why this gate exists

Every LUT figure in the plan is an estimate derived from what each config
elaborates. That is enough to rule out RV64GC and to be confident about the
pruned configs, but it is not enough to decide how much of the budget is free —
and that is the open question blocking the tapeout config freeze:

> `DCACHE_NUMWAYS = 1`, `DCACHE_WAYSIZEINBYTES = 512` were chosen to minimise
> area in a Verilator experiment. They cost **1.57× on a Linux boot**
> (556.3 M cycles against ~353.5 M on the full config, with 488 M of them in the
> single M3→M4 phase). Whether to spend LUTs on the cache depends on how many
> are left, which is what this measures.

## Toolchain

**Vivado 2024.1**, Linux, self-extracting unified installer (`.bin`).

Two constraints pin this, and both are easy to get wrong:

- **Not 2026.1.** From the 2026.1 release AMD moved to tiered licensing and the
  free tier became **Windows-only**. 2025.2 is the last release with a free tier
  that runs on Linux. 7-series and Zynq-7000 are still in the free tier as
  *devices* — it is the host OS that was cut.
- **2024.1 specifically, to match PYNQ v3.1**, whose overlays and PetaLinux are
  both built with 2024.1. The `.hwh` hardware-handoff file that PYNQ parses to
  discover the address map is version-sensitive, and skew between the Vivado
  that wrote it and the PYNQ that reads it is a well-known failure mode. It
  lands exactly where this project spends its time.

If you decide to skip the PYNQ framework and drive the core from plain
`/dev/mem` with a `reserved-memory` device-tree carve-out, take **2025.2**
instead — newest free-on-Linux, and the `.hwh` question disappears. Either
version runs the gate identically.

### Installing on Ubuntu 24.04

24.04 postdates 2024.1 and is not on its supported-OS list. It runs, but
`librdi_commontasks.so` links against `libtinfo.so.5`, which Noble dropped.

**This one hides.** `vivado -version` does not load that library, so the tool
reports its version happily and looks installed. The failure appears only on the
first batch run, as:

```
application-specific initialization failed: couldn't load file
"librdi_commontasks.so": libtinfo.so.5: cannot open shared object file
```

`make utilization` handles it: when the real `libtinfo.so.5` is absent it builds
a `libtinfo.so.6` symlink under `build/tinfo-shim` and puts that on
`LD_LIBRARY_PATH` for the run. No root, nothing touched outside `build/`, and
the ABI is close enough for what Vivado uses. Set `AMOEBA_NO_TINFO_SHIM=1` to
opt out if you would rather install the real library from the jammy pool:

```bash
wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
sudo dpkg -i libtinfo5_*.deb   # check the pool for the current point revision
```

The usual X and build dependencies are worth having either way:

```bash
sudo apt install libncurses5 libx11-6 libxext6 libxrender1 libxtst6 libxi6 build-essential
```

**Deselect device families during install.** The default unified install is well
over 100 GB. This project needs only Zynq-7000 / 7-series and no Vitis, which
brings it down to roughly 30–60 GB. The `.bin` also extracts to a temp directory
before installing, so budget headroom beyond the install target itself.

Then source it before running the gate:

```bash
source ~/Xilinx/Vivado/2024.1/settings64.sh   # or wherever you installed it
```

`make utilization` checks for this and tells you if it is missing rather than
failing three lines into a recipe.


## Running it

```bash
make lint                       # elaboration check, needs only Verilator
make dryrun                     # exercise the Vivado TCL with commands stubbed
make utilization                # the gate -- needs Vivado
make utilization-all            # every config, side by side
```

`CONFIG=` takes the same names as `sim/Makefile`, `synth/Makefile` and
`testcode/linux/Makefile`. It defaults to `baremetal_linux`, the tapeout config.

```bash
make utilization CONFIG=baremetal_linux     # the one that matters
make utilization CONFIG=freertos            # what the pruning bought
make utilization CONFIG=                    # full pkg/config.vh, for the record
make utilization FCLK_MHZ=40                # push the clock and read the WNS
```

Vivado ML Standard covers the XC7Z020 at no cost. The gate needs **no board, no
bitstream and no block design** — out-of-context synthesis means no I/O buffers
are inserted and no board constraints are required, so the number describes the
design rather than the pin planning.

Expect roughly an hour per config.

## What you get

`reports/<config>/` holds `utilization.rpt`, `utilization_hier.rpt`,
`timing.rpt`, `timing_paths.rpt`, a `post_synth.dcp` checkpoint, and a
machine-readable `summary.txt`. `scripts/fit_report.sh` renders the last of
those into the table the gate exists to produce:

```
  XC7Z020 fit -- CONFIG=baremetal_linux   @ 25.0 MHz target
  --------------------------------------------------------
  LUT6           28000 / 53200       52.6%
  FF             31000 / 106400      29.1%
  DSP48             18 / 220          8.2%
  BRAM36            24 / 140         17.1%
  --------------------------------------------------------
  WNS            1.100 ns   -> Fmax 25.7 MHz
  verdict    FITS
```

**Post-synthesis numbers are estimates.** Placement can push LUT usage up as the
tool duplicates logic to meet timing, so anything above ~80% is reported as
`TIGHT` and means "run place-and-route before believing it." The
`post_synth.dcp` checkpoint exists so that follow-up run does not have to
re-synthesize.

On the clock: Wally's own Arty A7 build runs at **20 MHz** on the same -1 speed
grade 7-series fabric, so `FCLK_MHZ=25` is a starting point rather than a
target. Read the WNS and move. If the 64-bit divider is what holds you,
`IDIV_BITSPERCYCLE` from 4 to 2 is a one-line config change — though as a
tapeout parameter it deserves more thought than it would as an FPGA workaround.

## What is here

```
DESIGN.md                   the PL/PS contract -- read this first

rtl/amoeba_soc_wrapper.sv   the DUT: core + minimal uncore.  The gate's top,
                            and what goes to the ASIC.  No debug ports.
rtl/amoeba_pynq_top.sv      the whole PL: DUT + control + monitor + trace +
                            memory backend.  The bitstream's top.
rtl/amoeba_pynq_top_v.v     Verilog shim -- IPI refuses a SystemVerilog file as
                            a module reference's top.  No logic, just ports.
rtl/amoeba_ctl.sv           AXI4-Lite control and status -- the PS's entire view
rtl/amoeba_bus_mon.sv       AHB snoop: console bytes, tohost, cycle counter
rtl/amoeba_trace.sv         commit trace -> AXI4-Stream, and ExternalStall
rtl/amoeba_mem_bram.sv      block RAM backend, port B exposed for image load
rtl/amoeba_fifo.sv          the FIFO both of those use

tcl/bd_pynq.tcl             the block design: PS7, DMA, addresses
tcl/build.tcl               project -> block design -> bitstream + .hwh
constraints/pynq-z2.xdc     the two console pins (check them -- see the file)
tcl/synth_ooc.tcl           out-of-context synthesis + reports
scripts/fit_report.sh       summary.txt -> the fit table above
scripts/tcl_dryrun.tcl      stubs every Vivado command so the TCL can be
                            exercised in tclsh, in about a second
Makefile                    generates the filelist and drives all of it
```

`TOP=` selects what is elaborated, and both values are meaningful:

```bash
make utilization                          # amoeba_soc_wrapper -- the core alone
make utilization TOP=amoeba_pynq_top      # the whole PL -- the bitstream
```

Running both separates "what does the core cost" from "what does the debug
plumbing cost". They are different questions with different answers, and only
one of them goes to the ASIC. Reports land in `reports/<config>` and
`reports/<config>-amoeba_pynq_top` respectively.

For the bitstream itself:

```bash
make bd                     # block design only -- minutes, and where it breaks
make bd BOARD=none          # ... without needing the PYNQ-Z2 board files
make synth-bd               # through synthesis
make bitstream              # .bit + .hwh, into bit/<config>-<backend>/
```

See [DESIGN.md](DESIGN.md) for the PS address map and the board-file
requirement.

### Why not `hdl/rv64_core_wrapper.sv`

That wrapper exposes several hundred `monitor_*` ports so the testbench can
watch every retired instruction. At a pin boundary those ports are preserved by
synthesis, which keeps the entire RVFI tap pipeline alive and inflates the area
report with logic no bitstream would contain. `amoeba_soc_wrapper` instantiates
the same hardware with only the ports the FPGA actually drives. The two are
meant to stay separate.

### What is inside the wrapper

At `CONFIG=baremetal_linux`, `wallypipelinedsoc` elaborates to exactly:

| | |
|---|---|
| `wallypipelinedcore` | **the tapeout** |
| `adrdecs` | address decode; also drives `HSELEXT` |
| `ahbapbbridge` | 105 lines |
| `clint_apb` | **mandatory** — the core takes `MTimerInt`/`MSwInt`/`MTIME_CLINT` as *inputs* |
| `uart_apb` | the console |

PLIC, GPIO, SPI, SDC, BootROM and the uncore RAM are all `_SUPPORTED = 0` and
generate away. So instantiating the SoC costs nothing over hand-rolling the
scaffolding, and it is already exercised by every simulation tier — the tapeout
boundary is still `wallypipelinedcore`, one level down.

The AHB master leaves the wrapper unflattened on purpose. The bring-up bitstream
will feed it to `hdl/ahb_to_memitf.sv` and a block RAM; the production bitstream
hands it straight to Xilinx's `ahblite_axi_bridge` so 8-beat cache-line fills
stay bursts all the way to the HP port. Converting to the `mem_itf` protocol
first flattens them into eight single transfers — free against block RAM,
roughly 7× against DDR.

## No local substitute for the gate

`make lint` is the only part that runs without Vivado. There is deliberately no
local area estimate: Verilator is a simulator and reports node counts, not
flip-flops or LUTs, and yosys cannot read this SystemVerilog without `sv2v` —
and would map to its own primitives rather than Xilinx's, giving an answer
that is wrong in a way that looks right.

`make dryrun` is the next best thing. It runs `tcl/synth_ooc.tcl` in plain
`tclsh` with every Vivado command stubbed out, which catches typos, bad
`lassign` arity and malformed command construction in about a second instead of
an hour into a run on the one machine that has a licence. It proves the script
runs; it cannot prove Vivado likes the options.
