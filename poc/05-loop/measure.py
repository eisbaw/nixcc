#!/usr/bin/env python3
"""What the closed loop costs to evaluate, in memory and in CPU.

Memory is the binding constraint on this whole project (decision-001): the
image is a BYTE LIST, the emulator's RAM is an attrset with one entry per
written byte, and every register write rebuilds a 32-element list. The lexer
measured about 4 kB of peak RSS per token, the matcher about 9.5 kB per DAG
node and the assembler about 8.6-9.4 kB per item. This reports the closed
loop's own figure -- kB of peak RSS per emulated instruction -- and holds it
to a ceiling, because a compiler that can only run seven-hundred-instruction
programs is not one. It is an UPPER bound on the execution stage: the net
figure also carries LEXING AND PARSING hello.c, selecting the instructions and
assembling them, and this PoC has no ladder to separate them. The front end
joined that list when task-028 made the demo start from the .c rather than
from lcc's listing, and it moved the reading: this file recorded 44 kB per
instruction before that and measures 53 kB after, against a ceiling of 70.
Both are single readings on one machine, so read the ceiling and not the gap.

There is no timing ladder here and so no contention guard: a ceiling on peak
RSS is not a comparison between two measurements, and a busy machine does not
move it the way it moves a ratio. The contention figure is printed anyway, so
that a reading taken on a loaded machine does not log identically to one taken
on an idle one.

    measure.py POC_DIR
"""
import os
import pathlib
import shutil
import sys

# The guard is a sibling directory, so it has to be put on the path before it
# can be imported -- and a missing one has to be a HARNESS FAULT rather than
# the exit 1 Python would give.
sys.path.append(str(pathlib.Path(__file__).resolve().parent.parent / "lib"))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e}); "
          f"poc/lib must sit beside this harness")
    sys.exit(2)

REPEATS = 3
# Net of the evaluator's own start-up, which is measured rather than assumed.
# The demo executes ~700 instructions and measures about 53 kB of peak RSS for
# each of them -- the figure recorded here was 44 kB before the front end moved
# inside the evaluation (task-028); the ceiling is set above that with room for
# the evaluator to change. An assertion rather than a report: this is the number that decides
# whether a real program can be run inside an evaluation at all.
MAX_KB_PER_STEP = 70.0
MAX_RSS_KB = 512 * 1024
MIN_STEPS = 100
fault = contention.fault


def main(argv):
    if len(argv) != 1:
        fault("usage: measure.py POC_DIR")
    poc = pathlib.Path(argv[0]).resolve()

    nix = shutil.which("nix")
    if nix is None:
        fault("no `nix' on PATH -- run this inside nix develop")
    riscv = os.environ.get("NIX_RISCV")
    if not riscv:
        fault("NIX_RISCV is unset -- run this inside nix develop")

    expr = (f'let cpu = import (/. + "{riscv}/rv32.nix"); '
            f'd = import {poc}/demo.nix {{ inherit cpu; }}; '
            f'in toString d.report.steps')

    # Round-robin, like the three linearity ladders, even though nothing here
    # is a ratio between two sizes: the baseline is still subtracted from the
    # measurement, and interleaving is what makes the two comparable.
    measured = contention.rounds(
        [contention.baseline_argv(nix),
         [nix, "eval", "--impure", "--raw", "--expr", expr]], REPEATS)
    base, run = measured.points

    steps = int(run.out.strip())
    if steps < MIN_STEPS:
        fault(f"the demo reported {steps} executed instructions; "
              f"this is measuring an evaluation that ran nothing")

    net_rss = run.rss - base.rss
    net_cpu = run.cpu - base.cpu
    per_step = net_rss / steps

    print(f"machine: {contention.cores()} cores; other work occupied up to "
          f"{contention.busiest(measured):.2f} of them while measuring "
          f"(no verdict here depends on that)")
    print(f"  evaluator baseline: {base.cpu:.2f} s CPU, {base.rss / 1024:.0f} MB peak RSS")
    print(f"  closed loop:        {run.cpu:.2f} s CPU, {run.rss / 1024:.0f} MB peak RSS, "
          f"{steps} RV32I instructions executed")
    print(f"  net of the baseline: {net_cpu:.2f} s CPU and {net_rss / 1024:.0f} MB, "
          f"which is at most {per_step:.1f} kB per emulated instruction -- at most, because "
          f"the same figure also carries lexing and parsing the C, selecting the "
          f"instructions and assembling them")

    if run.rss > MAX_RSS_KB:
        sys.exit(f"the closed loop peaked at {run.rss / 1024:.0f} MB, over the "
                 f"{MAX_RSS_KB / 1024:.0f} MB ceiling")
    if per_step > MAX_KB_PER_STEP:
        sys.exit(f"the closed loop costs {per_step:.1f} kB of peak RSS per emulated "
                 f"instruction, over the {MAX_KB_PER_STEP:.1f} kB ceiling; at this rate "
                 f"a program of any size will not evaluate")


if __name__ == "__main__":
    main(sys.argv[1:])
