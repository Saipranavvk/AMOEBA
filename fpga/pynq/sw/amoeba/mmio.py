"""Minimal memory-mapped register access.

One implementation over /dev/mem rather than a pynq backend and a fallback.
PYNQ's own MMIO is a /dev/mem mapping underneath, so a second path would buy
nothing but a second thing that can be subtly different -- and this way the
driver also runs on a plain Zynq Linux with no PYNQ installed.  pynq is used
only to download the bitstream, and only if it is there.

Everything is 32-bit word access.  The control block and the image window are
both AXI4-Lite slaves, and while they do honour byte strobes, letting Python's
buffer machinery choose an access width for a device mapping is the sort of
thing that works on one kernel and not the next.
"""

import mmap
import os
import struct

PAGE = mmap.PAGESIZE


class Mmio:
    def __init__(self, base: int, length: int):
        if base % 4:
            raise ValueError("base must be word-aligned")
        self.base = base
        self.length = length

        page_base = base & ~(PAGE - 1)
        self._delta = base - page_base
        span = ((self._delta + length + PAGE - 1) // PAGE) * PAGE

        self._fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        try:
            self._map = mmap.mmap(self._fd, span, mmap.MAP_SHARED,
                                  mmap.PROT_READ | mmap.PROT_WRITE,
                                  offset=page_base)
        except Exception:
            os.close(self._fd)
            raise

    # ---- single word ------------------------------------------------------
    def read(self, offset: int) -> int:
        self._check(offset, 4)
        return struct.unpack_from("<I", self._map, self._delta + offset)[0]

    def write(self, offset: int, value: int) -> None:
        self._check(offset, 4)
        struct.pack_into("<I", self._map, self._delta + offset, value & 0xFFFFFFFF)

    # ---- bulk -------------------------------------------------------------
    def write_bytes(self, offset: int, data: bytes) -> None:
        """Word-at-a-time, zero-padded to a word boundary.

        The pad matters: a program image whose last section does not end on a
        4-byte boundary would otherwise leave the final bytes unwritten, and the
        symptom is a corrupt tail rather than an error.
        """
        self._check(offset, len(data))
        pad = (-len(data)) % 4
        if pad:
            data = data + b"\x00" * pad
        for i in range(0, len(data), 4):
            struct.pack_into("<I", self._map, self._delta + offset + i,
                             struct.unpack_from("<I", data, i)[0])

    def read_bytes(self, offset: int, length: int) -> bytes:
        self._check(offset, length)
        out = bytearray()
        for i in range(0, ((length + 3) // 4) * 4, 4):
            out += struct.pack("<I", self.read(offset + i))
        return bytes(out[:length])

    def fill(self, offset: int, length: int, value: int = 0) -> None:
        self._check(offset, length)
        for i in range(0, ((length + 3) // 4) * 4, 4):
            self.write(offset + i, value)

    # ---- housekeeping -----------------------------------------------------
    def _check(self, offset: int, length: int) -> None:
        if offset < 0 or offset + length > self.length:
            raise IndexError(
                f"access at +0x{offset:x}[{length}] is outside the "
                f"0x{self.length:x}-byte window at 0x{self.base:08x}")

    def close(self) -> None:
        try:
            self._map.close()
        finally:
            os.close(self._fd)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


def download_bitstream(path: str) -> None:
    """Deprecated shim.  Use amoeba.pl.program(), which also sets FCLK0.

    Kept because programming without setting the clock is exactly the bug this
    module used to have, and a caller still reaching for this name should get
    the fixed behaviour rather than the old one.
    """
    from .pl import program
    program(path)
