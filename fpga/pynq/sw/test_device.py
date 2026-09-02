#!/usr/bin/env python3
"""Offline tests for the driver.  No board, no /dev/mem, no root.

    python3 test_device.py

These exist because this driver has now broken twice in ways that only showed
up on hardware, after a bitstream download and a password prompt: once a stale
local in a refactor (NameError deep inside load()), once a method called as a
property.  Neither needed an FPGA to catch -- they needed the code to be run at
all.  A fake MMIO makes every path here executable in milliseconds.

What is deliberately NOT tested: anything about whether the RTL is correct.
That is what fpga/pynq/tb/ and the on-board soak are for.  This checks that the
Python does what it says.
"""

import os
import struct
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import image as _image                       # noqa: E402
from amoeba import regs as R                             # noqa: E402
from amoeba.device import Amoeba, AmoebaError            # noqa: E402

MEM_KB = 128


class FakeMem:
    """A byte array behind the Mmio interface."""

    def __init__(self, size):
        self.buf = bytearray(size)
        self.length = size

    def read(self, off):
        return struct.unpack_from("<I", self.buf, off)[0]

    def write(self, off, val):
        struct.pack_into("<I", self.buf, off, val & 0xFFFFFFFF)

    def write_bytes(self, off, data):
        pad = (-len(data)) % 4
        self.buf[off:off + len(data) + pad] = data + b"\x00" * pad

    def read_bytes(self, off, length):
        return bytes(self.buf[off:off + length])

    def fill(self, off, length, value=0):
        b = struct.pack("<I", value) * (length // 4)
        self.buf[off:off + len(b)] = b


class FakeCtl:
    """The control block's observable behaviour, including reset semantics."""

    def __init__(self, mem_kb=MEM_KB, is_bram=True, has_trace=True):
        self.regs = {}
        self.regs[R.R_ID] = R.ID_MAGIC
        self.regs[R.R_VERSION] = 0x0001_0000
        self.regs[R.R_CAPS] = ((mem_kb & 0xFFFF) << 16) \
            | (R_TRACE_BIT if has_trace else 0) | (1 if is_bram else 0)
        self.regs[R.R_CTRL] = R.CTRL_CORE_RESET      # comes out of config held
        self.starts = 0
        self.halts = 0
        self.log = []

    def read(self, off):
        if off == R.R_STATUS:
            in_rst = self.regs[R.R_CTRL] & R.CTRL_CORE_RESET
            return R.ST_CORE_RESET if in_rst else 0
        return self.regs.get(off, 0)

    def write(self, off, val):
        if off == R.R_CTRL:
            was = self.regs[R.R_CTRL] & R.CTRL_CORE_RESET
            now = val & R.CTRL_CORE_RESET
            if was and not now:
                self.starts += 1
                self.log.append("start")
            if now and not was:
                self.halts += 1
                self.log.append("halt")
        self.regs[off] = val


R_TRACE_BIT = 1 << 8


def make_dev(mem_kb=MEM_KB, **kw):
    dev = object.__new__(Amoeba)
    dev.ctl = FakeCtl(mem_kb=mem_kb, **kw)
    dev._mem = FakeMem(mem_kb * 1024)
    return dev


def make_image(base=R.EXT_MEM_BASE, size=4096, tohost=None, memsz=None):
    if tohost is None:
        tohost = R.tohost_addr(MEM_KB, True)
    data = bytes((i * 7 + 3) & 0xFF for i in range(size))
    seg = _image.Segment(paddr=base, data=data,
                         memsz=memsz if memsz is not None else size)
    return _image.Image(entry=base, segments=[seg],
                        symbols={"tohost": tohost}, path="fake.elf")


# ---------------------------------------------------------------- tests ----
FAILED = []
print("driver tests (no hardware)")


def test(fn):
    name = fn.__name__[2:].replace("_", " ")   # strip the leading "t_" only
    try:
        fn()
        print(f"  ok    {name}")
    except Exception as exc:                                  # noqa: BLE001
        FAILED.append(name)
        print(f"  FAIL  {name}: {exc.__class__.__name__}: {exc}")
        traceback.print_exc(limit=3)
    return fn


@test
def t_load_writes_the_image():
    dev, img = make_dev(), make_image(size=1024)
    dev.load(img)
    assert dev._mem.buf[:1024] == img.segments[0].data


@test
def t_load_zeroes_first():
    dev, img = make_dev(), make_image(size=64)
    dev._mem.buf[5000] = 0xAB              # residue from a previous run
    dev.load(img)
    assert dev._mem.buf[5000] == 0, "stale byte survived the zero pass"


@test
def t_load_can_skip_zeroing():
    dev, img = make_dev(), make_image(size=64)
    dev._mem.buf[5000] = 0xAB
    dev.load(img, zero=False)
    assert dev._mem.buf[5000] == 0xAB


@test
def t_verify_catches_corruption():
    dev, img = make_dev(), make_image(size=256)
    real = dev._mem.write_bytes

    def flaky(off, data):
        real(off, data)
        dev._mem.buf[off + 10] ^= 0xFF     # a bit rots on the way in
    dev._mem.write_bytes = flaky
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "readback differs" in str(exc), exc
        return
    raise AssertionError("corruption was not detected")


@test
def t_refuses_oversized_image():
    dev = make_dev()
    img = make_image(size=64, memsz=MEM_KB * 1024 + 8)
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "outside" in str(exc), exc
        return
    raise AssertionError("oversized image was accepted")


@test
def t_refuses_tohost_mismatch():
    dev = make_dev()
    img = make_image(size=64, tohost=0x8080_0000)
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "tohost" in str(exc), exc
        return
    raise AssertionError("tohost mismatch was accepted")


@test
def t_refuses_to_load_while_running():
    dev, img = make_dev(), make_image(size=64)
    dev.start()
    try:
        dev.load(img)
    except AmoebaError as exc:
        assert "running" in str(exc), exc
        return
    raise AssertionError("load while running was accepted")


@test
def t_legacy_workaround_releases_then_rehalts():
    dev, img = make_dev(), make_image(size=64)
    dev.load(img, legacy_axi_reset=True)
    assert dev.ctl.log == ["start", "halt"], dev.ctl.log
    assert dev.in_reset, "core left running after a legacy load"


@test
def t_legacy_workaround_rehalts_even_on_error():
    dev = make_dev()
    img = make_image(size=64, tohost=0x8080_0000)   # fails the tohost check
    try:
        dev.load(img, legacy_axi_reset=True)
    except AmoebaError:
        pass
    # The check runs before the release, so the core must never have started.
    assert dev.ctl.log == [], dev.ctl.log
    assert dev.in_reset


@test
def t_run_orders_halt_load_start():
    dev, img = make_dev(), make_image(size=64)
    dev.start()                       # pretend a previous run left it going
    dev.ctl.log.clear()
    dev.run(img)
    assert dev.ctl.log[0] == "halt", dev.ctl.log
    assert dev.ctl.log[-1] == "start", dev.ctl.log
    assert not dev.in_reset


@test
def t_describe_reads_caps():
    dev = make_dev(mem_kb=64, is_bram=False, has_trace=False)
    d = dev.describe()
    assert "64 KiB" in d and "AXI/DDR" in d and "trace=no" in d, d


@test
def t_image_tohost_is_a_method_not_a_property():
    # The API is inconsistent -- load_base/load_end/file_bytes are properties,
    # tohost() is a method -- and calling it wrong yields a TypeError deep in
    # an f-string rather than anything legible.  Pin the shape.
    img = make_image(size=8)
    assert callable(img.tohost)
    assert isinstance(img.tohost(), int)


@test
def t_top_word_of_memory_is_reachable():
    dev = make_dev()
    off = MEM_KB * 1024 - 4
    dev._mem.write(off, 0x5A5A_5A5A)
    assert dev._mem.read(off) == 0x5A5A_5A5A


def main():
    if FAILED:
        print(f"\n{len(FAILED)} failed: {', '.join(FAILED)}")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
