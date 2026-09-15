#!/usr/bin/env python3
"""Generate a .s file of BLOCKS blocks for the scale ladder.

  ladder.py BLOCKS OUTPUT.s

Generated rather than taken from a corpus because there is no corpus of large
assembly files here yet: poc/03-matcher's functions are tens of instructions,
and a ladder has to span 6x over thousands to say anything about linearity.

Each block carries one backward branch, one forward branch, a load, a store
and an `li' whose value cycles through both the one-instruction and the
two-instruction expansions -- so the ladder measures variable-length placement
and symbol resolution, not just a run of identical words. Branch distances stay
inside a block, which keeps every one of them in range at any ladder size.
"""
import sys


def block(i):
    # A value that lands on both sides of the 12-bit boundary as i advances,
    # so the ladder never degenerates into one `li' shape.
    value = (i * 7919) % 0x100000000 - 0x80000000
    return [
        f".Lb_{i}:",
        f"\taddi\ta0,a0,{i % 2000 - 1000}",
        f"\tlw\ta1,{-(i % 500) * 4}(s0)",
        f"\tbeq\ta0,a1,.Lb_{i}",
        f"\tli\ta2,{value}",
        f"\tsw\ta2,{(i % 500) * 4}(sp)",
        f"\tbne\ta0,a2,.Lf_{i}",
        "\tadd\ta0,a1,a2",
        f".Lf_{i}:",
        "\txor\ta3,a0,a1",
    ]


def main(argv):
    if len(argv) != 2:
        sys.exit("usage: ladder.py BLOCKS OUTPUT.s")
    blocks = int(argv[0])
    if blocks < 1:
        sys.exit("ladder.py: BLOCKS must be at least 1")
    lines = ["\t.text", "\t.globl _start", "_start:"]
    for i in range(blocks):
        lines += block(i)
    lines.append("\tret")
    with open(argv[1], "w") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
