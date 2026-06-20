# FORTE

**ECE 427 Tapeout – Secure Linux Processor**

---

## Overview

FORTE is the ECE 427 tapeout project: a secure Linux-capable processor designed for research and educational purposes.

---

## Lint

Run lint checks:

```bash
cd lint
make lint
```

---

## Simulation (VCS / Verdi / Verilator)

Build the testbench:

```bash
cd sim
make vcs/top_tb
```

Run the simulation:

```bash
make run_vcs_top_tb PROG=../testcode/cp1_example.s
```

Open the waveform viewer:

```bash
make verdi &
```

Verilator: Lint

```bash
make run_verilator_lint
```

Verilator: Run

```bash
make run_verilator_top_tb PROG={your program}
```

---

## Synthesis

Run synthesis:

```bash
cd synth
make synth
```

---

## Spike (Standalone)

Run an ELF binary using Spike:

```bash
make spike ELF=PATH_TO_ELF
```

### Interactive Mode

Launch Spike in interactive mode:

```bash
make interactive_spike ELF=PATH_TO_ELF
```

