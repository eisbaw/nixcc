#!/usr/bin/env python3
"""Timed child runs, and the contention guard both timing ladders hang off.

poc/02-lexer/throughput.py and poc/03-matcher/scale.py both judge linearity by
comparing a child evaluator's CPU time across a size ladder. Contention does
not perturb that comparison evenly: memory-bandwidth pressure costs a 500 MB
working set more than an 82 MB one, so a busy machine inflates the top of a
ladder more than the bottom and reads as superlinear. This module decides
whether the machine was quiet enough for either ladder's numbers to mean
anything. Both the measurement and the decision live here, because a guard
duplicated in two harnesses gets fixed in one of them.

WHAT IS MEASURED. Not the load average. A one-minute mean lags a burst by most
of a minute, which makes it structurally unable to see load that arrives after
the harness starts -- and both ladders used to read it exactly once, before
measuring. Instead /proc/stat's system-wide busy counter is sampled around
every ladder point, and the point's own children's CPU time is subtracted from
the delta. What is left, divided by the wall time of the window, is the number
of cores' worth of OTHER work that ran while that point was being measured. It
is a direct measurement of the thing that distorts the ratios, over exactly
the window in which the distortion would happen.

Two accountings are being differenced -- /proc/stat's per-core tick counters
and wait4's rusage -- so they can disagree by a tick or two per core. Beyond
that allowance the disagreement is a fault, not a reading: see best(). An
earlier draft clamped the result at zero instead, which meant "these two
clocks contradict each other" was reported as "the machine was perfectly
idle", the most permissive answer available. That is the same fail-open shape
this module was written to remove, so it is worth naming.

WHAT IS DONE WITH IT. require_quiet() refuses to render a verdict -- pass or
fail -- when any point of the ladder was measured against more than limit()
cores of other work. A measurement that could not be taken is not the same as
a measurement that failed, and neither may be reported as the other. The guard
this replaced could only downgrade a FAIL, so a pass measured under contention
was reported as a clean pass with nothing said.

WHERE THE THRESHOLD COMES FROM, since a number nobody measured is a number
somebody guessed. The lexer ladder was run seventeen times on this 14-core
machine under a memory-copying stressor on 0 to 4 cores -- the machine was
already carrying 3 to 5 cores of unrelated work, which is what reaches the top
of the range -- and each run's foreign occupancy recorded against the worst
adjacent step's ratio-of-ratios, the quantity TOLERANCE is applied to, where
1.0 is exactly linear and that ladder refuses anything past 1.35:

    foreign cores    worst adjacent step
      3.2            1.00
      3.7  3.9       1.05  1.05
      4.1  4.3       1.19  1.16
      4.9  5.0  5.3  1.10  1.13  1.03
      5.4  5.7  5.8  1.18  1.18  1.25
      6.0  6.4       1.27  1.36   <-- 1.36 is past 1.35: a FAIL from contention
      7.3  8.3  8.6  1.18  1.08  1.12
     10.2 10.6       1.14  1.07

(The 3.7-10.6 rows were taken while best() still filled its sampling window
with extra child runs rather than padding it. That changed how many runs the
min() was taken over, which is why it no longer does it -- see best().)

Three things to read off the table. The last clean reading is 3.9 and the
first distorted one is 4.1, so the boundary lies between them -- and
BUSY_CEILING is set below both rather than between them, for two reasons.
Only three of the seventeen runs landed under 4.0, so the clean side of that
boundary is the thinly sampled side; and the costs are asymmetric, since
refusing a verdict that could have been given costs a re-run while giving one
that could not costs a wrong answer about the architecture. It was NOT chosen
to make a gate go green: the machine it was measured on idles at 3.6 to 4.7
cores of unrelated work, so both ladders refuse on it either way. By 6.4 cores the distortion on its own was enough to fail a
lexer that had not changed, which is the false SUPERLINEAR this guard was
rewritten for, at a comparable load -- task-020 records one in the wild at a
load average of 6.6.

Second, the relationship is noisy rather than proportional: 8.3 cores of load
produced a cleaner ladder (1.08) than 6.4 did (1.36). Contention BOUNDS how
far a ladder can be trusted; it does not predict the error. There is nothing
here to correct for and nothing to calibrate against, which is why the answer
is to refuse rather than to compensate.

Third, it moves both ways. The end-to-end ratio read 1.50 against its own 1.5
ceiling at 6.4 cores and 0.77 at 5.0, and the low readings are the dangerous
ones: the start-up baseline is subtracted from every point, so a baseline
measured under load is subtracted too generously from the small points and
flatters the curve. The same contention that invents a superlinearity can hide
one. That is why the baseline is one of the points this guard checks, and why
the refusal is not conditional on which way the verdict came out.

LIMITS, stated rather than left to be discovered.

  * The threshold is a measurement from one 14-core machine, so it is capped
    in absolute cores rather than scaled with the core count. Memory bandwidth
    is a socket property: a 128-core machine does not have nine times this
    one's, and letting 32 cores of memcpy through because the fraction said so
    would be extrapolating a measurement nobody took.
  * iowait counts as idle here. A task blocked on IO burns no CPU, but a
    writeback storm or a `nix-store --gc' does saturate the memory bus while
    its accounting sits in iowait, and such a machine reads quiet and gets a
    verdict. Counting iowait as busy would be the conservative choice; it was
    not taken because iowait is a per-CPU heuristic that is not even monotonic,
    and feeding it into a threshold would be building on sand. This is the
    known hole in the measurement.
  * /proc/stat is system-wide, so under a cgroup CPU quota or inside a VM it
    describes the host rather than what this process could have had.
  * A machine whose steady state is busier than the threshold gets no verdict
    out of these ladders at all. That is the correct answer for it rather than
    a defect here, but it does mean the linearity gate wants a machine that is
    free, and that the gate is red on a machine that is not.

WHAT PROVES ANY OF THIS WORKS. selftest.py, next to this file, puts a known
number of busy cores on the machine and checks that this module reports them.
The four cases each run.sh runs against the ladders move the threshold to
force the DECISION either way; none of them can see a broken MEASUREMENT --
with busy_cpu_seconds() stubbed out to return 0.0, every one of them still
passes. selftest.py is the half that notices, and run.sh proves it notices by
stubbing exactly that.
"""
import os
import shlex
import sys
import time
from typing import NamedTuple

# Exit statuses. Distinct on purpose: run.sh, a human, or a mutation test must
# be able to tell "the machine was too busy to say" apart from "the thing under
# test is broken" and from "the harness itself is broken".
EXIT_FAIL = 1
EXIT_FAULT = 2
EXIT_NO_VERDICT = 3

# No verdict is rendered when other work occupied more than this much of the
# machine while any ladder point was measured: a quarter of the cores, but
# never more than the absolute figure the table above was measured against.
# Raising either to make a red gate go green would be exactly the mistake that
# made this rewrite necessary.
BUSY_FRACTION = 0.25
BUSY_CEILING = 3.5
# The shortest window a contention reading may be taken over, in seconds. See
# best(), which pads a short window rather than adding runs to it.
MIN_WINDOW = 2.0

_CLOCK_TICK = os.sysconf("SC_CLK_TCK")


class Point(NamedTuple):
    """One ladder point: the cheapest run of several, and what else ran."""
    out: str
    wall: float     # seconds, of the cheapest run
    cpu: float      # child CPU seconds, of the cheapest run
    rss: int        # peak RSS in KB, of the cheapest run
    foreign: float  # cores' worth of other work, across ALL the runs
    window: float   # seconds the foreign figure was measured over


def cores():
    return os.cpu_count() or 1


def limit():
    """Cores of other work above which no verdict may be rendered."""
    return min(cores() * BUSY_FRACTION, BUSY_CEILING)


def fault(msg):
    """The harness or its inputs are broken. Not a verdict on anything."""
    print(f"HARNESS FAULT: {msg}")
    sys.exit(EXIT_FAULT)


def busy_cpu_seconds():
    """Non-idle CPU seconds summed over every core since boot, from /proc/stat.

    iowait is counted as idle -- a task blocked on IO burns no CPU. See the
    LIMITS in the module docstring for what that misses.

    Raises rather than returning a sentinel, and the caller turns that into a
    harness fault. A guard that reports 0.0 contention when it cannot read
    /proc is a guard that waves everything through.
    """
    with open("/proc/stat") as f:
        fields = f.readline().split()
    if fields[:1] != ["cpu"] or len(fields) < 9:
        raise ValueError(f"/proc/stat began with {' '.join(fields[:3])!r}")
    # user nice system idle iowait irq softirq steal
    v = [int(x) for x in fields[1:9]]
    return (v[0] + v[1] + v[2] + v[5] + v[6] + v[7]) / _CLOCK_TICK


def _sample():
    """(busy CPU seconds, monotonic seconds), read adjacently so that a window
    between two of these covers the same interval on both clocks."""
    try:
        return busy_cpu_seconds(), time.monotonic()
    except (OSError, ValueError) as e:
        fault(f"cannot read /proc/stat ({e}); without it there is no way to "
              f"tell a slow evaluator from a busy machine, so no ladder may run")


def _run_once(argv):
    """Run argv to completion, returning (stdout, wall, child CPU, peak RSS KB)."""
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


def best(argv, repeats):
    """Cheapest of `repeats` runs by CPU time, and what else ran while they did.

    Minimum, not mean: we are measuring an algorithm, and noise only ever adds
    work. The contention figure covers the WHOLE window -- every repeat and
    the gaps between them -- rather than the window of the repeat that won.
    That is deliberately the conservative reading: if load arrived for part of
    the window and the cheapest repeat happened to miss it, the point is still
    declared contended.

    A short window is padded with a sleep rather than with more runs. The
    reading needs a window of its own: /proc/stat counts whole ticks per core,
    so a delta can be out by about one tick on each core -- 0.14 core-seconds
    on 14 cores at 100 Hz, which over the 0.14 s the start-up baseline takes is
    an error of a whole core, and over MIN_WINDOW is under a tenth of one.
    Filling the window with extra runs instead would deepen the min() for the
    short points only, biasing the small end of a ladder down and its ratios
    up -- a false SUPERLINEAR built into the instrument, and a silent
    recalibration of tolerances that were measured at a fixed repeat count.

    CPU and peak RSS come from os.wait4, which reports this child's own
    figures, rather than from getrusage(RUSAGE_CHILDREN), which is a running
    maximum over every child this process has ever had.
    """
    if repeats < 1:
        fault(f"best() asked for {repeats} repeats")
    busy0, t0 = _sample()
    runs = [_run_once(argv) for _ in range(repeats)]
    short = MIN_WINDOW - (time.monotonic() - t0)
    if short > 0:
        time.sleep(short)
    busy1, t1 = _sample()
    span = t1 - t0
    other = busy1 - busy0 - sum(r[2] for r in runs)
    # Two tick counters differenced against a third clock: a couple of ticks
    # per core of disagreement is accounting skew, and is carried through as
    # measured, sign and all. More than that and the two do not describe the
    # same machine -- a suspend, a core going offline, a masked /proc -- and
    # there is no reading to report rather than a reassuring one.
    skew = 2.0 * cores() / _CLOCK_TICK
    if other < -skew:
        fault(f"/proc/stat accounted {other:.2f} core-seconds LESS work than "
              f"`{shlex.join(argv)}` used over {span:.2f} s; the kernel's "
              f"counters and this child's rusage do not describe the same "
              f"machine, so no contention reading from them can be trusted")
    out, wall, cpu, rss = min(runs, key=lambda r: r[2])
    return Point(out, wall, cpu, rss, other / span, span)


def busiest(points):
    """The worst contention any of these points was measured against."""
    return max(p.foreign for _, p in points)


def quiet(points):
    """Was the machine free enough for these points to mean anything?"""
    return busiest(points) <= limit()


def report(points):
    """One line naming what the ladder was up against. Printed on every run and
    not only on the refusals: a ladder that squeaked in under the threshold and
    one measured on an empty machine must not log identically."""
    print(f"machine: {cores()} cores; other work occupied up to "
          f"{busiest(points):.2f} of them while measuring "
          f"(a verdict needs {limit():.2f} or less)")


def require_quiet(points, what):
    """Render no verdict at all if the machine was busy. Called whether the
    ladder was about to pass or about to fail; `points` is (label, Point) pairs
    so the reader can see which part of the ladder was hit."""
    if quiet(points):
        return
    print(f"NO VERDICT: other work occupied up to {busiest(points):.2f} of this "
          f"machine's {cores()} cores while this ladder was measured, over the "
          f"{limit():.2f} this check will render a verdict against.")
    for label, p in points:
        mark = "  <--" if p.foreign > limit() else ""
        print(f"  {label:>12}: {p.foreign:>5.2f} cores of other work "
              f"over {p.window:.1f} s{mark}")
    print(f"Contention inflates a large working set more than a small one, and a "
          f"contended start-up baseline is subtracted from every point at once, "
          f"which bends the ratios the other way. So these numbers are not "
          f"evidence about the {what} in either direction. This is not a pass "
          f"and not a failure: the measurement could not be taken. Re-run on an "
          f"idle machine.")
    sys.exit(EXIT_NO_VERDICT)
