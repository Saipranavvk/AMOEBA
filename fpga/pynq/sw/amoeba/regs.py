"""Register map for the AMOEBA PL design.

These constants have NO compile-time link to the hardware.  The offsets come
from ``localparam logic [7:0] R_*`` in ``rtl/amoeba_ctl.sv`` and the base
addresses from ``amoeba_assign`` calls in ``tcl/bd_pynq.tcl``; nothing but
diligence keeps them in step, and a silent mismatch reads as a dead board.

``check_regs.py`` parses both sources and asserts they agree.  Run it whenever
the RTL changes.
"""

# ---- base addresses, from tcl/bd_pynq.tcl -----------------------------------
CTL_BASE = 0x43C0_0000
CTL_SIZE = 0x1000
MEM_BASE = 0x4400_0000          # image window; size comes from CAPS.mem_kb
DMA_BASE = 0x4040_0000
DMA_SIZE = 0x1_0000

# ---- the core's own view of memory, from pkg/config_baremetal_linux.vh ------
# EXT_MEM_BASE is 0x80000000 in every configuration in this project.  The PS
# needs it to turn a program's load address into an offset in the image window.
EXT_MEM_BASE = 0x8000_0000

# ---- control registers, offsets from CTL_BASE -------------------------------
R_ID = 0x00
R_VERSION = 0x04
R_CAPS = 0x08
R_CTRL = 0x0C
R_STATUS = 0x10
R_UART_DATA = 0x14
R_UART_LEVEL = 0x18
R_CYCLES_LO = 0x20
R_CYCLES_HI = 0x24
R_RETIRED_LO = 0x28
R_RETIRED_HI = 0x2C
R_TRAPS = 0x30
R_TOHOST_LO = 0x34
R_TOHOST_HI = 0x38
R_TRACE_MODE = 0x40
R_TRIG_START_LO = 0x44
R_TRIG_START_HI = 0x48
R_TRIG_COUNT = 0x4C
R_TRIG_PC_LO = 0x50
R_TRIG_PC_HI = 0x54
R_TRACE_STAT = 0x58

ID_MAGIC = 0x414D_4F42          # "AMOB"

# ---- CTRL bits --------------------------------------------------------------
CTRL_CORE_RESET = 1 << 0
CTRL_MON_CLEAR = 1 << 1
CTRL_TRACE_CLEAR = 1 << 2

# ---- STATUS bits ------------------------------------------------------------
ST_CORE_RESET = 1 << 0
ST_UART_VALID = 1 << 1
ST_UART_OVERFLOW = 1 << 2
ST_TOHOST_VALID = 1 << 3
ST_TRACE_OVERFLOW = 1 << 4
ST_TRACE_STALLING = 1 << 5

# ---- UART_DATA --------------------------------------------------------------
UART_VALID = 1 << 8
UART_BYTE = 0xFF

# ---- trace modes, from rtl/amoeba_trace.sv ----------------------------------
TRACE_OFF = 0
TRACE_ALL = 1
TRACE_WINDOW = 2
TRACE_PC_TRIG = 3


def caps_mem_kb(caps: int) -> int:
    """Image memory size in KiB, CAPS[31:16]."""
    return (caps >> 16) & 0xFFFF


def caps_has_trace(caps: int) -> bool:
    """CAPS[8]."""
    return bool(caps & (1 << 8))


def caps_is_bram(caps: int) -> bool:
    """CAPS[0]: 1 = block RAM backend, 0 = AXI/DDR."""
    return bool(caps & 1)


def tohost_addr(mem_kb: int, is_bram: bool) -> int:
    """The address the bus monitor is watching for HTIF writes.

    Must match TOHOST_ADDR in rtl/amoeba_pynq_top.sv and the PROVIDE(tohost)
    in the program's linker script.  In a BRAM build the memory is small and
    amoeba_mem_bram truncates rather than faulting, so an address above the
    array aliases back into it -- the usual 0x80800000 against a 128 KiB array
    lands on offset 0, the reset vector.  Hence the top page of real memory.
    """
    if is_bram:
        return EXT_MEM_BASE + mem_kb * 1024 - 4096
    return 0x8080_0000
