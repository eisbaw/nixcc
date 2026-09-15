"""Compare our assembler's bytes against GNU as + ld for one program.

Its own file rather than a shell one-liner because the comparison is the part
most likely to lie: this project has already shipped a differential test whose
zip() truncated silently, so every way of accidentally comparing nothing is a
hard error here.

  diff.py OURS.json REFERENCE.bin NAME

OURS.json is the flat image our assembler produced; REFERENCE.bin is objcopy's
flat image of the same program linked at the same addresses.
"""

import json
import sys


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: diff.py OURS.json REFERENCE.bin NAME")
    ours_path, ref_path, name = argv[1], argv[2], argv[3]

    with open(ours_path) as fh:
        ours = json.load(fh)
    with open(ref_path, "rb") as fh:
        ref = fh.read()

    if not isinstance(ours, list):
        sys.exit(f"{name}: HARNESS FAULT: {ours_path} is not a list of bytes")
    bad = [b for b in ours if not isinstance(b, int) or b < 0 or b > 255]
    if bad:
        sys.exit(f"{name}: HARNESS FAULT: {len(bad)} value(s) in {ours_path} are not bytes")
    # A zero-length comparison is the failure mode that reads as a pass.
    if len(ours) < 16:
        sys.exit(f"{name}: HARNESS FAULT: we produced only {len(ours)} bytes; nothing to compare")
    if len(ref) < 16:
        sys.exit(f"{name}: HARNESS FAULT: the reference image is {len(ref)} bytes; "
                 "GNU as or ld produced nothing")

    if len(ours) != len(ref):
        sys.exit(f"{name}: we produced {len(ours)} bytes, GNU as/ld produced {len(ref)}")

    mine = bytes(ours)
    if mine == ref:
        print(f"  {name}: {len(ref)} bytes identical to GNU as")
        return

    for i in range(len(ref)):
        if mine[i] != ref[i]:
            lo = i & ~3
            sys.exit(
                f"{name}: differs from GNU as at byte 0x{i:x} "
                f"(word 0x{lo:x}): ours {mine[lo:lo + 4].hex()}, "
                f"GNU as {ref[lo:lo + 4].hex()}")


if __name__ == "__main__":
    main(sys.argv)
