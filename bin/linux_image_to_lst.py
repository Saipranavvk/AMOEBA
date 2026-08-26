#!/usr/bin/python3
"""Convert flat binary blobs into the byte-addressed .lst image that
simple_memory_w_mask $readmemh's at reset.

generate_memory_file.py takes an ELF and walks `objdump -h`, which hard-errors
on any section whose VMA or size is not a multiple of the addressability.  The
Linux boot image is not an ELF -- OpenSBI's fw_payload.bin is a flat blob with
the kernel and its built-in initramfs already embedded -- so it goes through
this path instead.

The output format matches generate_memory_file.py exactly: an `@<word-index>`
directive followed by one 64-bit little-endian word per line, most significant
byte first.

Usage:
    linux_image_to_lst.py -o boot.lst fw_payload.bin@0x80000000
    linux_image_to_lst.py -o boot.lst shim.bin@0x80000000 fw.bin@0x80001000
"""

import argparse
import os
import sys

WORD = 8


def parse_blob(spec):
    if "@" not in spec:
        sys.exit(f"error: '{spec}' must be <path>@<load-address>, e.g. boot.bin@0x80000000")
    path, _, addr_s = spec.rpartition("@")
    try:
        addr = int(addr_s, 0)
    except ValueError:
        sys.exit(f"error: '{addr_s}' is not a valid load address")
    if addr % WORD:
        sys.exit(f"error: load address {addr:#x} is not {WORD}-byte aligned")
    if not os.path.isfile(path):
        sys.exit(f"error: no such file: {path}")
    with open(path, "rb") as f:
        return path, addr, f.read()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", required=True, help="destination .lst file")
    ap.add_argument("blobs", nargs="+", metavar="FILE@ADDR",
                    help="flat binary and its physical load address")
    args = ap.parse_args()

    blobs = sorted((parse_blob(b) for b in args.blobs), key=lambda b: b[1])

    # Overlap is always a build mistake -- a shim silently clobbered by the
    # firmware behind it is far cheaper to catch here than in a boot log.
    for (p1, a1, d1), (p2, a2, _) in zip(blobs, blobs[1:]):
        if a1 + len(d1) > a2:
            sys.exit(f"error: {os.path.basename(p1)} ({a1:#x}+{len(d1):#x}) "
                     f"overlaps {os.path.basename(p2)} at {a2:#x}")

    total = 0
    with open(args.output, "w") as out:
        for path, addr, data in blobs:
            # Pad the tail so the final word is complete; $readmemh has no way
            # to express a partial word.
            if len(data) % WORD:
                data += b"\x00" * (WORD - len(data) % WORD)
            out.write(f"@{addr // WORD:08x}\n")
            for i in range(0, len(data), WORD):
                out.write(data[i:i + WORD][::-1].hex() + "\n")
            out.write("\n")
            total += len(data)
            print(f"[INFO]  {os.path.basename(path):<24} {addr:#011x} .. "
                  f"{addr + len(data):#011x}  ({len(data):,} bytes)")

    print(f"[INFO]  Wrote {args.output} ({total // WORD:,} words, {total:,} bytes)")


if __name__ == "__main__":
    main()
