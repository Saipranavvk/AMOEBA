"""Program images: ELF64 or flat binary, reduced to what the loader needs.

Deliberately dependency-free.  A PYNQ image does not ship pyelftools, and
``pip install`` on a board that may not have a network is a bad first step in a
bring-up procedure.  ELF64/little-endian/RISC-V is all this has to read, and
that is about eighty lines.

The symbol table is parsed for one reason: ``tohost``.  The program's linker
script and the PL's bus monitor must agree on that address, and if they drift
the run prints correct console output and then hangs forever waiting for an exit
the monitor never saw.  Reading it here turns that into a check at load time.
"""

import struct
from typing import List, NamedTuple, Optional

PT_LOAD = 1
SHT_SYMTAB = 2
EM_RISCV = 0xF3


class Segment(NamedTuple):
    paddr: int
    data: bytes
    memsz: int          # >= len(data); the excess is .bss, zeroed by crt0


class Image(NamedTuple):
    entry: int
    segments: List[Segment]
    symbols: dict
    path: str

    @property
    def load_base(self) -> int:
        return min(s.paddr for s in self.segments)

    @property
    def load_end(self) -> int:
        """Highest address the program will touch, including .bss."""
        return max(s.paddr + s.memsz for s in self.segments)

    @property
    def file_bytes(self) -> int:
        return sum(len(s.data) for s in self.segments)

    def tohost(self) -> Optional[int]:
        return self.symbols.get("tohost")


def load(path: str, base: Optional[int] = None) -> Image:
    """Read an ELF, or a flat binary if `base` is given."""
    with open(path, "rb") as fh:
        blob = fh.read()

    if blob[:4] != b"\x7fELF":
        if base is None:
            raise ValueError(
                f"{path} is not an ELF and no load address was given; "
                "pass base= for a flat binary"
            )
        return Image(entry=base, segments=[Segment(base, blob, len(blob))],
                     symbols={}, path=path)

    if blob[4] != 2 or blob[5] != 1:
        raise ValueError(f"{path}: expected 64-bit little-endian ELF")
    machine = struct.unpack_from("<H", blob, 0x12)[0]
    if machine != EM_RISCV:
        raise ValueError(f"{path}: e_machine is 0x{machine:x}, expected RISC-V")

    entry, phoff, shoff = struct.unpack_from("<QQQ", blob, 0x18)
    phentsize, phnum = struct.unpack_from("<HH", blob, 0x36)
    shentsize, shnum = struct.unpack_from("<HH", blob, 0x3A)

    segments = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type = struct.unpack_from("<I", blob, off)[0]
        if p_type != PT_LOAD:
            continue
        p_offset, _p_vaddr, p_paddr, p_filesz, p_memsz = struct.unpack_from(
            "<QQQQQ", blob, off + 0x08)
        if p_memsz == 0:
            continue
        # p_paddr, not p_vaddr: this is a physical load, with no MMU in the
        # picture yet.  They are equal for every image in this project, but
        # being explicit costs nothing and documents the intent.
        segments.append(Segment(p_paddr, blob[p_offset:p_offset + p_filesz], p_memsz))

    if not segments:
        raise ValueError(f"{path}: no PT_LOAD segments")

    symbols = _symbols(blob, shoff, shentsize, shnum)
    return Image(entry=entry, segments=segments, symbols=symbols, path=path)


def _symbols(blob: bytes, shoff: int, shentsize: int, shnum: int) -> dict:
    out = {}
    for i in range(shnum):
        off = shoff + i * shentsize
        sh_type = struct.unpack_from("<I", blob, off + 0x04)[0]
        if sh_type != SHT_SYMTAB:
            continue
        sh_offset, sh_size = struct.unpack_from("<QQ", blob, off + 0x18)
        sh_link = struct.unpack_from("<I", blob, off + 0x28)[0]
        sh_entsize = struct.unpack_from("<Q", blob, off + 0x38)[0]
        if sh_entsize == 0:
            continue

        str_off, str_size = struct.unpack_from(
            "<QQ", blob, shoff + sh_link * shentsize + 0x18)
        strtab = blob[str_off:str_off + str_size]

        for s in range(sh_size // sh_entsize):
            so = sh_offset + s * sh_entsize
            st_name = struct.unpack_from("<I", blob, so)[0]
            st_value = struct.unpack_from("<Q", blob, so + 0x08)[0]
            if st_name == 0:
                continue
            end = strtab.find(b"\0", st_name)
            name = strtab[st_name:end].decode("ascii", "replace")
            if name:
                out[name] = st_value
    return out
