#!/usr/bin/env python3
"""Measure the bottom-up labeller across a size ladder of real lcc DAGs.

Two questions, and only the second one is interesting.

Is it linear? Dynamic programming over a DAG is linear by construction, but in
Nix the accumulator shape decides, not the algorithm (decision-001). The label
table here is a self-referential `listToAttrs` rather than a fold with `//`, so
it should be linear; this asserts it rather than assuming it.

What does it cost in memory? That is the number that will decide whether a real
code generator fits, because decision-001's closing point is that the
evaluator's per-live-value overhead, not asymptotics, is what bit the lexer.
The lexer measured about 4 kB of peak RSS per token. A DAG node carries more --
a cost-and-rule entry per nonterminal it can produce -- so this reports kB per
node and holds it to a ceiling.

Method follows poc/02-lexer/throughput.py, which earned its details the hard
way: linearity is judged on the child's own CPU time rather than the wall
clock, because contention inflates a large working set more than a small one
and produced a false SUPERLINEAR verdict there from an unchanged lexer; the
evaluator's fixed start-up cost is measured and subtracted, because leaving it
in makes every implementation look sublinear; and every adjacent step is
checked, not only the endpoints.

CPU time is not enough on its own -- contention is real CPU time, not waiting
-- so contention is measured around the ladder and no verdict is rendered at
all, in either direction, when the machine was busy. Nor is a CPU second a
stable unit across a ladder measured in size order, which took four gate runs
and four wrong diagnoses to establish. Both the guard and the round-robin
measurement that fixes the second live in poc/lib/contention.py, and are
shared with the lexer and assembler ladders rather than copied into them.
"""
import pathlib
import shutil
import sys
import traceback

# The guard is a sibling directory, so it has to be put on the path before it
# can be imported -- and a missing one has to be a HARNESS FAULT rather than
# the exit 1 Python would give, because exit 1 here means "the labeller is
# superlinear".
sys.path.append(str(pathlib.Path(__file__).resolve().parent.parent / "lib"))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e}); "
          f"poc/lib must sit beside this harness")
    sys.exit(2)

# Min over REPEATS interleaved rounds, not mean: noise only ever adds work.
# Five rather than the lexer ladder's three because these points run in 0.2 to
# 1.7 s, where one unlucky garbage collection is a large fraction of the
# measurement -- with three repeats a 2x step was measured between 1.53x and
# 2.67x CPU across six runs of an unchanged labeller. That spread was taken
# before the rounds were interleaved, so part of it was the machine's clock
# rather than the GC; five is kept because these points are still the shortest
# in the tree and the reading costs little.
REPEATS = 5
# A doubling of input may cost at most this much more than a doubling of CPU.
# Chosen from that spread rather than from taste: the honest steps landed
# between 0.76 and 1.08 times the input ratio, and a QUADRATIC labeller would
# read 2.0 at a 2x step, so 1.45 sits well clear of both. If this starts
# flaking the number wants re-measuring, not raising.
TOLERANCE = 1.45
# The end-to-end step is the product of the adjacent ones, so it gets its own
# slack. A quadratic labeller would miss this by an order of magnitude.
END_TO_END_TOLERANCE = 1.6
# Width of the per-round CPU column: REPEATS values of up to five characters
# (`12.34') plus the slashes between them. Computed rather than written down,
# because at REPEATS = 5 a hardcoded 24 was exactly saturated and the first
# ladder point to cross 10 s CPU would have pushed the table out of line.
ROUNDS_COL = REPEATS * 5 + (REPEATS - 1)
MIN_POINTS = 4
MIN_SPAN = 6.0
MIN_BASELINE_RATIO = 3.0
# The same idea for memory. Without it, a baseline that grew to meet the
# measurement would drive the net figure to zero and make the ceiling below
# unfalsifiable -- a check that cannot fail.
MIN_RSS_RATIO = 1.5
# Peak RSS per DAG node, NET of the evaluator's own footprint -- which is
# subtracted here for the same reason the CPU baseline is. Gross, the smallest
# ladder point reads 16.6 kB/node against the largest point's 9.9, and the
# difference is entirely the ~36 MB nix itself occupies: measured net, every
# point sits at 9.3-9.5. Asserting on the gross figure would mean the check
# fails when nix's own baseline grows, with nothing about the labeller having
# changed. The lexer runs at about 4 kB per token for comparison.
MAX_KB_PER_NODE = 13.0
MAX_RSS_KB = 1024 * 1024
# Contention -- how busy the machine may have been for any of this to count as
# a verdict -- is measured and decided in poc/lib/contention.py, threshold and
# all. This file asks it; it does not carry a copy of the number.
fault = contention.fault


def main(argv):
    if len(argv) < 2:
        fault("usage: scale.py POC_DIR LADDER_FILE...")
    poc = pathlib.Path(argv[0]).resolve()
    files = [pathlib.Path(p).resolve() for p in argv[1:]]
    if len(files) < MIN_POINTS:
        fault(f"only {len(files)} ladder points, at least {MIN_POINTS} are needed")

    nix = shutil.which("nix")
    if nix is None:
        fault("no `nix' on PATH -- run this inside nix develop")
    # Baseline and points measured together, round-robin, for the reason
    # poc/lib/contention.py's MEASUREMENT ORDER section gives: a ladder walked
    # in size order measures its largest point last, on the warmest machine,
    # every time.
    ladder, base, measured = contention.ladder(nix, poc, files, REPEATS)
    base_cpu, base_rss = base.cpu, base.rss
    quiet = contention.quiet(ladder)

    rows = []
    for f, point in zip(files, measured, strict=True):
        secs, cpu, rss = point.wall, point.cpu, point.rss
        parts = point.out.split()
        if len(parts) != 3:
            fault(f"bench.nix printed {point.out!r} for {f}, expected three numbers")
        nbytes, nodes, entries = (int(p) for p in parts)
        if nbytes != f.stat().st_size:
            fault(f"bench read {nbytes} bytes of {f} but the file is {f.stat().st_size}")
        if nodes == 0 or entries == 0:
            fault(f"{f} produced {nodes} nodes and {entries} label entries; nothing was labelled")
        if entries < nodes:
            fault(f"{f} produced {entries} label entries for {nodes} nodes; "
                  f"a labelled node has at least one nonterminal")
        work = cpu - base_cpu
        # A busy machine inflates the baseline, which shrinks `work' and
        # produces this same reading from a sound ladder -- so the shared guard
        # says which of the two it is rather than blaming either on its own.
        if work < base_cpu * MIN_BASELINE_RATIO:
            contention.too_small(ladder, f"{nodes} nodes", point, base,
                                 MIN_BASELINE_RATIO, "labeller")
        if rss < base_rss * MIN_RSS_RATIO:
            fault(f"{f} peaked at {rss / 1024:.0f} MB against a {base_rss / 1024:.0f} MB "
                  f"baseline; subtracting one from the other would not leave a measurement")
        rows.append({"path": f, "bytes": nbytes, "nodes": nodes, "entries": entries,
                     "secs": secs, "work": work, "rss": rss,
                     "net": max(rss - base_rss, 0), "point": point})

    rows.sort(key=lambda r: r["nodes"])
    contention.report(ladder)
    print(f"evaluator start-up baseline: {base_cpu:.3f} s CPU, {base_rss / 1024:.0f} MB RSS "
          f"(both subtracted), cheapest of {REPEATS} rounds at "
          f"{'/'.join(f'{c:.3f}' for c in base.costs)}")
    print(f"{'nodes':>8} {'entries':>8} {'wall s':>8} {'label cpu s':>11} "
          f"{'nodes/s':>9} {'peak RSS':>10} {'kB/node':>8} {'per-round cpu s':>{ROUNDS_COL}}")
    for r in rows:
        print(f"{r['nodes']:>8} {r['entries']:>8} {r['secs']:>8.2f} {r['work']:>11.2f} "
              f"{r['nodes'] / r['work']:>9.0f} {r['rss'] / 1024:>7.0f} MB "
              f"{r['net'] / r['nodes']:>8.1f} "
              f"{'/'.join(f'{c:.2f}' for c in r['point'].costs):>{ROUNDS_COL}}")

    span = rows[-1]["nodes"] / rows[0]["nodes"]
    if span < MIN_SPAN:
        fault(f"the ladder only spans {span:.1f}x, at least {MIN_SPAN}x is needed")

    bad = []
    steps = [(rows[i], rows[i + 1], TOLERANCE) for i in range(len(rows) - 1)]
    steps.append((rows[0], rows[-1], END_TO_END_TOLERANCE))
    for a, z, tol in steps:
        grew = z["nodes"] / a["nodes"]
        # The ratio is measured within each round and the median taken,
        # rather than divided out of two independently-minimised figures;
        # poc/lib/contention.py's step_ratio() says what that is for. It
        # is why dividing this table's two `cpu s' columns does not
        # reproduce the number below -- the per-round readings it came
        # from are printed beside it.
        slower, spread = contention.step_ratio(base, a["point"], z["point"])
        # On a busy machine the ratios are still printed -- they are what was
        # measured -- but they are not turned into a verdict in either
        # direction, and `bad' stays empty so nothing downstream reads one.
        verdict = ("unjudged" if not quiet else
                   "ok" if slower <= grew * tol else "SUPERLINEAR")
        print(f"  {a['nodes']:>7} -> {z['nodes']:>7} nodes: {grew:.2f}x input, "
              f"{slower:.2f}x CPU  {verdict:<12} "
              f"per round {'/'.join(f'{r:.2f}' for r in spread)}")
        if verdict == "SUPERLINEAR":
            bad.append((a["nodes"], z["nodes"], grew, slower))

    worst = max(rows, key=lambda r: r["net"] / r["nodes"])
    print(f"peak memory: {worst['net'] / worst['nodes']:.1f} kB per DAG node net of the "
          f"baseline at {worst['nodes']} nodes (ceiling {MAX_KB_PER_NODE} kB/node, "
          f"{MAX_RSS_KB / 1024:.0f} MB absolute)")

    # Peak RSS is a fact about one run rather than a comparison between two, so
    # contention does not bear on it and it is judged whatever the machine was
    # doing. It is also the number decision-001 says will decide whether a real
    # code generator fits, which makes it the last thing that should go quiet
    # because something else was compiling.
    memory = []
    if worst["net"] / worst["nodes"] > MAX_KB_PER_NODE:
        memory.append(f"{worst['net'] / worst['nodes']:.1f} kB per node is over "
                      f"the {MAX_KB_PER_NODE} kB ceiling")
    if rows[-1]["rss"] > MAX_RSS_KB:
        memory.append(f"the largest point peaked at {rows[-1]['rss'] / 1024:.0f} MB, "
                      f"over the {MAX_RSS_KB / 1024:.0f} MB ceiling")
    for m in memory:
        print(f"FAIL: {m}")
    if memory:
        sys.exit(contention.EXIT_FAIL)

    # Everything below compares one run against another, so none of it may be
    # judged on a machine that was busy while measuring. That is the whole
    # point: a pass measured under contention is as untrustworthy as a failure,
    # and the guard this replaced could only ever downgrade a failure.
    contention.require_quiet(ladder, "labeller")

    if bad:
        for a, z, grew, slower in bad:
            print(f"FAIL: {a} -> {z} nodes grew {grew:.2f}x but cost {slower:.2f}x CPU")
        sys.exit(contention.EXIT_FAIL)
    print(f"PASS: {len(rows)} sizes spanning {span:.1f}x, every step linear within "
          f"{TOLERANCE}x and the whole ladder within {END_TO_END_TOLERANCE}x")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except SystemExit:
        raise
    except BaseException:
        # An uncaught exception exits 1, and exit 1 from this harness means
        # "the labeller is superlinear". It is not; the harness broke.
        traceback.print_exc()
        fault("the scale ladder crashed -- see the traceback above. This is "
              "not a verdict on the labeller")
