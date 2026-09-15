#!/usr/bin/env python3
"""Measure the Nix lexer's throughput across a size ladder and assert linearity.

Linearity is the whole point of the exercise, so it is asserted here rather
than eyeballed: Nix lists have no O(1) cons and `++` copies, so a lexer written
the obvious way is quadratic and would report a throughput number that reads as
"Nix is too slow for this project" when the real answer is accumulator shape
(decision-001).

Two things make the assertion harder rather than easier, deliberately:

  * The evaluator's fixed start-up cost is measured and subtracted. Leaving it
    in inflates the small sizes and makes any implementation look sublinear.
  * Every consecutive step is checked, not just the endpoints, so a curve that
    only bends at the top cannot hide behind a good end-to-end ratio.

Linearity is judged on CPU time, not wall clock. This is not leniency: wall
clock measures how busy the machine is, and this harness runs in a gate that
may share a machine with other builds. Measured under contention, the same
lexer reported a 2.77x time ratio for a 1.86x size step -- a false
"SUPERLINEAR" verdict from an implementation that had not changed. The wall
clock is still reported, and the acceptance limits below are still wall clock,
because that is what a user waits for.

Switching to CPU time narrows the problem but does not remove it. Measured on a
14-core machine with every core saturated, the largest ladder point's CPU time
inflated 3x while the smallest inflated 2.5x -- memory-bandwidth contention
costs a 500 MB working set more than an 82 MB one, and that is real CPU time,
not waiting. So contention is measured around the ladder, and when the machine
was busy this harness renders NO VERDICT at all: not a pass, not a failure.

Nor is CPU time a stable unit on a laptop. This ladder failed intermittently
for four gate runs and was diagnosed four different ways before the cause
turned out to be its own measurement ORDER: measuring the points in size order
measures the largest one last, when the package is hottest and its clock
lowest, every time. poc/lib/contention.py owns the fix -- round-robin rounds,
and a step's cost ratio measured inside a round rather than divided out of two
separately-optimised figures -- and the evidence, and is shared with the
matcher and assembler ladders rather than copied into them.
"""
import pathlib
import shutil
import sys
import traceback

# The guard is a sibling directory, so it has to be put on the path before it
# can be imported -- and a missing one has to be a HARNESS FAULT rather than
# the exit 1 Python would give, because exit 1 here means "the lexer is
# superlinear".
sys.path.append(str(pathlib.Path(__file__).resolve().parent.parent / "lib"))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e}); "
          f"poc/lib must sit beside this harness")
    sys.exit(2)

# Every ladder point is measured this many times, one run each per round. The
# cheapest run is what the table below reports; the VERDICTS come from ratios
# taken inside a round, which is contention.step_ratio()'s business. Rounds
# rather than repeats: see rounds(), and MEASUREMENT ORDER above it.
REPEATS = 3
# A doubling of input may cost at most this much more than a doubling of time.
# Slack for GC timing and scheduler noise; a quadratic lexer misses it by 10x,
# not by 30%.
#
# This number did NOT move when the ladder's intermittent FAIL was fixed, and
# that is the finding rather than an omission. The task that chased it expected
# the top of the ladder to need its own, wider tolerance, on the reading that
# decision-001's "2.2 MB takes 18.3 s where the small-file rate predicts 14.5"
# was showing up at 500 MB. It is not. Measured round-robin over six sessions
# on this machine, the worst adjacent step across the whole ladder came in at
# 1.052, 1.067, 1.058, 1.060, 1.077 and 1.092 -- the largest step is not
# distinguishable from the others, and 1.35 clears the worst of them by 24%.
# What produced the 1.39 and 1.71 readings that failed the gate was the ladder
# measuring its largest point last on a warm machine; with that fixed there is
# no degradation at this working set left to widen a tolerance for. Widening it
# would have hidden a real instrument fault behind a plausible-sounding
# constant, which is the failure this project has now rejected three times.
TOLERANCE = 1.35
# The end-to-end step is the PRODUCT of the four adjacent ones, so holding it to
# the same tolerance makes it far the strictest check here by accident: four
# steps each inside 1.35x can multiply out to 3.3x. It gets its own number,
# chosen from measurement rather than taste -- across ten runs of this ladder
# the end-to-end ratio-of-ratios came in at 0.88 to 1.02 on a quiet machine and
# 1.23 to 1.26 with other builds running. A quadratic lexer would read 13.9x
# here, not 1.3x, so 1.5 still leaves two orders of magnitude of signal. If this
# starts flaking, the number is wrong and wants re-measuring, not raising.
END_TO_END_TOLERANCE = 1.5
# Width of the per-round CPU column: REPEATS values of up to five characters
# (`12.34') plus the slashes between them. Computed rather than written down,
# because at REPEATS = 5 a hardcoded 24 was exactly saturated and the first
# ladder point to cross 10 s CPU would have pushed the table out of line.
ROUNDS_COL = REPEATS * 5 + (REPEATS - 1)
MIN_POINTS = 4
MIN_SPAN = 8.0
# The evaluator's fixed cost is subtracted from every point, so the smallest
# point has to be large enough that the subtraction is a correction and not the
# measurement. Below this it is the baseline being compared, not the lexer.
MIN_BASELINE_RATIO = 3.0
# Peak RSS is the budget decision-001 says to watch. Gated at both ends: the
# acceptance point against the task's limit, the largest point against a
# ceiling a 2x regression would break.
MAX_RSS_KB = 1024 * 1024
# task-002 acceptance: a 1000-line file, under 10 s and under 2 GB.
AC_SECONDS = 10.0
AC_RSS_KB = 2 * 1024 * 1024
# Contention -- how busy the machine may have been for any of this to count as
# a verdict -- is measured and decided in poc/lib/contention.py, threshold and
# all. This file asks it; it does not carry a copy of the number.
fault = contention.fault


def main(argv):
    if len(argv) < 2:
        fault("usage: throughput.py POC_DIR LADDER_FILE...")
    poc = pathlib.Path(argv[0]).resolve()
    files = [pathlib.Path(p).resolve() for p in argv[1:]]
    if len(files) < MIN_POINTS:
        fault(f"only {len(files)} ladder points, at least {MIN_POINTS} are needed")

    nix = shutil.which("nix")
    if nix is None:
        fault("no `nix' on PATH -- run this inside nix develop")
    ladder, base, measured = contention.ladder(nix, poc, files, REPEATS)
    base_wall, base_cpu = base.wall, base.cpu
    quiet = contention.quiet(ladder)

    rows = []
    # strict: a silently truncated zip is how this repo's first harness came to
    # report "48 instructions compared / PASS" having compared nothing.
    for f, point in zip(files, measured, strict=True):
        secs, cpu, rss = point.wall, point.cpu, point.rss
        parts = point.out.split()
        if len(parts) != 2:
            fault(f"bench.nix printed {point.out!r} for {f}, expected two numbers")
        nbytes, ntokens = int(parts[0]), int(parts[1])
        if nbytes != f.stat().st_size:
            fault(f"bench lexed {nbytes} bytes of {f} but the file is {f.stat().st_size}")
        if ntokens < nbytes / 100:
            fault(f"{f} produced only {ntokens} tokens from {nbytes} bytes")
        work = cpu - base_cpu
        # A cliff, not a clamp: if the work is not comfortably bigger than the
        # baseline being subtracted from it, the ratios below are measuring
        # start-up noise. That is a broken measurement, not a slow lexer -- and
        # a busy machine produces the same reading from a sound ladder, so the
        # shared guard says which of the two it is rather than assuming.
        if work < base_cpu * MIN_BASELINE_RATIO:
            contention.too_small(ladder, f"{nbytes} bytes", point, base,
                                 MIN_BASELINE_RATIO, "lexer")
        rows.append({
            "path": f, "lines": sum(1 for _ in f.open("rb")), "bytes": nbytes,
            "tokens": ntokens, "secs": secs, "work": work, "rss": rss,
            "point": point,
        })

    rows.sort(key=lambda r: r["bytes"])
    contention.report(ladder)
    print(f"evaluator start-up baseline: {base_wall:.3f} s wall, "
          f"{base_cpu:.3f} s CPU (subtracted from `lex cpu s'), cheapest of "
          f"{REPEATS} rounds at {'/'.join(f'{c:.3f}' for c in base.costs)}")
    print(f"{'lines':>7} {'bytes':>8} {'tokens':>8} {'wall s':>8} {'lex cpu s':>9} "
          f"{'tokens/s':>9} {'peak RSS':>10} {'per-round cpu s':>{ROUNDS_COL}}")
    for r in rows:
        print(f"{r['lines']:>7} {r['bytes']:>8} {r['tokens']:>8} {r['secs']:>8.2f} "
              f"{r['work']:>9.2f} {r['tokens'] / r['work']:>9.0f} {r['rss'] / 1024:>7.0f} MB "
              f"{'/'.join(f'{c:.2f}' for c in r['point'].costs):>{ROUNDS_COL}}")

    span = rows[-1]["bytes"] / rows[0]["bytes"]
    if span < MIN_SPAN:
        fault(f"the ladder only spans {span:.1f}x, at least {MIN_SPAN}x is needed")
    # The smallest ladder point stands in for the acceptance criterion. Ladder
    # points are whole source files concatenated, never cut mid-comment, so the
    # count overshoots 1000 -- which makes the check stricter, not weaker. This
    # is a fact about the input rather than a verdict on the lexer, so it is
    # asked here, where contention cannot silence it.
    ac = rows[0]
    if ac["lines"] < 1000:
        fault(f"the smallest ladder point is only {ac['lines']} lines; the criterion is 1000")

    bad = []
    steps = [(rows[i], rows[i + 1], TOLERANCE) for i in range(len(rows) - 1)]
    steps.append((rows[0], rows[-1], END_TO_END_TOLERANCE))
    for a, z, tol in steps:
        grew = z["bytes"] / a["bytes"]
        # The ratio is measured within each round and the median taken,
        # rather than divided out of two independently-minimised figures;
        # poc/lib/contention.py's step_ratio() says what that is for. It
        # is why dividing this table's two `cpu s' columns does not
        # reproduce the number below -- the per-round readings it came
        # from are printed beside it.
        slower, spread = contention.step_ratio(
            ladder, base, a["point"], z["point"], "lexer")
        # On a busy machine the ratios are still printed -- they are what was
        # measured -- but they are not turned into a verdict in either
        # direction, and `bad' stays empty so nothing downstream reads one.
        verdict = ("unjudged" if not quiet else
                   "ok" if slower <= grew * tol else "SUPERLINEAR")
        print(f"  {a['bytes']:>8} -> {z['bytes']:>8}: {grew:.2f}x input, "
              f"{slower:.2f}x CPU  {verdict:<12} "
              f"per round {'/'.join(f'{r:.2f}' for r in spread)}")
        if verdict == "SUPERLINEAR":
            bad.append((a["bytes"], z["bytes"], grew, slower))

    print(f"acceptance point: {ac['lines']} lines, {ac['secs']:.2f} s "
          f"(limit {AC_SECONDS}), {ac['rss'] / 1024:.0f} MB peak RSS "
          f"(limit {AC_RSS_KB / 1024:.0f} MB); largest point "
          f"{rows[-1]['rss'] / 1024:.0f} MB (ceiling {MAX_RSS_KB / 1024:.0f} MB)")

    # Peak RSS is a fact about one run rather than a comparison between two, so
    # contention does not bear on it and it is judged whatever the machine was
    # doing. It is also the budget decision-001 closes on, which makes it the
    # last thing that should go quiet because something else was compiling.
    memory = []
    if ac["rss"] > AC_RSS_KB:
        memory.append(f"{ac['lines']} lines peaked at {ac['rss'] / 1024:.0f} MB, "
                      f"over the {AC_RSS_KB / 1024:.0f} MB limit")
    if rows[-1]["rss"] > MAX_RSS_KB:
        memory.append(f"{rows[-1]['bytes']} bytes peaked at "
                      f"{rows[-1]['rss'] / 1024:.0f} MB, over the "
                      f"{MAX_RSS_KB / 1024:.0f} MB ceiling")
    for m in memory:
        print(f"FAIL: {m}")
    if memory:
        sys.exit(contention.EXIT_FAIL)

    # Everything below compares one run against another or against a wall
    # clock, so none of it may be judged on a machine that was busy while
    # measuring. That is the whole point: a pass measured under contention is
    # as untrustworthy as a failure, and the guard this replaced could only
    # ever downgrade a failure.
    contention.require_quiet(ladder, "lexer")

    if bad:
        for a, z, grew, slower in bad:
            print(f"FAIL: {a} -> {z} bytes grew {grew:.2f}x but cost {slower:.2f}x CPU")
        sys.exit(contention.EXIT_FAIL)
    if ac["secs"] > AC_SECONDS:
        print(f"FAIL: {ac['lines']} lines took {ac['secs']:.2f} s, over the {AC_SECONDS} s limit")
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
        # "the lexer is superlinear". It is not; the harness broke.
        traceback.print_exc()
        fault("the throughput ladder crashed -- see the traceback above. This "
              "is not a verdict on the lexer")
