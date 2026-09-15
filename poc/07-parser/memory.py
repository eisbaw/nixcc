#!/usr/bin/env python3
"""What this frontend costs to evaluate, per source line, with everything live.

Criterion #5 of task-027, and it asks for the figure with "tokens/AST/DAG live
simultaneously" rather than for the cheapest number available.

TWO LADDERS, NOT ONE, and the difference between them is the point. funcdefn
releases a finished function's trees and dag nodes -- lcc frees its FUNC arena
at the same place -- so a translation unit of MANY SMALL functions peaks far
below one whose peak is a SINGLE LARGE function. Measuring only the first
reports a per-line figure the second does not obey: 143 kB against 336 kB, a
factor of 2.3. The ceiling below is the larger shape's, because that is the
one a real file can hit.

WHY THIS IS THE NUMBER THAT MATTERS. decision-001 and decision-007 both say
memory is the binding constraint on this project, not speed: the lexer measured
about 4 kB of peak RSS per token, the matcher about 9.5 kB per dag node, the
assembler about 8.6-9.4 kB per item, and a stage that holds all of those at
once multiplies them. A frontend that cannot evaluate a thousand-line file
inside a `nix eval' is not a frontend, however clean its IR diff is.

WHAT THIS MEASUREMENT FOUND, recorded because the numbers would otherwise read
as inherent:

  * The symbol, tree and node tables were one flat attrset each, updated with
    `//'. That copies every existing binding per insert. Measured flat:
    62/101/224/574 MB at 104/208/416/832 source lines -- 2.5x memory for 2x the
    input. store.nix chunks them.
  * The listing accumulated one line at a time into `out'. At 1664 lines it was
    worth about 75 MB on its own. listing.nix buffers per function.
  * A finished function's trees and dag nodes were never released: 763 MB
    against 472 MB for a hundred functions, 38% of peak for one line.
  * sym.reachable built and filtered a full index of the code list on every
    code() call, where lcc walks back from the tail and stops at the first
    item. On a 1600-statement function it was the largest single term.

There is no TIMING ladder here and so no contention self-test: a ceiling on
peak RSS is not a comparison between two measurements, and a busy machine does
not move it the way decision-008 says it moves a ratio. The contention figure
is printed anyway so that a reading taken on a loaded machine does not log
identically to one taken on an idle one.

    memory.py POC_DIR
"""
import pathlib
import shutil
import sys

sys.path.append(str(pathlib.Path(__file__).resolve().parent.parent / "lib"))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e}); "
          f"poc/lib must sit beside this harness")
    sys.exit(2)

REPEATS = 3
# (label, cases.nix function, argument). `synthetic' is n functions of ten
# lines; `syntheticOne' is ONE function of n statement pairs.
LADDER = [
    ("many functions", "synthetic", 8),
    ("many functions", "synthetic", 32),
    ("many functions", "synthetic", 128),
    ("one function", "syntheticOne", 200),
    ("one function", "syntheticOne", 600),
    ("one function", "syntheticOne", 1200),
]
# Per source line of C, net of the evaluator's own start-up. Measured at
# 130-145 kB for the many-function shape and 330-350 kB for the one-function
# shape; the ceiling is the larger one's, with room for the evaluator to change
# and not enough for a quadratic to hide in.
MAX_KB_PER_LINE = 430.0
# And an absolute one, because "per line" stays flattering while the total goes
# somewhere a machine cannot follow.
MAX_RSS_KB = 1024 * 1024
MIN_LINES = 100

fault = contention.fault


def main(argv):
    if len(argv) != 1:
        fault("usage: memory.py POC_DIR")
    poc = pathlib.Path(argv[0]).resolve()

    nix = shutil.which("nix")
    if nix is None:
        fault("no `nix' on PATH -- run this inside nix develop")

    def expr(fn, n):
        return (f'let c = import {poc}/compile.nix; '
                f'cs = import {poc}/cases.nix; '
                f'r = c.census (cs.{fn} {n}); in '
                f'"${{toString r.lines}} ${{toString r.tokens}} '
                f'${{toString r.treesBuilt}} ${{toString r.nodesBuilt}} '
                f'${{toString r.symbols}}"')

    argvs = [contention.baseline_argv(nix)]
    argvs += [[nix, "eval", "--impure", "--raw", "--expr", expr(fn, n)]
              for _, fn, n in LADDER]

    # Round-robin, as decision-008 requires of anything that subtracts one
    # reading from another on this machine.
    measured = contention.rounds(argvs, REPEATS)
    base = measured.points[0]
    runs = measured.points[1:]
    if len(runs) != len(LADDER):
        fault(f"{len(runs)} points came back for a ladder of {len(LADDER)}; "
              f"this is not measuring what it declares")

    print(f"machine: {contention.cores()} cores; other work occupied up to "
          f"{contention.busiest(measured):.2f} of them while measuring "
          f"(no verdict here depends on that)")
    print(f"  evaluator baseline: {base.rss / 1024:.0f} MB peak RSS")

    worst = 0.0
    biggest = None
    for (label, _fn, _n), point in zip(LADDER, runs):
        fields = point.out.split()
        if len(fields) != 5:
            fault(f"a census returned {point.out!r}, which is not the five "
                  f"counts it should be; this is measuring something other "
                  f"than a compiled translation unit")
        lines, tokens, trees, nodes, symbols = (int(x) for x in fields)
        if lines < MIN_LINES:
            fault(f"a ladder point compiled {lines} source lines; this is "
                  f"measuring an evaluation that compiled nothing")
        net = point.rss - base.rss
        per_line = net / lines
        worst = max(worst, per_line)
        if biggest is None or per_line > biggest[0]:
            biggest = (per_line, lines)
        print(f"  {label:15s} {lines:5d} lines: {point.rss / 1024:5.0f} MB peak RSS, "
              f"{net / 1024:5.0f} MB net, {per_line:3.0f} kB per source line, with "
              f"{tokens} tokens, {trees} trees, {nodes} dag nodes and {symbols} "
              f"symbols built")
        if point.rss > MAX_RSS_KB:
            sys.exit(f"compiling {lines} lines peaked at {point.rss / 1024:.0f} MB, "
                     f"over the {MAX_RSS_KB / 1024:.0f} MB ceiling")

    # The number a reader actually wants: where the wall is. It is a property
    # of the worst SHAPE, not of the largest point measured.
    wall = int((MAX_RSS_KB - base.rss) / worst)
    print(f"  at most {worst:.0f} kB of peak RSS per source line, under the "
          f"{MAX_KB_PER_LINE:.0f} kB ceiling -- so the {MAX_RSS_KB / 1024:.0f} MB "
          f"ceiling is reached at about {wall} source lines in one function")
    if worst > MAX_KB_PER_LINE:
        sys.exit(f"the frontend costs {worst:.0f} kB of peak RSS per source line, "
                 f"over the {MAX_KB_PER_LINE:.0f} kB ceiling; at this rate a real "
                 f"translation unit will not evaluate")


if __name__ == "__main__":
    main(sys.argv[1:])
