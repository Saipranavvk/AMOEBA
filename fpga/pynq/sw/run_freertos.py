#!/usr/bin/env python3
"""Load a FreeRTOS image onto the soft core, run it, and report.

  ./run_freertos.py --image freertos_wally.elf --bitstream amoeba.bit
  ./run_freertos.py --image freertos_wally.elf --soak 30      # heartbeat

Exits with the program's HTIF code, so this drops straight into a regression
harness.

The soak mode is the interesting one.  It measures the PL's cycle counter
against the host's wall clock to get the true fabric clock, and separately
measures the guest's heartbeat rate to get the clock the guest BELIEVES it is
running at.  Those two being equal is the check; when they are not, the ratio
is exactly the factor configCPU_CLOCK_HZ is wrong by.  Nothing else in the test
suite can catch that -- a terminating test verifies ordering and results, not
rates, so it passes just as happily on a 4x-wrong clock.
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, AmoebaError, image as _image, regs as R  # noqa: E402

HB_START = re.compile(rb"HB start period_ms=(\d+) tick_hz=(\d+) cpu_hz=(\d+)")
HB_BEAT = re.compile(rb"HB seq=(\d+) tick=(\d+)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image", required=True, help="ELF, or flat binary with --base")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=None,
                    help="load address for a flat binary")
    ap.add_argument("--bitstream",
                    help="program the PL first (uses pynq if importable, "
                         "otherwise the kernel's fpga_manager)")
    ap.add_argument("--fclk", type=float, default=25.0,
                    help="PL clock in MHz to program and then verify "
                         "(default 25, which is what the design closed "
                         "timing at); 0 disables both")
    ap.add_argument("--timeout", type=float, default=30.0)
    ap.add_argument("--soak", type=float, default=0.0,
                    help="run for N seconds without expecting an exit, and "
                         "report heartbeat timing")
    ap.add_argument("--expect-exit", type=int, default=None)
    ap.add_argument("--no-verify", action="store_true",
                    help="skip image readback (faster, and a bad idea)")
    ap.add_argument("--quiet", action="store_true", help="do not echo the console")
    ap.add_argument("--legacy-axi-reset", action="store_true",
                    help="workaround for bitstreams built before "
                         "amoeba_mem_bram got its own s_axi_aresetn, where "
                         "the first write to the image window deadlocks the "
                         "PS.  Releases the core across the load.")
    args = ap.parse_args()

    img = _image.load(args.image, base=args.base)

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

    # Before anything else touches the core: confirm the PL is running at the
    # frequency this bitstream was closed for.  Measured against wall time, not
    # read back from the SLCR -- a register that agrees with the value we just
    # wrote proves only that the write landed.
    if args.fclk > 0:
        try:
            got = dev.check_fclk(args.fclk)
            print(f"# fabric clock verified: {got/1e6:.3f} MHz")
        except AmoebaError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2

    print(f"# image {os.path.basename(img.path)}: "
          f"0x{img.load_base:08x}..0x{img.load_end:08x}, "
          f"{img.file_bytes} bytes to load, entry 0x{img.entry:08x}")

    try:
        dev.run(img, verify=not args.no_verify,
                legacy_axi_reset=args.legacy_axi_reset)
    except AmoebaError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    t0 = time.monotonic()
    c0 = dev.cycles
    hb = _Heartbeat()
    out = bytearray()

    timeout = args.soak if args.soak else args.timeout
    try:
        for chunk in dev.stream_console(timeout, until_tohost=not args.soak):
            out += chunk
            hb.feed(chunk, time.monotonic())
            if not args.quiet:
                sys.stdout.buffer.write(chunk)
                sys.stdout.flush()
    except KeyboardInterrupt:
        print("\n# interrupted", file=sys.stderr)

    wall = time.monotonic() - t0
    cycles = dev.cycles - c0

    if out and not out.endswith(b"\n") and not args.quiet:
        sys.stdout.buffer.write(b"\n")
        sys.stdout.flush()

    # ---- the PL's own view -------------------------------------------------
    print(f"# ran {wall:.3f} s wall, {cycles} cycles, "
          f"{dev.retired} retired, {dev.traps} traps")
    if dev.uart_overflow:
        print("# WARNING: console FIFO overflowed -- output above has gaps",
              file=sys.stderr)

    # The authoritative clock measurement: PL cycles against host wall time.
    # Involves no guest software at all.
    if wall > 0.5 and cycles > 0:
        fclk = cycles / wall
        print(f"# fabric clock (PL cycles / wall time): {fclk / 1e6:.3f} MHz")
        hb.report(fclk)
    elif args.soak:
        print("# too short to measure the clock; try --soak 5 or more")

    # ---- exit --------------------------------------------------------------
    if args.soak:
        return 0

    if not dev.tohost_valid:
        print(f"# TIMEOUT after {args.timeout} s with no tohost write",
              file=sys.stderr)
        _diagnose(dev, cycles)
        return 124

    code = dev.exit_code
    print(f"# exit {code}")
    if args.expect_exit is not None and code != args.expect_exit:
        print(f"# FAIL: expected exit {args.expect_exit}", file=sys.stderr)
        return 1
    return code


def _diagnose(dev, cycles: int) -> None:
    """The ladder from BRINGUP.md, applied automatically on a timeout."""
    if cycles == 0:
        print("#   CYCLES did not advance: the core is not clocked, or reset "
              "was never released.", file=sys.stderr)
    elif dev.retired == 0:
        print("#   CYCLES advanced but RETIRED is 0: the core is fetching but "
              "nothing commits.\n"
              "#   Suspect the image or the reset vector.", file=sys.stderr)
    elif dev.traps > 0:
        print(f"#   RETIRED advanced and TRAPS is {dev.traps}: it is probably "
              "trapping in a loop.", file=sys.stderr)
    else:
        print("#   The core ran and retired instructions but never wrote "
              "tohost.\n"
              "#   If the console looked right, suspect the tohost address: "
              "see BRINGUP.md 0.1.", file=sys.stderr)


class _Heartbeat:
    """Parse heartbeat_app.c output and time the beats."""

    def __init__(self):
        self.buf = bytearray()
        self.cfg = None            # (period_ms, tick_hz, cpu_hz)
        self.stamps = []           # wall time of each beat
        self.ticks = []

    def feed(self, chunk: bytes, now: float) -> None:
        self.buf += chunk
        while b"\n" in self.buf:
            line, _, rest = self.buf.partition(b"\n")
            self.buf = bytearray(rest)
            m = HB_START.search(line)
            if m:
                self.cfg = tuple(int(g) for g in m.groups())
                continue
            m = HB_BEAT.search(line)
            if m:
                self.stamps.append(now)
                self.ticks.append(int(m.group(2)))

    def report(self, fclk_hz: float) -> None:
        if self.cfg is None or len(self.stamps) < 3:
            return
        period_ms, tick_hz, cpu_hz = self.cfg
        period_s = period_ms / 1000.0

        gaps = [b - a for a, b in zip(self.stamps, self.stamps[1:])]
        mean = sum(gaps) / len(gaps)
        jitter = max(gaps) - min(gaps)

        print(f"# heartbeat: {len(self.stamps)} beats, "
              f"mean {mean * 1e3:.2f} ms, jitter {jitter * 1e3:.2f} ms "
              f"(guest intends {period_ms} ms)")

        # CALIBRATION.  The guest schedules N = cpu_hz * period_s mtime
        # increments per beat, and mtime advances once per fabric clock, so a
        # beat actually takes N / fclk seconds.  Beats arriving late by exactly
        # the ratio cpu_hz / fclk is the signature of a wrong
        # configCPU_CLOCK_HZ -- and comparing the measured period against the
        # INTENDED one is the only way to see it.  (Comparing an "implied
        # clock" against the measured fabric clock does not work: both are
        # estimates of the same quantity and agree by construction whether or
        # not the guest's constant is right.)
        implied = (cpu_hz * period_s) / mean
        drift = (mean - period_s) / period_s * 100.0

        if abs(drift) > 5.0:
            print(f"# MISMATCH: beats arrive every {mean * 1e3:.1f} ms, not "
                  f"{period_ms} ms ({drift:+.0f}%).\n"
                  f"#   configCPU_CLOCK_HZ is {cpu_hz}, but the core is running "
                  f"at about {implied / 1e6:.3f} MHz, so every interval in the "
                  f"guest is off by {cpu_hz / implied:.2f}x.\n"
                  f"#   Rebuild with FPGA_CLOCK_HZ={int(round(implied))}.",
                  file=sys.stderr)
        else:
            print(f"# clock calibration OK ({drift:+.1f}% off the intended "
                  f"period)")

        # CONSISTENCY.  Two independent estimates of the same fabric clock: one
        # from the guest's timer, one from the PL counter against host wall
        # time.  They should agree regardless of whether cpu_hz is right.  If
        # they do not, mtime and the PL cycle counter are not counting the same
        # thing, which would be a hardware problem rather than a build one.
        skew = (implied - fclk_hz) / fclk_hz * 100.0
        note = "consistent" if abs(skew) < 5.0 else "INCONSISTENT"
        print(f"# clock cross-check: guest timer says {implied / 1e6:.3f} MHz, "
              f"PL counter says {fclk_hz / 1e6:.3f} MHz ({skew:+.1f}%, {note})")
        if abs(skew) >= 5.0:
            print("#   mtime and the PL cycle counter disagree; they are both "
                  "supposed to be FCLK_CLK0.", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
