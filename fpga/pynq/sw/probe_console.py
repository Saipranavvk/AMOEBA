#!/usr/bin/env python3
"""Find the board's serial console, or prove nothing is coming out of it.

    sudo python3 probe_console.py
    sudo python3 probe_console.py --port /dev/ttyUSB1 --baud 115200

A blank terminal has several causes that look identical, and guessing between
them wastes a lot of time:

  - the board booted before you attached, so it has already printed everything
    it is going to print and is sitting at a login prompt waiting for input
  - you are on the wrong FT2232 channel (A is JTAG, B is the UART, and which
    one enumerates as ttyUSB0 is not guaranteed)
  - the baud rate is wrong
  - the PS is not booting at all

Every port operation runs under a hard SIGALRM timeout.  That is not defensive
programming for its own sake: opening or writing an FTDI channel that is in JTAG
mode rather than UART mode can block in the kernel indefinitely, and so can
tcdrain on a line whose far end never reads.  A probe that hangs tells you
nothing, which is worse than a probe that reports silence.
"""

import argparse
import glob
import signal
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("needs pyserial:  pip3 install pyserial   "
             "(or apt install python3-serial)")

BAUDS = [115200, 9600, 38400, 57600, 921600]
READ_S = 1.2
HARD_TIMEOUT_S = 4


class Stalled(Exception):
    pass


def _alarm(_sig, _frm):
    raise Stalled()


signal.signal(signal.SIGALRM, _alarm)


def printable_ratio(data: bytes) -> float:
    if not data:
        return 0.0
    ok = sum(1 for b in data if 32 <= b < 127 or b in (9, 10, 13))
    return ok / len(data)


def probe(port: str, baud: int, read_s: float):
    """Open, prod, read.

    Returns (data, note).  `note` is None on success, otherwise a short reason
    the caller prints instead of "silent" -- a port that could not be opened has
    told us nothing about whether the board is talking.
    """
    s = None
    signal.alarm(HARD_TIMEOUT_S)
    try:
        # Build the port unopened so every setting is applied before open(),
        # and disable all three kinds of flow control explicitly.  With RTS/CTS
        # left on, a far end that never asserts CTS makes write() block forever.
        s = serial.Serial()
        s.port = port
        s.baudrate = baud
        s.timeout = 0.2
        s.write_timeout = 0.5
        s.rtscts = False
        s.dsrdtr = False
        s.xonxoff = False
        s.exclusive = True
        s.open()

        s.dtr = True
        s.rts = True
        time.sleep(0.05)
        s.reset_input_buffer()

        # No flush()/tcdrain here on purpose -- see the module docstring.
        try:
            s.write(b"\r\n")
        except serial.SerialTimeoutException:
            pass

        out = bytearray()
        end = time.monotonic() + read_s
        while time.monotonic() < end:
            out += s.read(4096)
        return bytes(out), None

    except Stalled:
        return b"", "hung (channel is probably JTAG, not a UART)"
    except PermissionError:
        return b"", "PERMISSION"
    except (serial.SerialException, OSError) as exc:
        msg = str(exc).split("\n")[0]
        if "Permission denied" in msg:
            return b"", "PERMISSION"
        return b"", msg
    finally:
        signal.alarm(0)
        if s is not None:
            try:
                s.close()
            except Exception:
                pass


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", help="probe only this port")
    ap.add_argument("--baud", type=int, help="probe only this rate")
    ap.add_argument("--read", type=float, default=READ_S,
                    help="seconds to listen per attempt")
    args = ap.parse_args()

    ports = [args.port] if args.port else sorted(
        glob.glob("/dev/ttyUSB*") + glob.glob("/dev/ttyACM*"))
    bauds = [args.baud] if args.baud else BAUDS

    if not ports:
        return err("no /dev/ttyUSB* or /dev/ttyACM* at all -- is the micro-USB "
                   "cable plugged in, and does 'lsusb' show 0403:6010?")

    total = len(ports) * len(bauds)
    print(f"probing {len(ports)} port(s) x {len(bauds)} rate(s), "
          f"about {total * (args.read + 0.3):.0f}s\n", flush=True)

    hits, live = [], False
    for port in ports:
        for baud in bauds:
            # Printed BEFORE the attempt, and flushed, so a hang is visibly
            # attributable to a specific port and rate rather than looking like
            # the whole script died.
            print(f"  {port:16} {baud:>7} ... ", end="", flush=True)
            data, note = probe(port, baud, args.read)
            if note == "PERMISSION":
                print("permission denied", flush=True)
                return err("\nthese ports need root or the dialout group:\n"
                           "    sudo python3 probe_console.py\n"
                           "  or, once:\n"
                           "    sudo usermod -aG dialout $USER   "
                           "(then log out and back in)")
            if note:
                print(note, flush=True)
                continue
            if not data:
                print("silent", flush=True)
                continue
            ratio = printable_ratio(data)
            live = True
            if ratio > 0.8:
                print(f"{len(data)} bytes, TEXT", flush=True)
                hits.append((port, baud, data))
            else:
                print(f"{len(data)} bytes, garbage (wrong baud?)", flush=True)

    print(flush=True)
    if not hits:
        if live:
            return err("bytes arrived but never decoded as text: the line is\n"
                       "alive but none of the rates tried are right.  Check\n"
                       "what the image's console is set to.")
        return err(
            "nothing readable on any port at any rate.\n\n"
            "  Most likely, in order:\n"
            "    1. the board booted before you looked and is idle at a login\n"
            "       prompt -- but this script sends a newline, so that should\n"
            "       have produced output.  Try --read 5.\n"
            "    2. the boot-mode jumper is not on SD.  On JTAG or QSPI the\n"
            "       board powers up and does nothing: no console, no network.\n"
            "    3. the SD card is not bootable, or the image is for a\n"
            "       PYNQ-Z1 rather than a Z2.")

    port, baud, data = hits[0]
    print(f"CONSOLE: {port} at {baud}\n", flush=True)
    text = data.decode("ascii", "replace")
    for line in text.splitlines()[-15:]:
        print(f"  | {line}")
    print(f"\n  sudo screen {port} {baud}      (exit: Ctrl-A then k)")
    if "login:" in text:
        print("  it is at a login prompt: xilinx / xilinx")
    return 0


def err(msg: str) -> int:
    print(msg, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
