#!/usr/bin/python3
"""Summarise a Linux boot run: milestone cycle counts, phase costs and status.

The Linux-tier testbench prefixes every console line with the cycle it was
emitted on ("[UART @1234567] ..."), so a boot log is already a timing trace.
This turns it into a table.

    boot_report.py sim/verilator/linux_boot/simulation.log [--wall SECONDS]
"""

import argparse
import re
import sys

# Ordered boot milestones.  Each is (id, description, substring to match).
MILESTONES = [
    ("M0", "OpenSBI running",   "OpenSBI v1."),
    ("M1", "Kernel entered",    "Linux version 6.6"),
    ("M2", "Console handover",  "printk: bootconsole"),
    ("M3", "Memory map parsed", "Initmem setup node 0"),
    ("M4", "Init memory freed", "Freeing unused kernel image"),
    ("M5", "Userspace reached", "AMOEBA_LINUX_BOOT_OK"),
]

UART_RE = re.compile(r"\[UART @(\d+)\]\s?(.*)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--wall", type=float, default=None,
                    help="wall-clock seconds for the run, for a kHz figure")
    args = ap.parse_args()

    lines = []
    status = "NO RESULT"
    last_cycle = 0
    with open(args.log, errors="replace") as f:
        for raw in f:
            m = UART_RE.search(raw)
            if m:
                cyc = int(m.group(1))
                last_cycle = max(last_cycle, cyc)
                lines.append((cyc, m.group(2).rstrip()))
            if "test PASSED" in raw:
                status = "PASS"
            elif "test FAILED" in raw or "Timed out" in raw:
                status = "FAIL"
            elif "RVFI Monitor Error" in raw:
                status = "FAIL (RVFI)"

    print(f"status          : {status}")
    print(f"console lines   : {len(lines)}")
    print(f"cycles observed : {last_cycle:,}")
    if args.wall:
        print(f"wall clock      : {args.wall:,.0f} s "
              f"({last_cycle / args.wall / 1000:.1f} kHz)")
    print()

    hdr = f"{'':<5} {'milestone':<24} {'cycle':>14} {'delta':>14}"
    if args.wall and last_cycle:
        hdr += f" {'wall':>9}"
    print(hdr)
    print("-" * len(hdr))

    found, missing = [], []
    for mid, desc, needle in MILESTONES:
        hit = next((c for c, t in lines if needle in t), None)
        (missing if hit is None else found).append((mid, desc, hit))
    found.sort(key=lambda r: r[2])

    prev = 0
    for mid, desc, hit in found:
        row = f"{mid:<5} {desc:<24} {hit:>14,} {hit - prev:>14,}"
        if args.wall and last_cycle:
            row += f" {hit / last_cycle * args.wall:>8.0f}s"
        print(row)
        prev = hit
    for mid, desc, _ in missing:
        print(f"{mid:<5} {desc:<24} {'not reached':>14} {'':>14}")

    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
