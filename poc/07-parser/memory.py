#!/usr/bin/env python3
"""What this frontend costs to evaluate, per source line, with everything live.

Criterion #5 of task-027, and it asks for the figure with "tokens/AST/DAG live
simultaneously" rather than for the cheapest number available. That is what
compile.nix's `census' forces: there is no arena to free here, so at the end of
a translation unit the token list, every tree, every dag node, every symbol and
the rendered listing are all still reachable. The final state IS the peak.

WHY THIS IS THE NUMBER THAT MATTERS. decision-001 and decision-007 both say
memory is the binding constraint on this project, not speed: the lexer measured
about 4 kB of peak RSS per token, the matcher about 9.5 kB per dag node, the
assembler about 8.6-9.4 kB per item, and a stage that holds all of those at once
multiplies them. A frontend that cannot evaluate a thousand-line file inside a
`nix eval' is not a frontend, however clean its IR diff is.

TWO QUADRATIC ACCUMULATORS WERE FOUND BY THIS MEASUREMENT and are recorded here
because the numbers would otherwise read as inherent:

  * The symbol, tree and node tables were one flat attrset each, updated with
    `//'. That copies every existing binding per insert. Measured flat:
    62/101/224/574 MB at 104/208/416/832 source lines -- 2.5x memory for 2x the
    input. store.nix chunks them.
  * The listing accumulated one line at a time into `out'. Measured at 1664
    lines it was worth about 75 MB on its own. listing.nix buffers per
    function and concatenates once.

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
# Function counts for the synthetic translation unit; cases.nix says what one
# function looks like and how many lines it is.
SIZES = [8, 32, 128]
# The ceiling, per source line of C, net of the evaluator's own start-up.
# Measured at 161-178 kB across the ladder; the ceiling leaves room for the
# evaluator to change without leaving room for a quadratic to hide.
MAX_KB_PER_LINE = 260.0
# And an absolute one, because "per line" stays flattering while the total goes
# somewhere a machine cannot follow.
MAX_RSS_KB = 768 * 1024
MIN_LINES = 100

fault = contention.fault


def main(argv):
    if len(argv) != 1:
        fault("usage: memory.py POC_DIR")
    poc = pathlib.Path(argv[0]).resolve()

    nix = shutil.which("nix")
    if nix is None:
        fault("no `nix' on PATH -- run this inside nix develop")

    def expr(n):
        return (f'let c = import {poc}/compile.nix; '
                f'cs = import {poc}/cases.nix; '
                f'r = c.census (cs.synthetic {n}); in '
                f'"${{toString r.lines}} ${{toString r.tokens}} '
                f'${{toString r.trees}} ${{toString r.nodes}} ${{toString r.symbols}}"')

    argvs = [contention.baseline_argv(nix)]
    argvs += [[nix, "eval", "--impure", "--raw", "--expr", expr(n)] for n in SIZES]

    # Round-robin, as decision-008 requires of anything that subtracts one
    # reading from another on this machine.
    measured = contention.rounds(argvs, REPEATS)
    base = measured.points[0]
    runs = measured.points[1:]

    print(f"machine: {contention.cores()} cores; other work occupied up to "
          f"{contention.busiest(measured):.2f} of them while measuring "
          f"(no verdict here depends on that)")
    print(f"  evaluator baseline: {base.rss / 1024:.0f} MB peak RSS")

    worst = 0.0
    for n, point in zip(SIZES, runs):
        fields = point.out.split()
        if len(fields) != 5:
            fault(f"the census for {n} functions returned {point.out!r}, which is "
                  f"not the five counts it should be; this is measuring something "
                  f"other than a compiled translation unit")
        lines, tokens, trees, nodes, symbols = (int(x) for x in fields)
        if lines < MIN_LINES and n == max(SIZES):
            fault(f"the largest point compiled {lines} source lines; this is "
                  f"measuring an evaluation that compiled nothing")
        net = point.rss - base.rss
        per_line = net / lines
        worst = max(worst, per_line)
        print(f"  {lines:5d} lines: {point.rss / 1024:4.0f} MB peak RSS, "
              f"{net / 1024:4.0f} MB net, {per_line:.0f} kB per source line, with "
              f"{tokens} tokens, {trees} trees, {nodes} dag nodes and {symbols} "
              f"symbols live at once")
        if point.rss > MAX_RSS_KB:
            sys.exit(f"compiling {lines} lines peaked at {point.rss / 1024:.0f} MB, "
                     f"over the {MAX_RSS_KB / 1024:.0f} MB ceiling")

    print(f"  at most {worst:.0f} kB of peak RSS per source line, under the "
          f"{MAX_KB_PER_LINE:.0f} kB ceiling")
    if worst > MAX_KB_PER_LINE:
        sys.exit(f"the frontend costs {worst:.0f} kB of peak RSS per source line, "
                 f"over the {MAX_KB_PER_LINE:.0f} kB ceiling; at this rate a real "
                 f"translation unit will not evaluate")


if __name__ == "__main__":
    main(sys.argv[1:])
