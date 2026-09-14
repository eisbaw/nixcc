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

CPU time and peak RSS come from os.wait4, which reports the child's own
figures, rather than from getrusage(RUSAGE_CHILDREN), which is a running
maximum over every child this process has ever had.

Switching to CPU time narrows the problem but does not remove it. Measured on a
14-core machine with every core saturated, the largest ladder point's CPU time
inflated 3x while the smallest inflated 2.5x -- memory-bandwidth contention
costs a 500 MB working set more than an 82 MB one, and that is real CPU time,
not waiting. So the load average is recorded, and a superlinear verdict reached
on a loaded machine is reported as a measurement failure rather than as a
verdict on the lexer. It still fails; it just does not lie about why. The load
average is a one-minute mean and lags a spike, so this diagnosis catches
sustained load and not a burst -- it is a courtesy, not a guarantee.
"""
import os
import pathlib
import shlex
import shutil
import sys
import time

REPEATS = 3
# A doubling of input may cost at most this much more than a doubling of time.
# Slack for GC timing and scheduler noise; a quadratic lexer misses it by 10x,
# not by 30%.
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
# Above this share of the machine's cores, a superlinear verdict is not
# evidence about the lexer. Measured: see the module docstring.
BUSY_FRACTION = 0.5
AC_RSS_KB = 2 * 1024 * 1024


def loadavg():
    """One-minute load average, or 0.0 where /proc is not available."""
    try:
        with open("/proc/loadavg") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError):
        return 0.0


def fault(msg):
    print(f"HARNESS FAULT: {msg}")
    sys.exit(2)


def run(argv):
    """Run argv, returning (stdout, wall seconds, CPU seconds, peak RSS in KB)."""
    r, w = os.pipe()
    t0 = time.monotonic()
    pid = os.posix_spawn(argv[0], argv, os.environ,
                         file_actions=[(os.POSIX_SPAWN_DUP2, w, 1)])
    os.close(w)
    out = b""
    while chunk := os.read(r, 65536):
        out += chunk
    os.close(r)
    _, status, usage = os.wait4(pid, 0)
    elapsed = time.monotonic() - t0
    code = os.waitstatus_to_exitcode(status)
    if code != 0:
        fault(f"`{shlex.join(argv)}` exited with code {code}")
    return out.decode(), elapsed, usage.ru_utime + usage.ru_stime, usage.ru_maxrss


def best(argv):
    """Cheapest of REPEATS runs, chosen by CPU time. Minimum, not mean: we are
    measuring the algorithm, and noise only ever adds work."""
    return min((run(argv) for _ in range(REPEATS)), key=lambda r: r[2])


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
    cores = os.cpu_count() or 1
    load = loadavg()
    _, base_wall, base_cpu, _ = best([nix, "eval", "--impure", "--raw", "--expr", '""'])

    rows = []
    for f in files:
        out, secs, cpu, rss = best([
            nix, "eval", "--impure", "--raw", "--expr",
            f'import {poc}/bench.nix {{ path = "{f}"; }}',
        ])
        parts = out.split()
        if len(parts) != 2:
            fault(f"bench.nix printed {out!r} for {f}, expected two numbers")
        nbytes, ntokens = int(parts[0]), int(parts[1])
        if nbytes != f.stat().st_size:
            fault(f"bench lexed {nbytes} bytes of {f} but the file is {f.stat().st_size}")
        if ntokens < nbytes / 100:
            fault(f"{f} produced only {ntokens} tokens from {nbytes} bytes")
        work = cpu - base_cpu
        # A cliff, not a clamp: if the work is not comfortably bigger than the
        # baseline being subtracted from it, the ratios below are measuring
        # start-up noise. That is a broken measurement, not a slow lexer.
        if work < base_cpu * MIN_BASELINE_RATIO:
            fault(f"{f} cost {cpu:.3f} s CPU against a {base_cpu:.3f} s baseline; "
                  f"this ladder point is too small to measure")
        rows.append({
            "path": f, "lines": sum(1 for _ in f.open("rb")), "bytes": nbytes,
            "tokens": ntokens, "secs": secs, "work": work, "rss": rss,
        })

    load = max(load, loadavg())
    rows.sort(key=lambda r: r["bytes"])
    print(f"machine: {cores} cores, 1-minute load average {load:.1f}")
    print(f"evaluator start-up baseline: {base_wall:.3f} s wall, "
          f"{base_cpu:.3f} s CPU (subtracted from `lex cpu s')")
    print(f"{'lines':>7} {'bytes':>8} {'tokens':>8} {'wall s':>8} {'lex cpu s':>9} "
          f"{'tokens/s':>9} {'peak RSS':>10}")
    for r in rows:
        print(f"{r['lines']:>7} {r['bytes']:>8} {r['tokens']:>8} {r['secs']:>8.2f} "
              f"{r['work']:>9.2f} {r['tokens'] / r['work']:>9.0f} {r['rss'] / 1024:>7.0f} MB")

    span = rows[-1]["bytes"] / rows[0]["bytes"]
    if span < MIN_SPAN:
        fault(f"the ladder only spans {span:.1f}x, at least {MIN_SPAN}x is needed")

    bad = []
    steps = [(rows[i], rows[i + 1], TOLERANCE) for i in range(len(rows) - 1)]
    steps.append((rows[0], rows[-1], END_TO_END_TOLERANCE))
    for a, z, tol in steps:
        grew = z["bytes"] / a["bytes"]
        slower = z["work"] / a["work"]
        verdict = "ok" if slower <= grew * tol else "SUPERLINEAR"
        print(f"  {a['bytes']:>8} -> {z['bytes']:>8}: {grew:.2f}x input, "
              f"{slower:.2f}x CPU  {verdict}")
        if verdict != "ok":
            bad.append((a["bytes"], z["bytes"], grew, slower))

    # The smallest ladder point stands in for the acceptance criterion. Ladder
    # points are whole source files concatenated, never cut mid-comment, so the
    # count overshoots 1000 -- which makes the check stricter, not weaker.
    ac = rows[0]
    print(f"acceptance point: {ac['lines']} lines, {ac['secs']:.2f} s "
          f"(limit {AC_SECONDS}), {ac['rss'] / 1024:.0f} MB peak RSS "
          f"(limit {AC_RSS_KB / 1024:.0f} MB); largest point "
          f"{rows[-1]['rss'] / 1024:.0f} MB (ceiling {MAX_RSS_KB / 1024:.0f} MB)")

    if bad:
        for a, z, grew, slower in bad:
            print(f"FAIL: {a} -> {z} bytes grew {grew:.2f}x but cost {slower:.2f}x CPU")
        if load > cores * BUSY_FRACTION:
            fault(f"...but the load average was {load:.1f} on {cores} cores. Contention "
                  f"inflates the largest ladder point more than the smallest, so this is "
                  f"not evidence about the lexer. Re-run on an idle machine.")
        sys.exit(1)
    if ac["lines"] < 1000:
        fault(f"the smallest ladder point is only {ac['lines']} lines; the criterion is 1000")
    if ac["secs"] > AC_SECONDS:
        print(f"FAIL: {ac['lines']} lines took {ac['secs']:.2f} s, over the {AC_SECONDS} s limit")
        sys.exit(1)
    if ac["rss"] > AC_RSS_KB:
        print(f"FAIL: {ac['lines']} lines peaked at {ac['rss'] / 1024:.0f} MB, over the limit")
        sys.exit(1)
    if rows[-1]["rss"] > MAX_RSS_KB:
        print(f"FAIL: {rows[-1]['bytes']} bytes peaked at {rows[-1]['rss'] / 1024:.0f} MB, "
              f"over the {MAX_RSS_KB / 1024:.0f} MB ceiling")
        sys.exit(1)
    print(f"PASS: {len(rows)} sizes spanning {span:.1f}x, every step linear within "
          f"{TOLERANCE}x and the whole ladder within {END_TO_END_TOLERANCE}x")


if __name__ == "__main__":
    main(sys.argv[1:])
