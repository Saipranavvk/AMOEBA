"""Program the PL and set its clock, without needing pynq.

Two jobs that have to happen together, and one of which is easy to forget.

PROGRAMMING.  `pynq.Bitstream` is used when it is importable.  When it is not --
a plain Zynq Linux, or PYNQ v3.x where `pynq` lives in a venv that `sudo
python3` does not see -- we fall back to the kernel's fpga_manager, which needs
no packages at all.  That path converts the `.bit` to the raw form the driver
wants: strip the Xilinx header, then byte-swap every 32-bit word, because the
PCAP DMA reads little-endian words out of memory and the configuration stream is
defined big-endian.  The sync word is the tell: `AA 99 55 66` in the `.bit`
becomes `66 55 99 AA` in the `.bin`, which is the pattern zynq-fpga scans for.

THE CLOCK.  This is the part that bites.  The block design asks for
FCLK_CLK0 = 25 MHz and the `.hwh` records it, but *nothing programs it at
runtime* unless you go through `pynq.Overlay`, which reads the `.hwh` and
applies it.  We deliberately use `Bitstream` instead so that an unparseable
`.hwh` cannot block bring-up -- and the cost of that choice is that FCLK0 stays
at whatever the PYNQ boot default left it, usually 100 MHz.  Against a design
that closed timing at 25.5 MHz, that is not a subtle failure, but it is an
invisible one: the PL is configured, the registers read back, and the core
produces garbage.  So we program FCLK0 here, from the SLCR, every time.

Neither of those is trusted afterwards.  `Amoeba.measure_fclk()` counts real PL
cycles against host wall time, which is the only statement about the clock that
does not depend on this file's arithmetic being right.
"""

import array
import os
import struct
import subprocess
import time
from typing import Dict, Optional, Tuple

# ---- SLCR (UG585 ch. 25) --------------------------------------------------
SLCR_BASE = 0xF8000000
SLCR_SPAN = 0x1000

SLCR_LOCK = 0x004
SLCR_UNLOCK = 0x008
SLCR_LOCK_KEY = 0x767B
SLCR_UNLOCK_KEY = 0xDF0D

ARM_PLL_CTRL = 0x100
DDR_PLL_CTRL = 0x104
IO_PLL_CTRL = 0x108
FPGA0_CLK_CTRL = 0x170

# PS_CLK is a board-level crystal, not something the SoC can report.  50 MHz is
# right for PYNQ-Z1 and Z2; ZedBoard and friends use 33.333.
PS_CLK_MHZ = float(os.environ.get("AMOEBA_PS_CLK_MHZ", "50.0"))

FIRMWARE_DIR = "/lib/firmware"
FPGA_MANAGER = "/sys/class/fpga_manager/fpga0"


# ---- .bit parsing ---------------------------------------------------------
def parse_bit(path: str) -> Tuple[Dict[bytes, bytes], bytes]:
    """Split a Xilinx .bit into its header fields and its raw payload.

    Layout: a 9-byte magic, then length-prefixed fields keyed 'a'..'d'
    (design, part, date, time), then 'e' with a 4-byte length and the
    configuration stream.
    """
    with open(path, "rb") as fh:
        blob = fh.read()

    def be16(p): return struct.unpack_from(">H", blob, p)[0]
    def be32(p): return struct.unpack_from(">I", blob, p)[0]

    pos = 0
    n = be16(pos); pos += 2 + n                 # magic
    n = be16(pos); pos += 2
    key = blob[pos:pos + n]; pos += n
    if key != b"a":
        raise ValueError(f"{path} is not a Xilinx .bit (first key {key!r})")
    n = be16(pos); pos += 2
    fields = {b"a": blob[pos:pos + n]}; pos += n

    while pos < len(blob):
        k = blob[pos:pos + 1]; pos += 1
        if k == b"e":
            n = be32(pos); pos += 4
            return fields, blob[pos:pos + n]
        n = be16(pos); pos += 2
        fields[k] = blob[pos:pos + n]; pos += n

    raise ValueError(f"{path}: no 'e' payload field")


def bit_to_bin(path: str) -> bytes:
    """The byte-swapped configuration stream fpga_manager expects."""
    _, data = parse_bit(path)
    if len(data) % 4:
        raise ValueError(f"{path}: payload {len(data)} bytes is not word-aligned")
    words = array.array("I")
    if words.itemsize != 4:
        raise RuntimeError("array('I') is not 32-bit on this platform")
    words.frombytes(data)
    words.byteswap()
    out = words.tobytes()
    if out.find(bytes.fromhex("665599aa")) < 0:
        raise ValueError(
            f"{path}: no sync word in the converted stream -- this does not "
            "look like a full configuration bitstream")
    return out


def bit_part(path: str) -> str:
    fields, _ = parse_bit(path)
    return fields.get(b"b", b"").rstrip(b"\x00").decode("ascii", "replace")


# ---- SLCR clock control ---------------------------------------------------
class _Slcr:
    """Word access to the SLCR, with the write lock handled."""

    def __init__(self):
        from .mmio import Mmio
        self._m = Mmio(SLCR_BASE, SLCR_SPAN)

    def read(self, off: int) -> int:
        return self._m.read(off)

    def write(self, off: int, val: int) -> None:
        self._m.write(SLCR_UNLOCK, SLCR_UNLOCK_KEY)
        self._m.write(off, val)
        self._m.write(SLCR_LOCK, SLCR_LOCK_KEY)

    def close(self) -> None:
        self._m.close()

    def __enter__(self): return self
    def __exit__(self, *a): self.close()

    # -- derived ------------------------------------------------------------
    def pll_mhz(self, srcsel: int) -> float:
        reg = {0: IO_PLL_CTRL, 1: IO_PLL_CTRL,
               2: ARM_PLL_CTRL, 3: DDR_PLL_CTRL}[srcsel & 3]
        fdiv = (self.read(reg) >> 12) & 0x7F
        return PS_CLK_MHZ * fdiv


def fclk0_mhz() -> float:
    """What FCLK_CLK0 is actually set to right now, per the SLCR."""
    with _Slcr() as s:
        ctrl = s.read(FPGA0_CLK_CTRL)
        srcsel = (ctrl >> 4) & 0x3
        div0 = (ctrl >> 8) & 0x3F
        div1 = (ctrl >> 20) & 0x3F
        if div0 == 0 or div1 == 0:
            return 0.0
        return s.pll_mhz(srcsel) / (div0 * div1)


def best_divisors(src_mhz: float, target_mhz: float) -> Tuple[int, int]:
    """Pick the 6-bit divisor pair whose product best hits `target_mhz`.

    Ties are broken toward the more balanced pair.  UG585 recommends
    DIVISOR1 <= DIVISOR0, and a balanced split also keeps the intermediate
    clock inside the range the divider is specified for.
    """
    best, err = None, None
    for d0 in range(1, 64):
        for d1 in range(1, d0 + 1):
            e = abs(src_mhz / (d0 * d1) - target_mhz)
            if err is None or e < err - 1e-12:
                best, err = (d0, d1), e
    return best


def set_fclk0_mhz(target: float) -> float:
    """Set FCLK_CLK0 as close to `target` as the dividers allow.

    Returns the frequency actually programmed.  Divisors are 6-bit and the
    product sets the ratio, so the achievable set is coarse; the caller should
    check the returned value rather than assume it got what it asked for.
    """
    with _Slcr() as s:
        ctrl = s.read(FPGA0_CLK_CTRL)
        srcsel = (ctrl >> 4) & 0x3
        src = s.pll_mhz(srcsel)
        if src <= 0:
            raise RuntimeError("could not determine the source PLL frequency")

        d0, d1 = best_divisors(src, target)

        new = (ctrl & ~((0x3F << 20) | (0x3F << 8))) | (d1 << 20) | (d0 << 8)
        s.write(FPGA0_CLK_CTRL, new)
        return src / (d0 * d1)


# ---- programming ----------------------------------------------------------
def _program_via_pynq(path: str) -> bool:
    try:
        from pynq import Bitstream
    except ImportError:
        return False
    Bitstream(path).download()
    return True


def _program_via_fpga_manager(path: str) -> None:
    if not os.path.isdir(FPGA_MANAGER):
        raise RuntimeError(
            f"no {FPGA_MANAGER} and pynq is not importable, so there is no way "
            "to program the PL.\n"
            "  On a PYNQ v3 image, pynq lives in a venv that 'sudo python3'\n"
            "  does not see.  Try:\n"
            "    sudo /usr/local/share/pynq-venv/bin/python3 run_freertos.py ...\n"
            "  Or program the PL yourself and re-run with --no-download.")

    blob = bit_to_bin(path)
    name = os.path.basename(path).rsplit(".", 1)[0] + ".bin"
    dest = os.path.join(FIRMWARE_DIR, name)

    os.makedirs(FIRMWARE_DIR, exist_ok=True)
    # Write via a temporary and rename, so a half-written file is never the one
    # the driver is told to load.
    tmp = dest + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(blob)
    os.replace(tmp, dest)

    with open(os.path.join(FPGA_MANAGER, "flags"), "w") as fh:
        fh.write("0")                       # full bitstream, not partial
    with open(os.path.join(FPGA_MANAGER, "firmware"), "w") as fh:
        fh.write(name)

    state = _fpga_state()
    if state != "operating":
        raise RuntimeError(
            f"fpga_manager finished in state '{state}', expected 'operating'; "
            f"check dmesg")


def _fpga_state() -> str:
    try:
        with open(os.path.join(FPGA_MANAGER, "state")) as fh:
            return fh.read().strip()
    except OSError:
        return "unknown"


def program(path: str, fclk_mhz: Optional[float] = 25.0,
            verbose: bool = True) -> None:
    """Download `path` to the PL and set FCLK_CLK0.

    `fclk_mhz=None` leaves the clock alone, which is only correct if something
    else has already set it.
    """
    if not os.path.exists(path):
        raise FileNotFoundError(path)

    part = bit_part(path)
    if verbose:
        print(f"# programming PL: {os.path.basename(path)} for {part}")

    if _program_via_pynq(path):
        how = "pynq.Bitstream"
    else:
        _program_via_fpga_manager(path)
        how = "fpga_manager"
    if verbose:
        print(f"#   downloaded via {how}")

    if fclk_mhz is not None:
        before = fclk0_mhz()
        got = set_fclk0_mhz(fclk_mhz)
        if verbose:
            print(f"#   FCLK0 {before:.3f} -> {got:.3f} MHz "
                  f"(asked for {fclk_mhz:.3f})")
        if abs(got - fclk_mhz) / fclk_mhz > 0.02:
            raise RuntimeError(
                f"could not set FCLK0 to {fclk_mhz} MHz; nearest achievable "
                f"from this PLL is {got:.3f} MHz")
        # The PL sees the new clock immediately, but give the reset
        # synchroniser a moment before anyone touches a register.
        time.sleep(0.05)
