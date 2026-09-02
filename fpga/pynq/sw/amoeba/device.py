"""The Amoeba class: everything the PS can do to the soft core.

The organizing rule, which every method here assumes: THE PS OWNS THE CORE'S
RESET, and it comes out of configuration asserted.  So the core is halted after
the bitstream loads, and the image load, trigger setup and monitor clear all
happen in a quiescent design.  Nothing here races the core, because anything
that would is done while it is held.
"""

import time
from typing import Iterator, Optional

from . import image as _image
from . import regs as R
from . import pl as _pl
from .mmio import Mmio


class AmoebaError(RuntimeError):
    pass


class Amoeba:
    def __init__(self, bitstream: Optional[str] = None, *,
                 check_id: bool = True, fclk_mhz: Optional[float] = 25.0):
        """`fclk_mhz` is programmed after download, and must be.

        Nothing else sets it.  The block design records 25 MHz in the .hwh, but
        only pynq.Overlay reads that field, and we use pynq.Bitstream on
        purpose so an unparseable .hwh cannot block bring-up.  Left alone, the
        PL runs at whatever the boot default was -- usually 100 MHz, against a
        design that closed timing at 25.5.  Pass None only if something else
        has already set the clock.
        """
        if bitstream:
            _pl.program(bitstream, fclk_mhz=fclk_mhz)
        self.ctl = Mmio(R.CTL_BASE, R.CTL_SIZE)
        self._mem: Optional[Mmio] = None
        if check_id:
            self.check_id()

    def measure_fclk(self, seconds: float = 0.5) -> float:
        """PL cycles against host wall time -- the clock, measured not assumed.

        This is the only statement about the fabric clock that does not depend
        on the SLCR arithmetic in pl.py being correct, so it is what the
        callers check against.  The core does not need to be running; the cycle
        counter is free-running whenever the core is out of reset.
        """
        was_reset = self.in_reset
        if was_reset:
            self.start()
        c0, t0 = self.cycles, time.monotonic()
        time.sleep(seconds)
        c1, t1 = self.cycles, time.monotonic()
        if was_reset:
            self.halt()
        dt = t1 - t0
        return (c1 - c0) / dt if dt > 0 else 0.0

    def check_fclk(self, expect_mhz: float = 25.0, tol: float = 0.05) -> float:
        """Measure the fabric clock and refuse to continue if it is wrong.

        A PL running at 4x its timing-closed frequency does not announce
        itself: registers still read back, the core still fetches, and what
        comes out is garbage that looks like a logic bug.  Checking here turns
        a day of debugging into one line.
        """
        got = self.measure_fclk()
        if got <= 0:
            raise AmoebaError(
                "the PL cycle counter is not advancing: FCLK0 is stopped, or "
                "the core is held in reset by something other than us.")
        if abs(got - expect_mhz * 1e6) / (expect_mhz * 1e6) > tol:
            raise AmoebaError(
                f"fabric clock measures {got/1e6:.3f} MHz, expected "
                f"{expect_mhz:.3f} MHz.\n"
                "  The design closed timing at 25.5 MHz; running it faster "
                "produces wrong results, not an error.\n"
                "  Set it with:  python3 -c 'from amoeba import pl; "
                "pl.set_fclk0_mhz(25)'")
        return got

    # ---- identity ---------------------------------------------------------
    def check_id(self) -> None:
        """First thing, always.

        A wrong magic here means the overlay did not load or the base address
        is wrong, and every subsequent symptom -- a core that never runs, a
        console that stays empty -- is downstream of it.  Fail here, loudly,
        rather than letting it present as dead hardware.
        """
        got = self.ctl.read(R.R_ID)
        if got != R.ID_MAGIC:
            raise AmoebaError(
                f"ID at 0x{R.CTL_BASE:08x} reads 0x{got:08x}, expected "
                f"0x{R.ID_MAGIC:08x} ('AMOB').\n"
                "  The bitstream is not loaded, or is not this design, or "
                "CTL_BASE in regs.py does not match tcl/bd_pynq.tcl."
            )

    @property
    def version(self) -> int:
        return self.ctl.read(R.R_VERSION)

    @property
    def caps(self) -> int:
        return self.ctl.read(R.R_CAPS)

    @property
    def mem_kb(self) -> int:
        return R.caps_mem_kb(self.caps)

    @property
    def is_bram(self) -> bool:
        return R.caps_is_bram(self.caps)

    @property
    def has_trace(self) -> bool:
        return R.caps_has_trace(self.caps)

    def describe(self) -> str:
        v = self.version
        return (f"amoeba v{(v >> 16) & 0xFF}.{(v >> 8) & 0xFF}.{v & 0xFF}  "
                f"mem={self.mem_kb} KiB  "
                f"backend={'BRAM' if self.is_bram else 'AXI/DDR'}  "
                f"trace={'yes' if self.has_trace else 'no'}")

    # ---- reset and monitors ----------------------------------------------
    @property
    def in_reset(self) -> bool:
        return bool(self.ctl.read(R.R_STATUS) & R.ST_CORE_RESET)

    def halt(self) -> None:
        self.ctl.write(R.R_CTRL, R.CTRL_CORE_RESET)

    def clear_monitors(self) -> None:
        """One-cycle pulse; the reset bit must be preserved across it."""
        keep = self.ctl.read(R.R_CTRL) & R.CTRL_CORE_RESET
        self.ctl.write(R.R_CTRL, keep | R.CTRL_MON_CLEAR | R.CTRL_TRACE_CLEAR)
        self.ctl.write(R.R_CTRL, keep)

    def start(self) -> None:
        self.ctl.write(R.R_CTRL, 0)

    # ---- image ------------------------------------------------------------
    @property
    def mem(self) -> Mmio:
        if self._mem is None:
            if not self.is_bram:
                raise AmoebaError(
                    "this bitstream has no image window: it is an AXI/DDR "
                    "build, where the PS writes the carve-out directly")
            self._mem = Mmio(R.MEM_BASE, self.mem_kb * 1024)
        return self._mem

    def load(self, img: "_image.Image", *, verify: bool = True,
             zero: bool = True, legacy_axi_reset: bool = False) -> None:
        """Load a program while the core is held in reset.

        Checks three things before writing anything, because each of them
        produces a confusing failure much later:

        - that the core is actually halted.  The two BRAM ports are not
          arbitrated -- they are never meant to be live at once -- so writing
          while the core runs corrupts memory silently.
        - that the image fits.  amoeba_mem_bram truncates rather than faulting,
          so an over-large image wraps onto its own start.
        - that the program's `tohost` matches the address the bus monitor is
          watching.  If those drift, the run prints correct console output and
          then hangs forever waiting for an exit that was never seen.
        """
        if not self.in_reset:
            raise AmoebaError("core is running; call halt() before load()")

        size = self.mem_kb * 1024
        end = img.load_end - R.EXT_MEM_BASE
        if img.load_base < R.EXT_MEM_BASE or end > size:
            raise AmoebaError(
                f"image spans 0x{img.load_base:08x}..0x{img.load_end:08x}, "
                f"outside the {self.mem_kb} KiB window at "
                f"0x{R.EXT_MEM_BASE:08x}.\n"
                "  The memory truncates rather than faulting, so this would "
                "wrap onto itself.  Rebuild with a matching linker script, or "
                "raise MEM_KB.")

        want = R.tohost_addr(self.mem_kb, self.is_bram)
        have = img.tohost()
        if have is not None and have != want:
            raise AmoebaError(
                f"{img.path} puts tohost at 0x{have:08x}; the bus monitor "
                f"watches 0x{want:08x}.\n"
                "  Exit detection would never fire.  Build with "
                "TARGET=pynq (freertos_pynq.ld), or check MEM_KB.")

        if legacy_axi_reset:
            # Workaround for bitstreams built before amoeba_mem_bram got its
            # own s_axi_aresetn.  In those, port B is reset from HRESETn, which
            # the SoC asserts while the core is halted -- so the load port is
            # dead exactly when loading happens, and the first write deadlocks
            # the PS on an AXI transaction that never completes.
            #
            # Releasing the core first raises HRESETn and makes the port
            # answer.  That is safe here only because of what the core does
            # meanwhile: block RAM is zeroed by configuration, all-zero decodes
            # as an illegal instruction, and the trap vector resets to 0, which
            # is outside the memory map -- so it spins taking access faults and
            # never retires a store.  It cannot touch the image being written.
            #
            # Do not reach for this on a fixed bitstream.
            self.start()
        try:
            self._load_body(img, verify=verify, zero=zero)
        finally:
            if legacy_axi_reset:
                self.halt()

    def _load_body(self, img: "_image.Image", *, verify: bool,
                   zero: bool) -> None:
        size = self.mem_kb * 1024
        if zero:
            # Block RAM comes up zeroed in the bitstream, so the first run
            # after programming is clean -- but the second starts on the
            # first's memory, which is a fine way to spend an afternoon on a
            # bug that only appears on re-runs.
            self.mem.fill(0, size, 0)

        for seg in img.segments:
            self.mem.write_bytes(seg.paddr - R.EXT_MEM_BASE, seg.data)

        if verify:
            for seg in img.segments:
                off = seg.paddr - R.EXT_MEM_BASE
                got = self.mem.read_bytes(off, len(seg.data))
                if got != seg.data:
                    bad = next(i for i, (a, b) in enumerate(zip(got, seg.data))
                               if a != b)
                    raise AmoebaError(
                        f"image readback differs at 0x{seg.paddr + bad:08x}: "
                        f"wrote 0x{seg.data[bad]:02x}, read 0x{got[bad]:02x}")

    # ---- console ----------------------------------------------------------
    def read_console(self, limit: int = 4096) -> bytes:
        """Drain the console FIFO.

        UART_LEVEL first so an empty FIFO costs one register read rather than
        one per poll -- this gets called in a tight loop.
        """
        n = min(self.ctl.read(R.R_UART_LEVEL), limit)
        out = bytearray()
        for _ in range(n):
            w = self.ctl.read(R.R_UART_DATA)      # reading pops
            if not (w & R.UART_VALID):
                break
            out.append(w & R.UART_BYTE)
        return bytes(out)

    # ---- counters ---------------------------------------------------------
    def _read64(self, lo: int, hi: int) -> int:
        """LO first, always.

        Reading LO latches the high half into a shadow that the HI read
        returns.  Without that, a carry landing between the two reads yields a
        value that never existed.
        """
        low = self.ctl.read(lo)
        return (self.ctl.read(hi) << 32) | low

    @property
    def cycles(self) -> int:
        return self._read64(R.R_CYCLES_LO, R.R_CYCLES_HI)

    @property
    def retired(self) -> int:
        return self._read64(R.R_RETIRED_LO, R.R_RETIRED_HI)

    @property
    def traps(self) -> int:
        return self.ctl.read(R.R_TRAPS)

    @property
    def status(self) -> int:
        return self.ctl.read(R.R_STATUS)

    @property
    def tohost_valid(self) -> bool:
        return bool(self.status & R.ST_TOHOST_VALID)

    @property
    def tohost(self) -> int:
        return self._read64(R.R_TOHOST_LO, R.R_TOHOST_HI)

    @property
    def exit_code(self) -> int:
        """HTIF encodes exit as (code << 1) | 1."""
        return self.tohost >> 1

    @property
    def uart_overflow(self) -> bool:
        return bool(self.status & R.ST_UART_OVERFLOW)

    # ---- orchestration ----------------------------------------------------
    def run(self, img: "_image.Image", *, trace_mode: int = R.TRACE_OFF,
            **load_kw) -> None:
        """Halt, load, clear, release -- in that order, which is the point."""
        self.halt()
        self.load(img, **load_kw)
        if self.has_trace:
            self.ctl.write(R.R_TRACE_MODE, trace_mode)
        self.clear_monitors()
        self.start()

    def stream_console(self, timeout: float, *,
                       until_tohost: bool = True,
                       poll: float = 0.002) -> Iterator[bytes]:
        """Yield console bytes until tohost, timeout, or KeyboardInterrupt.

        Drains once more after tohost fires: the exit write and the last
        characters of output race each other through different paths, and
        stopping on the flag alone reliably truncates the final line.
        """
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            chunk = self.read_console()
            if chunk:
                yield chunk
                continue
            if until_tohost and self.tohost_valid:
                break
            time.sleep(poll)
        tail = self.read_console()
        if tail:
            yield tail
