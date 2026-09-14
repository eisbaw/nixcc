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
"""
import os
import pathlib
import shlex
import shutil
import sys
import time

# Min of REPEATS, not mean: noise only ever adds work. Five rather than the
# lexer ladder's three because these points run in 0.2 to 1.7 s, where one
# unlucky garbage collection is a large fraction of the measurement -- with
# three repeats a 2x step was measured between 1.53x and 2.67x CPU across six
# runs of an unchanged labeller.
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
# Above this share of the machine's cores a superlinear verdict is not evidence
# about the labeller.
BUSY_FRACTION = 0.5


def loadavg():
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
    """Cheapest of REPEATS runs by CPU time: noise only ever adds work."""
    return min((run(argv) for _ in range(REPEATS)), key=lambda r: r[2])


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
    cores = os.cpu_count() or 1
    load = loadavg()
    _, _, base_cpu, base_rss = best([nix, "eval", "--impure", "--raw", "--expr", '""'])

    rows = []
    for f in files:
        out, secs, cpu, rss = best([
            nix, "eval", "--impure", "--raw", "--expr",
            f'import {poc}/bench.nix {{ path = "{f}"; }}',
        ])
        parts = out.split()
        if len(parts) != 3:
            fault(f"bench.nix printed {out!r} for {f}, expected three numbers")
        nbytes, nodes, entries = (int(p) for p in parts)
        if nbytes != f.stat().st_size:
            fault(f"bench read {nbytes} bytes of {f} but the file is {f.stat().st_size}")
        if nodes == 0 or entries == 0:
            fault(f"{f} produced {nodes} nodes and {entries} label entries; nothing was labelled")
        if entries < nodes:
            fault(f"{f} produced {entries} label entries for {nodes} nodes; "
                  f"a labelled node has at least one nonterminal")
        work = cpu - base_cpu
        if work < base_cpu * MIN_BASELINE_RATIO:
            fault(f"{f} cost {cpu:.3f} s CPU against a {base_cpu:.3f} s baseline; "
                  f"this ladder point is too small to measure")
        if rss < base_rss * MIN_RSS_RATIO:
            fault(f"{f} peaked at {rss / 1024:.0f} MB against a {base_rss / 1024:.0f} MB "
                  f"baseline; subtracting one from the other would not leave a measurement")
        rows.append({"path": f, "bytes": nbytes, "nodes": nodes, "entries": entries,
                     "secs": secs, "work": work, "rss": rss,
                     "net": max(rss - base_rss, 0)})

    load = max(load, loadavg())
    rows.sort(key=lambda r: r["nodes"])
    print(f"machine: {cores} cores, 1-minute load average {load:.1f}")
    print(f"evaluator start-up baseline: {base_cpu:.3f} s CPU, {base_rss / 1024:.0f} MB RSS "
          f"(both subtracted)")
    print(f"{'nodes':>8} {'entries':>8} {'wall s':>8} {'label cpu s':>11} "
          f"{'nodes/s':>9} {'peak RSS':>10} {'kB/node':>8}")
    for r in rows:
        print(f"{r['nodes']:>8} {r['entries']:>8} {r['secs']:>8.2f} {r['work']:>11.2f} "
              f"{r['nodes'] / r['work']:>9.0f} {r['rss'] / 1024:>7.0f} MB "
              f"{r['net'] / r['nodes']:>8.1f}")

    span = rows[-1]["nodes"] / rows[0]["nodes"]
    if span < MIN_SPAN:
        fault(f"the ladder only spans {span:.1f}x, at least {MIN_SPAN}x is needed")

    bad = []
    steps = [(rows[i], rows[i + 1], TOLERANCE) for i in range(len(rows) - 1)]
    steps.append((rows[0], rows[-1], END_TO_END_TOLERANCE))
    for a, z, tol in steps:
        grew = z["nodes"] / a["nodes"]
        slower = z["work"] / a["work"]
        verdict = "ok" if slower <= grew * tol else "SUPERLINEAR"
        print(f"  {a['nodes']:>7} -> {z['nodes']:>7} nodes: {grew:.2f}x input, "
              f"{slower:.2f}x CPU  {verdict}")
        if verdict != "ok":
            bad.append((a["nodes"], z["nodes"], grew, slower))

    worst = max(rows, key=lambda r: r["net"] / r["nodes"])
    print(f"peak memory: {worst['net'] / worst['nodes']:.1f} kB per DAG node net of the "
          f"baseline at {worst['nodes']} nodes (ceiling {MAX_KB_PER_NODE} kB/node, "
          f"{MAX_RSS_KB / 1024:.0f} MB absolute)")

    if bad:
        for a, z, grew, slower in bad:
            print(f"FAIL: {a} -> {z} nodes grew {grew:.2f}x but cost {slower:.2f}x CPU")
        if load > cores * BUSY_FRACTION:
            fault(f"...but the load average was {load:.1f} on {cores} cores. Contention "
                  f"inflates the largest ladder point more than the smallest, so this is "
                  f"not evidence about the labeller. Re-run on an idle machine.")
        sys.exit(1)
    if worst["net"] / worst["nodes"] > MAX_KB_PER_NODE:
        print(f"FAIL: {worst['net'] / worst['nodes']:.1f} kB per node is over the "
              f"{MAX_KB_PER_NODE} kB ceiling")
        sys.exit(1)
    if rows[-1]["rss"] > MAX_RSS_KB:
        print(f"FAIL: the largest point peaked at {rows[-1]['rss'] / 1024:.0f} MB, "
              f"over the {MAX_RSS_KB / 1024:.0f} MB ceiling")
        sys.exit(1)
    print(f"PASS: {len(rows)} sizes spanning {span:.1f}x, every step linear within "
          f"{TOLERANCE}x and the whole ladder within {END_TO_END_TOLERANCE}x")


if __name__ == "__main__":
    main(sys.argv[1:])
