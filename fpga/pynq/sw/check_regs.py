#!/usr/bin/env python3
"""Assert that regs.py still matches the RTL and the block design.

The register offsets and base addresses are the only thing in this system with
no compile-time link between hardware and software: the RTL has localparams,
Python has integers, and nothing but this script notices when they diverge.  A
mismatch does not produce an error at runtime -- it produces a board that reads
plausible nonsense, which is a much worse afternoon.

Runs on the development machine, not the board.  Wire it into CI next to lint.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FPGA = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from amoeba import regs  # noqa: E402

CTL_SV = os.path.join(FPGA, "rtl", "amoeba_ctl.sv")
TRACE_SV = os.path.join(FPGA, "rtl", "amoeba_trace.sv")
BD_TCL = os.path.join(FPGA, "tcl", "bd_pynq.tcl")

fails = []


def check(what, got, want):
    if got != want:
        fails.append(f"{what}: regs.py has {got}, RTL has {want}")


# ---- register offsets, from amoeba_ctl.sv -----------------------------------
src = open(CTL_SV).read()
rtl_offsets = {
    m.group(1): int(m.group(2), 16)
    for m in re.finditer(r"localparam\s+logic\s+\[7:0\]\s+(R_\w+)\s*=\s*8'h([0-9A-Fa-f]+)", src)
}
if not rtl_offsets:
    fails.append(f"parsed no R_* localparams out of {CTL_SV} -- has it been restructured?")

for name, want in sorted(rtl_offsets.items()):
    got = getattr(regs, name, None)
    if got is None:
        fails.append(f"{name}: present in RTL at 0x{want:02x}, missing from regs.py")
    else:
        check(name, f"0x{got:02x}", f"0x{want:02x}")

for name in dir(regs):
    if name.startswith("R_") and name not in rtl_offsets:
        fails.append(f"{name}: in regs.py but not in {os.path.basename(CTL_SV)}")

# ---- ID magic ---------------------------------------------------------------
m = re.search(r"ID_MAGIC\s*=\s*32'h([0-9A-Fa-f_]+)", src)
if m:
    check("ID_MAGIC", hex(regs.ID_MAGIC), hex(int(m.group(1).replace("_", ""), 16)))
else:
    fails.append("could not find ID_MAGIC in the RTL")

# ---- trace mode encodings, from amoeba_trace.sv -----------------------------
tsrc = open(TRACE_SV).read()
for pyname, rtlname in (("TRACE_OFF", "MODE_OFF"), ("TRACE_ALL", "MODE_ALL"),
                        ("TRACE_WINDOW", "MODE_WINDOW"),
                        ("TRACE_PC_TRIG", "MODE_PC_TRIG")):
    m = re.search(rf"localparam\s+logic\s+\[1:0\]\s+{rtlname}\s*=\s*2'b([01]{{2}})", tsrc)
    if m:
        check(pyname, getattr(regs, pyname), int(m.group(1), 2))
    else:
        fails.append(f"could not find {rtlname} in the RTL")

# ---- base addresses, from bd_pynq.tcl ---------------------------------------
tcl = open(BD_TCL).read()
for pyname, key in (("CTL_BASE", "ctl_base"), ("MEM_BASE", "mem_base"),
                    ("DMA_BASE", "dma_base")):
    m = re.search(rf"^\s*{key}\s+(0x[0-9A-Fa-f]+)", tcl, re.M)
    if m:
        check(pyname, hex(getattr(regs, pyname)), hex(int(m.group(1), 16)))
    else:
        fails.append(f"could not find {key} in {os.path.basename(BD_TCL)}")

# ---- report -----------------------------------------------------------------
if fails:
    print("register map MISMATCH:\n")
    for f in fails:
        print(f"  {f}")
    print(f"\n{len(fails)} problem(s).  Fix regs.py, or the RTL, before running "
          "anything on hardware.")
    sys.exit(1)

print(f"register map OK: {len(rtl_offsets)} offsets, 4 trace modes, "
      "3 base addresses, ID magic")
