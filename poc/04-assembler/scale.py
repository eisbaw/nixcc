#!/usr/bin/env python3
"""Measure the assembler across a size ladder of generated .s files.

Two questions, and only the second one is interesting.

Is it linear? Address assignment is one `genericClosure' and resolution is one
`map', which decision-001 says is the linear shape -- but the same decision
also records that accumulator shape, not algorithm, is what decides in Nix, and
a single `++' in the wrong place would make this quadratic while every
correctness test still passed. This asserts it rather than assuming it.

What does it cost in memory? That is the number that decides whether a real
program fits, because an assembler's output is a BYTE LIST and Nix has no byte:
every byte is a live integer value, four of them per instruction, on top of the
items and the placements. The lexer measured about 4 kB of peak RSS per token
and the matcher about 9.5 kB per DAG node; this reports kB per item and holds
it to a ceiling.

Method follows poc/03-matcher/scale.py, which follows poc/02-lexer's, and the
details there were earned the hard way: linearity is judged on the child's own
CPU time rather than the wall clock; the evaluator's fixed start-up cost is
measured and subtracted; every adjacent step is checked and not only the
endpoints; and contention is measured around every point, with NO verdict
rendered in either direction when the machine was busy. That guard lives in
poc/lib/contention.py and is shared rather than copied.
"""
import pathlib
import shutil
import sys
import traceback

# The guard is a sibling directory, so it has to be put on the path before it
# can be imported -- and a missing one has to be a HARNESS FAULT rather than
# the exit 1 Python would give, because exit 1 here means "the assembler is
# superlinear".
sys.path.append(str(pathlib.Path(__file__).resolve().parent.parent / "lib"))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e}); "
          f"poc/lib must sit beside this harness")
    sys.exit(2)

REPEATS = 5
# A doubling of input may cost at most this much more than a doubling of CPU.
# The same number the matcher ladder uses, for the same reason: a QUADRATIC
# assembler reads 2.0 at a 2x step, so 1.45 sits clear of honest noise and of
# the failure being looked for. If this starts flaking it wants re-measuring,
# not raising.
TOLERANCE = 1.45
END_TO_END_TOLERANCE = 1.6
MIN_POINTS = 4
MIN_SPAN = 6.0
MIN_BASELINE_RATIO = 3.0
MIN_RSS_RATIO = 1.5
# Peak RSS per item, NET of the evaluator's own ~36 MB. Measured at 8.6-9.4
# kB/item across the ladder; the ceiling is set above that with room for the
# evaluator to change, and it is an assertion rather than a report because
# memory, not speed, is what decision-001 says will decide whether this scales.
MAX_KB_PER_ITEM = 14.0
MAX_RSS_KB = 1024 * 1024
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
    base = contention.best([nix, "eval", "--impure", "--raw", "--expr", '""'], REPEATS)
    base_cpu, base_rss = base.cpu, base.rss

    rows = []
    for f in files:
        point = contention.best([
            nix, "eval", "--impure", "--raw", "--expr",
            f'import {poc}/bench.nix {{ path = "{f}"; }}',
        ], REPEATS)
        parts = point.out.split()
        if len(parts) != 4:
            fault(f"bench.nix printed {point.out!r} for {f}, expected four numbers")
        nbytes, items, symbols, outbytes = (int(p) for p in parts)
        if nbytes != f.stat().st_size:
            fault(f"bench read {nbytes} bytes of {f} but the file is {f.stat().st_size}")
        if items == 0 or symbols == 0 or outbytes == 0:
            fault(f"{f} produced {items} items, {symbols} symbols and {outbytes} output "
                  f"bytes; nothing was assembled")
        # The generated ladder is every-fourth-item a label or directive at
        # most, so an image smaller than the item count means whole items
        # vanished -- which is what an assembler that dropped what it did not
        # understand would look like, and it would also look fast.
        if outbytes < items:
            fault(f"{f} assembled {items} items into only {outbytes} bytes; "
                  f"items are being dropped rather than assembled")
        work = point.cpu - base_cpu
        if work < base_cpu * MIN_BASELINE_RATIO:
            # Contention inflates the baseline, which shrinks `work' -- so ask
            # the guard first, or a busy machine gets told its ladder points
            # are too small when the truth is that it was busy.
            contention.require_quiet([("baseline", base), (f"{items} items", point)],
                                     "assembler")
            fault(f"{f} cost {point.cpu:.3f} s CPU against a {base_cpu:.3f} s baseline; "
                  f"this ladder point is too small to measure")
        if point.rss < base_rss * MIN_RSS_RATIO:
            fault(f"{f} peaked at {point.rss / 1024:.0f} MB against a "
                  f"{base_rss / 1024:.0f} MB baseline; subtracting one from the other "
                  f"would not leave a measurement")
        rows.append({"path": f, "items": items, "symbols": symbols, "out": outbytes,
                     "secs": point.wall, "work": work, "rss": point.rss,
                     "net": max(point.rss - base_rss, 0), "point": point})

    rows.sort(key=lambda r: r["items"])
    points = [("baseline", base)] + [(f"{r['items']} items", r["point"]) for r in rows]
    quiet = contention.quiet(points)
    contention.report(points)
    print(f"evaluator start-up baseline: {base_cpu:.3f} s CPU, {base_rss / 1024:.0f} MB RSS "
          f"(both subtracted), measured against {base.foreign:.2f} cores of other work")
    print(f"{'items':>8} {'symbols':>8} {'out B':>8} {'wall s':>8} {'asm cpu s':>10} "
          f"{'items/s':>9} {'peak RSS':>11} {'kB/item':>8} {'busy cores':>11}")
    for r in rows:
        print(f"{r['items']:>8} {r['symbols']:>8} {r['out']:>8} {r['secs']:>8.2f} "
              f"{r['work']:>10.2f} {r['items'] / r['work']:>9.0f} "
              f"{r['rss'] / 1024:>8.0f} MB {r['net'] / r['items']:>8.1f} "
              f"{r['point'].foreign:>11.2f}")

    span = rows[-1]["items"] / rows[0]["items"]
    if span < MIN_SPAN:
        fault(f"the ladder only spans {span:.1f}x, at least {MIN_SPAN}x is needed")

    bad = []
    steps = [(rows[i], rows[i + 1], TOLERANCE) for i in range(len(rows) - 1)]
    steps.append((rows[0], rows[-1], END_TO_END_TOLERANCE))
    for a, z, tol in steps:
        grew = z["items"] / a["items"]
        slower = z["work"] / a["work"]
        verdict = ("unjudged" if not quiet else
                   "ok" if slower <= grew * tol else "SUPERLINEAR")
        print(f"  {a['items']:>7} -> {z['items']:>7} items: {grew:.2f}x input, "
              f"{slower:.2f}x CPU  {verdict}")
        if verdict == "SUPERLINEAR":
            bad.append((a["items"], z["items"], grew, slower))

    worst = max(rows, key=lambda r: r["net"] / r["items"])
    print(f"peak memory: {worst['net'] / worst['items']:.1f} kB per item net of the "
          f"baseline at {worst['items']} items (ceiling {MAX_KB_PER_ITEM} kB/item, "
          f"{MAX_RSS_KB / 1024:.0f} MB absolute)")

    # Peak RSS is a fact about one run rather than a comparison between two, so
    # contention does not bear on it and it is judged whatever the machine was
    # doing.
    memory = []
    if worst["net"] / worst["items"] > MAX_KB_PER_ITEM:
        memory.append(f"{worst['net'] / worst['items']:.1f} kB per item is over "
                      f"the {MAX_KB_PER_ITEM} kB ceiling")
    if rows[-1]["rss"] > MAX_RSS_KB:
        memory.append(f"the largest point peaked at {rows[-1]['rss'] / 1024:.0f} MB, "
                      f"over the {MAX_RSS_KB / 1024:.0f} MB ceiling")
    for m in memory:
        print(f"FAIL: {m}")
    if memory:
        sys.exit(contention.EXIT_FAIL)

    # Everything below compares one run against another, so none of it may be
    # judged on a machine that was busy while measuring.
    contention.require_quiet(points, "assembler")

    if bad:
        for a, z, grew, slower in bad:
            print(f"FAIL: {a} -> {z} items grew {grew:.2f}x but cost {slower:.2f}x CPU")
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
        # "the assembler is superlinear". It is not; the harness broke.
        traceback.print_exc()
        fault("the scale ladder crashed -- see the traceback above. This is "
              "not a verdict on the assembler")
