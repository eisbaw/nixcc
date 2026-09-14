#!/usr/bin/env python3
"""Compare our Nix RV32I encoding against GNU as.

Shared by run.sh and the flake's `checks.encoder` so there is one comparison,
not two that can drift. Expects a directory holding in.s, ours.txt and a.bin.

The harness is as much on trial as the encoder: an earlier version reported
PASS while comparing nothing, because zip() truncates to the shortest sequence
and the printed count came from len(ours) -- a claim, not a measurement.
"""
import struct
import sys
import pathlib

MIN_CASES = 40


def fault(msg):
    print(f"HARNESS FAULT: {msg}")
    sys.exit(2)


def main(workdir):
    w = pathlib.Path(workdir)
    asm = [l for l in w.joinpath("in.s").read_text().split("\n") if l.strip()]
    ours = w.joinpath("ours.txt").read_text().split()
    theirs = ["%08x" % v for (v,) in struct.iter_unpack("<I", w.joinpath("a.bin").read_bytes())]

    # Guards, ordered by how quietly each failure would otherwise pass.
    if len(ours) < MIN_CASES:
        fault(f"only {len(ours)} cases, expected at least {MIN_CASES} -- did cases.nix shrink?")
    if len(asm) != len(ours):
        fault(f"{len(asm)} asm lines vs {len(ours)} encoded words")
    if len(theirs) > len(ours):          # GNU as pads .text to section alignment
        pad, theirs = theirs[len(ours):], theirs[:len(ours)]
        if any(p != "00000000" for p in pad):
            fault(f"unexpected trailing words from as: {pad}")
    if len(theirs) != len(ours):
        fault(f"as produced {len(theirs)} words but the encoder produced {len(ours)}")

    bad = compared = 0
    for a, o, t in zip(asm, ours, theirs):
        compared += 1
        if o != t:
            print(f"MISMATCH  {a:<28}  ours={o}  as={t}")
            bad += 1

    # Report what was measured, never what was expected.
    if compared != len(ours):
        fault(f"compared {compared} of {len(ours)} cases")
    print(f"{compared} instructions compared against GNU as")
    if bad:
        print(f"FAIL: {bad} mismatch(es)")
        sys.exit(1)
    print("PASS")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
