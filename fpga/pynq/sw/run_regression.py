#!/usr/bin/env python3
"""Run the FreeRTOS regression suite on the board.

    sudo python3 run_regression.py --bitstream ../amoeba.bit --images ../images

Each test runs to its HTIF exit and must exit 0.  The bitstream is programmed
once, not per test: downloading it is the slowest thing here, and the load path
already zeroes memory between runs.

Beyond pass/fail it records cycles and retired counts to JSON.  Those are the
interesting numbers, because they are the ones that can be compared against
simulation -- a test that passes on hardware and in Verilator but retires a
different number of instructions means the two are not running the same
program, and that difference is worth understanding before it is load-bearing.
Record a baseline with --save, compare later with --golden.
"""

import argparse
import glob
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import image as _image                       # noqa: E402
from amoeba import regs as R                             # noqa: E402
from amoeba.device import Amoeba, AmoebaError            # noqa: E402


def run_one(dev, path, timeout, quiet):
    img = _image.load(path)
    dev.run(img)

    out = bytearray()
    t0 = time.monotonic()
    for chunk in dev.stream_console(timeout):
        out += chunk
        if not quiet and chunk:
            sys.stdout.write(chunk.decode("ascii", "replace"))
            sys.stdout.flush()
    wall = time.monotonic() - t0

    res = {
        "test": os.path.basename(path).rsplit(".", 1)[0],
        "wall_s": round(wall, 3),
        "cycles": dev.cycles,
        "retired": dev.retired,
        "traps": dev.traps,
        "tohost_valid": dev.tohost_valid,
        "exit_code": dev.exit_code if dev.tohost_valid else None,
        "uart_overflow": dev.uart_overflow,
        "console": out.decode("ascii", "replace"),
    }
    res["pass"] = bool(res["tohost_valid"] and res["exit_code"] == 0
                       and not res["uart_overflow"])
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--images", default="../images",
                    help="directory of .elf images, or a single .elf")
    ap.add_argument("--pattern", default="tc_*.elf",
                    help="which images in that directory form the suite "
                         "(default tc_*.elf, matching FREERTOS_TESTS in "
                         "sim/Makefile).  Use '*.elf' to run everything.")
    ap.add_argument("--bitstream", help="program the PL once, before the suite")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--skip", action="append", default=[],
                    help="test name to skip (repeatable)")
    ap.add_argument("--save", help="write results to this JSON file")
    ap.add_argument("--golden", help="compare retired counts against this JSON")
    ap.add_argument("--quiet", action="store_true",
                    help="do not echo console output as it arrives")
    args = ap.parse_args()

    # The suite is the tc_* images, the same convention sim/Makefile uses for
    # FREERTOS_TESTS.  Naming it by pattern rather than excluding known
    # non-terminating programs matters: a stale image left in the directory by
    # an earlier deploy is otherwise picked up and burns a full timeout.
    if os.path.isdir(args.images):
        paths = sorted(glob.glob(os.path.join(args.images, args.pattern)))
        others = set(glob.glob(os.path.join(args.images, "*.elf"))) - set(paths)
        if others:
            print(f"# ignoring {len(others)} image(s) not matching "
                  f"{args.pattern}: "
                  + ", ".join(sorted(os.path.basename(o) for o in others)))
    else:
        paths = [args.images]
    paths = [p for p in paths
             if os.path.basename(p).rsplit(".", 1)[0] not in args.skip]
    if not paths:
        print(f"no images to run in {args.images}", file=sys.stderr)
        return 2

    golden = {}
    if args.golden:
        with open(args.golden) as fh:
            golden = {r["test"]: r for r in json.load(fh)["results"]}

    try:
        dev = Amoeba(bitstream=args.bitstream,
                     fclk_mhz=args.fclk if args.fclk > 0 else None)
    except PermissionError:
        print("error: need root for /dev/mem (try sudo)", file=sys.stderr)
        return 2
    except AmoebaError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(f"# {dev.describe()}")
    if args.fclk > 0:
        try:
            print(f"# fabric clock verified: {dev.check_fclk(args.fclk)/1e6:.3f} MHz")
        except AmoebaError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
    print(f"# {len(paths)} test(s)\n")

    results = []
    for p in paths:
        name = os.path.basename(p).rsplit(".", 1)[0]
        print(f"=== {name} ===")
        try:
            res = run_one(dev, p, args.timeout, args.quiet)
        except AmoebaError as exc:
            print(f"  error: {exc}")
            results.append({"test": name, "pass": False, "error": str(exc)})
            continue
        results.append(res)
        verdict = "PASS" if res["pass"] else "FAIL"
        detail = (f"exit={res['exit_code']}" if res["tohost_valid"]
                  else "no tohost (timeout)")
        print(f"  {verdict}  {detail}  {res['retired']} retired, "
              f"{res['cycles']} cycles, {res['traps']} traps, "
              f"{res['wall_s']}s")
        if res["uart_overflow"]:
            print("  WARNING: console FIFO overflowed -- output above is "
                  "incomplete, and this counts as a failure")
        g = golden.get(name)
        if g and g.get("retired") is not None:
            d = res["retired"] - g["retired"]
            if d:
                print(f"  retired differs from golden by {d:+d} "
                      f"({g['retired']} -> {res['retired']})")
            else:
                print(f"  retired matches golden exactly ({res['retired']})")
        print()

    npass = sum(1 for r in results if r.get("pass"))
    print(f"=== {npass}/{len(results)} passed ===")
    for r in results:
        if not r.get("pass"):
            print(f"    failed: {r['test']}")

    if args.save:
        with open(args.save, "w") as fh:
            json.dump({"fclk_mhz": args.fclk, "results": results}, fh, indent=2)
        print(f"\nwrote {args.save}")

    return 0 if npass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
