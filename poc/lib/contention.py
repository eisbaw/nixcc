#!/usr/bin/env python3
"""Timed child runs, and the machinery every timing ladder in this tree
hangs off: how a ladder is measured, and whether the machine was free enough
for what it measured to mean anything.

poc/02-lexer/throughput.py, poc/03-matcher/scale.py and poc/04-assembler's
scale.py all judge linearity by comparing a child evaluator's CPU time across
a size ladder. Two different things can distort that comparison, and this
module owns both: OTHER WORK on the machine, and the machine's own clock
moving while the ladder runs. Both the measurement and the decisions live
here, because a guard duplicated in three harnesses gets fixed in one of them.

MEASUREMENT ORDER IS THE FIRST THING THIS FILE DOES, and it is the one that
cost the most to learn. A ladder compares CPU seconds taken at different
moments, so it is only sound if a CPU second means the same thing throughout.
On this machine -- an Intel Core Ultra 7 165U -- it does not:

  * The 14 "cores" are three different processors. cpu0-3 are P-cores capped
    at 4.9 GHz, cpu4-11 are E-cores at 3.8, cpu12-13 are LP-E cores at 2.1.
    The same 431 kB lexer point, pinned, costs 1.79 s of CPU on a P-core,
    2.40 on an E-core and 3.93 on an LP-E core: 1.34x and 2.20x for byte-
    identical work. Nothing in rusage says which one ran it.
  * Within the P-cores the clock falls away under sustained load. Measured
    with NIX_SHOW_STATS, six consecutive runs of the same 431 kB point pinned
    to cpu0-3 reported an IDENTICAL two GC cycles and identical totalBytes
    every time, and cost 1.60, 1.60, 1.67, 1.66, 2.11, 2.16 s. Same work,
    same allocation, 35% more CPU seconds once the package had warmed up.

Both effects are functions of WHEN a point was measured. The ladders used to
measure block-wise -- every repeat of the smallest point, then the next, up to
the largest -- which confounds "when" perfectly with "how big", and always in
the same direction, since the largest point is always measured last and so
always on the hottest machine. That is not a subtle bias. Measured over five
gate runs the largest point never once reached the throughput the four smaller
ones sustained; measured in DESCENDING order instead, on the same tree and the
same machine, the same ladder read SUBLINEAR -- the last step came in at 0.83
to 1.01 times its input ratio and the end-to-end step as low as 0.51. Ladder
order alone moved the verdict from FAIL to a comfortable pass.

So rounds() measures ROUND-ROBIN: one run of every point, then another round
of every point, and so on, with the within-round order reversed on alternate
rounds so that a clock falling away DURING a round does not always land on the
same end of the ladder. Interleaving is also why the ladders no longer ask
whether two points were comparably measured: every point is now measured in
every round, which makes the question answer itself.

What is DONE with the rounds changed once more after that, and step_ratio()
below carries the argument: a point's headline figure -- the cheapest of its
rounds -- is what the table reports and what the baseline cliff is checked
against, but no linearity verdict is taken from it any more. Those come from
ratios measured inside a round.

WHAT CONTENTION IS MEASURED AGAINST. Not the load average. A one-minute mean
lags a burst by most of a minute, which makes it structurally unable to see
load that arrives after the harness starts -- and the ladders used to read it
exactly once, before measuring. Instead /proc/stat's system-wide busy counter
is sampled around every ROUND, and the CPU time of that round's own children
is subtracted from the delta. What is left, divided by the round's wall time,
is the number of cores' worth of OTHER work that ran during it. A LADDER's
figure is the worst of its rounds, which is the conservative reading: if load
arrived for one round and the cheapest run of a point happened to miss it, the
whole ladder is still declared contended. The figure belongs to the Ladder
rather than to any Point, because with the points interleaved "how busy was it
while THIS point was measured" is not a question with an answer.

Two accountings are being differenced -- /proc/stat's per-core tick counters
and wait4's rusage -- so they can disagree by a tick or two per core. Beyond
that allowance the disagreement is a fault, not a reading: see _round(). An
earlier draft clamped the result at zero instead, which meant "these two
clocks contradict each other" was reported as "the machine was perfectly
idle", the most permissive answer available. That is the same fail-open shape
this module was written to remove, so it is worth naming.

WHAT IS DONE WITH IT. require_quiet() refuses to render a verdict -- pass or
fail -- when any ROUND of the ladder was measured against more than limit()
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

(The 3.7-10.6 rows were taken while the sampling window was filled with extra
child runs rather than padded. That changed how many runs the min() was taken
over, which is why it no longer is -- see _round(). They were also taken one
point at a time, in size order, which MEASUREMENT ORDER above says is a
different instrument again.)

Three things to read off the table. The last clean reading is 3.9 and the
first distorted one is 4.1, so the boundary lies between them -- and
BUSY_CEILING is set below both rather than between them, for two reasons.
Only three of the seventeen runs landed under 4.0, so the clean side of that
boundary is the thinly sampled side; and the costs are asymmetric, since
refusing a verdict that could have been given costs a re-run while giving one
that could not costs a wrong answer about the architecture. It was NOT chosen
to make a gate go green: when it was measured, this machine idled at 3.6 to
4.7 cores of unrelated work, so every ladder refused on it either way. (It no
longer does -- a runaway process was killed and it now idles around 1 to 2 --
which is a fact about the machine and not a reason to have picked the number.)
By 6.4 cores the distortion on its own was enough to fail a lexer that had not
changed, which is the false SUPERLINEAR this guard was rewritten for, at a
comparable load -- task-020 records one in the wild at a load average of 6.6.

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
  * Round-robin order REMOVES the confound between size and machine state; it
    does not make a drifting clock go away. A point measured on a P-core in
    one round and an E-core in the next still has two readings 1.3x apart, and
    all interleaving guarantees is that every point got the same chances. The
    residue is ASSUMED to be noise rather than bias; it is not shown to be. It
    could have a direction: every point now runs immediately after a
    differently sized one, so each pays a cache-eviction cost the other points
    set, which is closer to a fixed adder than a proportional one and so costs
    the small points relatively more. That bends the ratios towards SUBLINEAR,
    which the paragraph above calls the dangerous direction. Counting retired
    instructions would be invariant to all of it; that is task-038, and it
    needs a perf counter this harness cannot assume it may open.
  * Interleaving cost the contention reading TEMPORAL RESOLUTION, and that is
    a real trade rather than a free win. Block order gave one window per point
    -- six short windows for the lexer ladder, and the guard took the worst.
    Round-robin gives one window per round: three, each covering the whole
    ladder. A two-second burst of eight cores used to read 8.0 on the point it
    landed on; spread over a six-second round it reads 2.7 and clears
    BUSY_CEILING. Sustained load is seen exactly as before; a TRANSIENT burst
    is now about three times harder to see. It was taken that way round
    because the alternative -- sampling between the children inside a round --
    puts /proc/stat's whole-tick quantisation back on the short jobs, where a
    single round of the smallest point is 0.15 s against a 0.14 core-second
    tick error, which is a reading of nothing at all. The threshold table
    above was measured on the per-point windows, so it describes a slightly
    sharper instrument than the one that now consults it.

WHAT PROVES ANY OF THIS WORKS. selftest.py, next to this file, puts a known
number of busy cores on the machine and checks that this module reports them,
and drives rounds() with jobs that record when they ran to check that the
order really is round-robin -- because "we interleave now" is the kind of
claim that keeps passing after the loop is quietly written back the other way.
The six cases poc/02-lexer/run.sh and poc/03-matcher/run.sh each run against
their ladder move the threshold to force the DECISION either way; none of them
can see a broken MEASUREMENT --
with busy_cpu_seconds() stubbed out to return 0.0, every one of them still
passes. selftest.py is the half that notices, and run.sh proves it notices by
stubbing exactly that.
"""
import os
import statistics
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
# machine during any round of a ladder: a quarter of the cores, but
# never more than the absolute figure the table above was measured against.
# Raising either to make a red gate go green would be exactly the mistake that
# made this rewrite necessary.
BUSY_FRACTION = 0.25
BUSY_CEILING = 3.5
# The shortest window a contention reading may be taken over, in seconds. See
# rounds(), which pads a short round rather than adding runs to it.
MIN_WINDOW = 2.0

CLOCK_TICK = os.sysconf("SC_CLK_TCK")


class Point(NamedTuple):
    """One ladder point: the cheapest run of several.

    It carries no contention figure. It used to, and the figure was the whole
    session's worst round copied onto every point -- the same scalar, stored
    once per row, describing something the row did not own. Contention belongs
    to the Ladder now, which is also the honest granularity: once the points
    are interleaved, "how busy was it while THIS point was measured" is not a
    question with an answer.
    """
    out: str
    wall: float     # seconds, of the cheapest run
    cpu: float      # child CPU seconds, of the cheapest run
    rss: int        # peak RSS in KB, of the cheapest run
    costs: tuple    # every round's CPU seconds for this point, in round order


class Ladder(NamedTuple):
    """What one interleaved measuring session produced.

    `points` is one Point per job, in the order the jobs were given -- NOT the
    order they ran in, which alternates. `foreign` and `windows` are per ROUND
    rather than per point, because that is the granularity the contention
    reading is taken at once the points are interleaved; every point shares
    them, which is the same statement as "these points are comparable".
    """
    points: tuple
    foreign: tuple
    windows: tuple


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
    return (v[0] + v[1] + v[2] + v[5] + v[6] + v[7]) / CLOCK_TICK


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


def _round(argvs, label):
    """One round: run each argv once, in the order given, over one contention
    window. Returns (runs in the given order, cores of other work, seconds).

    A short round is padded with a sleep rather than with more runs. The
    contention reading needs a window of its own: /proc/stat counts whole ticks
    per core, so a delta can be out by about one tick on each core -- 0.14
    core-seconds on 14 cores at 100 Hz -- and the skew allowance below is twice
    that, since two samples are being differenced. Over the 0.03 s the
    evaluator's start-up baseline takes, 0.14 core-seconds is an error of
    several whole cores; over MIN_WINDOW it is under a tenth of one. A round of
    a full ladder is already seconds long, so the padding only bites for a
    one-job round -- which is what selftest.py measures with. Filling the window
    with extra runs instead would deepen the min() for the short jobs only,
    biasing the small end of a ladder down and its ratios up: a false
    SUPERLINEAR built into the instrument, and a silent recalibration of
    tolerances that were measured at a fixed repeat count.
    """
    busy0, t0 = _sample()
    runs = [_run_once(a) for a in argvs]
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
    skew = 2.0 * cores() / CLOCK_TICK
    if other < -skew:
        fault(f"/proc/stat accounted {other:.2f} core-seconds LESS work than "
              f"the children of {label} used over {span:.2f} s; the kernel's "
              f"counters and those children's rusage do not describe the same "
              f"machine, so no contention reading from them can be trusted")
    return runs, other / span, span


def rounds(argvs, repeats):
    """Measure every argv `repeats` times, ROUND-ROBIN, cheapest run wins.

    Round-robin rather than one job at a time, because a ladder that measures
    its points in size order measures its largest one last, on the warmest
    machine, every single time -- see MEASUREMENT ORDER in the module
    docstring, which records what that cost. The within-round order is
    reversed on alternate rounds so that a clock falling away during a round
    does not always land on the same end of the ladder either.

    Minimum, not mean, for the figure this reports: we are measuring an
    algorithm, and noise only ever adds work. Taking it over interleaved rounds
    is what makes that minimum mean something -- each job's best observation is
    drawn from the same sequence of machine states as every other job's.

    But a minimum is biased low by an amount that grows with the noise, which
    is why no linearity VERDICT is taken from these figures. step_ratio() says
    what is, and why; the numbers here are what a reader sees in the table and
    what the baseline cliff is measured against.

    CPU and peak RSS come from os.wait4, which reports this child's own
    figures, rather than from getrusage(RUSAGE_CHILDREN), which is a running
    maximum over every child this process has ever had.
    """
    if repeats < 1:
        fault(f"rounds() asked for {repeats} repeats")
    if not argvs:
        fault("rounds() asked to measure nothing at all")
    runs = [[] for _ in argvs]          # per job, one entry per round
    foreign, windows = [], []
    for r in range(repeats):
        order = list(range(len(argvs)))
        if r % 2:
            order.reverse()
        got, other, span = _round([argvs[i] for i in order],
                                  f"round {r + 1} of {repeats}")
        for slot, run in zip(order, got):
            runs[slot].append(run)
        foreign.append(other)
        windows.append(span)
    points = []
    for job in runs:
        out, wall, cpu, rss = min(job, key=lambda run: run[2])
        # Every round's cost is kept, in round order, so a reader can see the
        # machine drift under the ladder rather than only the figure that
        # survived it.
        points.append(Point(out, wall, cpu, rss, tuple(r[2] for r in job)))
    return Ladder(tuple(points), tuple(foreign), tuple(windows))


def step_ratio(ladder, base, a, z, what):
    """How much more ladder point `z` cost than point `a`, and the per-round
    readings it was taken from. Both net of that ROUND's own baseline.

    The ratio is the quantity a linearity tolerance is applied to, so the ratio
    is what is measured -- rather than being assembled afterwards out of two
    numbers that were each optimised over the rounds independently. That
    distinction is not academic, and it cost a gate run to find.

    Each point's headline figure is the cheapest of its rounds. Taking a
    minimum is biased low, and the bias is larger the noisier the measurement
    -- which means larger for the SHORT points, whose cost is a few tenths of a
    second and so is dominated by start-up transients. The smallest ladder
    point is both the noisiest and the denominator of the first adjacent step
    AND of the end-to-end step, so one flattering reading of it moves two
    verdicts at once. Measured, in a gate run of the lexer ladder: the 31 kB
    point read 0.15, 0.22 and 0.23 s of CPU across three rounds while the
    431 kB point read 2.70, 2.73 and 3.18. Quotient of the minima: 1.50 against
    a 1.5 ceiling, a FAIL. The same three rounds read as three complete ratios:
    1.53, 1.07 and 1.13.

    So the median of those, and for two reasons. Within a round the endpoints
    are measured seconds apart on the same clock, so their ratio is invariant
    to the drift decision-008 records rather than merely averaged over it.
    Across rounds, a median rejects one bad round in either direction, where a
    minimum only ever rejects in the direction that flatters.

    A round in which a point cost no more than that round's own start-up
    baseline leaves nothing to take a ratio of, and that has TWO causes for the
    same reason the cliff at the bottom of a ladder does: a ladder point too
    small to measure, or a busy machine inflating the baseline. So it branches
    the same way -- HARNESS FAULT on a quiet machine, NO VERDICT on a busy one.
    Getting that wrong here would have been the exact miscategorisation
    task-035 was filed for, reintroduced inside the fix for it: this runs
    BEFORE require_quiet(), so a fault raised unconditionally would report a
    busy machine as a broken harness.
    """
    per_round = []
    for i, (bc, ac, zc) in enumerate(zip(base.costs, a.costs, z.costs, strict=True), 1):
        net_a, net_z = ac - bc, zc - bc
        if net_a <= 0 or net_z <= 0:
            report(ladder)
            print(f"in round {i} two ladder points cost {ac:.3f} s and {zc:.3f} s "
                  f"of CPU against the {bc:.3f} s start-up baseline measured in "
                  f"the same round, which leaves nothing to take a ratio of.")
            if quiet(ladder):
                fault(f"The machine was quiet throughout -- at worst "
                      f"{busiest(ladder):.2f} cores of other work in any round -- "
                      f"so nothing about this machine explains it and the ladder "
                      f"is built wrong: a point this close to the evaluator's own "
                      f"start-up cost is not a measurement of the {what}")
            print(f"NO VERDICT: the machine was also busy -- up to "
                  f"{busiest(ladder):.2f} of this machine's {cores()} cores of "
                  f"other work, over the {limit():.2f} this check will render a "
                  f"verdict against -- and contention inflates the start-up "
                  f"baseline, which is what this subtraction is against. Which of "
                  f"the two it was cannot be told apart from here. Re-run on an "
                  f"idle machine.")
            sys.exit(EXIT_NO_VERDICT)
        per_round.append(net_z / net_a)
    return statistics.median(per_round), tuple(per_round)


def baseline_argv(nix):
    """The evaluator's fixed start-up cost, as a job: an eval that does nothing.

    Here rather than written out in each harness because every ladder subtracts
    it from every point, so the four copies of this string were four chances
    for one of them to drift into measuring a different baseline.
    """
    return [nix, "eval", "--impure", "--raw", "--expr", '""']


def bench_argv(nix, poc, path):
    """One ladder point. Every PoC's bench.nix takes { path } and prints the
    counts its own ladder reads; that contract is shared, so it lives here."""
    return [nix, "eval", "--impure", "--raw", "--expr",
            f'import {poc}/bench.nix {{ path = "{path}"; }}']


def ladder(nix, poc, paths, repeats):
    """Measure the start-up baseline and every ladder point in one interleaved
    session. Returns (the Ladder, the baseline Point, a Point per path).

    The baseline goes in as one more job rather than being measured up front,
    because it is subtracted from every point: a baseline taken under
    conditions none of the points saw is subtracted wrongly from all of them at
    once. Which job is the baseline is decided here rather than in each
    harness, where "the baseline is job 0" was an unwritten positional contract
    repeated in four files -- reorder the list and every row is compared
    against the wrong thing and the ladder still passes.
    """
    measured = rounds([baseline_argv(nix)] + [bench_argv(nix, poc, p) for p in paths],
                      repeats)
    return measured, measured.points[0], measured.points[1:]


def busiest(ladder):
    """The worst contention any round of this ladder was measured against."""
    return max(ladder.foreign)


def quiet(ladder):
    """Was the machine free enough for this ladder to mean anything?"""
    return busiest(ladder) <= limit()


def report(ladder):
    """What the ladder was up against, printed on every run and not only on the
    refusals: a ladder that squeaked in under the threshold and one measured on
    an empty machine must not log identically. Per round rather than per point,
    because that is where the reading is taken once the points are
    interleaved -- and because a round that was busy is a round every point was
    measured in."""
    print(f"machine: {cores()} cores; other work occupied up to "
          f"{busiest(ladder):.2f} of them while measuring "
          f"(a verdict needs {limit():.2f} or less)")
    print("  per round: " + ", ".join(
        f"{f:.2f} cores over {w:.1f} s" for f, w in zip(ladder.foreign, ladder.windows)))


def require_quiet(ladder, what):
    """Render no verdict at all if the machine was busy. Called whether the
    ladder was about to pass or about to fail."""
    if quiet(ladder):
        return
    print(f"NO VERDICT: other work occupied up to {busiest(ladder):.2f} of this "
          f"machine's {cores()} cores while this ladder was measured, over the "
          f"{limit():.2f} this check will render a verdict against.")
    for i, (f, w) in enumerate(zip(ladder.foreign, ladder.windows), 1):
        mark = "  <--" if f > limit() else ""
        print(f"  round {i:>2}: {f:>5.2f} cores of other work over {w:.1f} s{mark}")
    print(f"Contention inflates a large working set more than a small one, and a "
          f"contended start-up baseline is subtracted from every point at once, "
          f"which bends the ratios the other way. So these numbers are not "
          f"evidence about the {what} in either direction. This is not a pass "
          f"and not a failure: the measurement could not be taken. Re-run on an "
          f"idle machine.")
    sys.exit(EXIT_NO_VERDICT)


def too_small(ladder, label, point, base, ratio, what):
    """The cliff at the bottom of a ladder: this point's work is not comfortably
    bigger than the evaluator start-up baseline being subtracted from it, so the
    ratios above it would be measuring start-up noise.

    TWO things produce that reading and they are not the same verdict, so this
    says which -- or, when it cannot tell, says that too. A genuinely small
    ladder point is a HARNESS FAULT: the ladder is built wrong and no machine
    will fix it. A busy machine inflates the baseline, which shrinks the very
    subtraction this cliff is testing, and that is a NO VERDICT: nothing is
    wrong with the ladder and a quiet machine would measure it fine. The old
    code asked the contention guard first and let it exit, which meant a run
    that had been TOLD everything was contended reported a timing accident as
    contention -- the wrong cause, in the one message the reader gets.
    """
    # The ladder exits from here, so the machine line it would have printed
    # further down never gets printed. A refusal that names contention as one
    # of its two candidate causes has to show the contention it is talking
    # about, or the reader is asked to take it on trust.
    report(ladder)
    print(f"{label} is too small to measure: it cost {point.cpu:.3f} s CPU "
          f"against a {base.cpu:.3f} s evaluator start-up baseline, under the "
          f"{ratio}x this ladder needs before subtracting one from the other "
          f"is a correction rather than the measurement.")
    if quiet(ladder):
        fault(f"and the machine was quiet throughout -- at worst "
              f"{busiest(ladder):.2f} cores of other work in any round, under "
              f"the {limit():.2f} that would cast doubt on it -- so nothing "
              f"about this machine explains the reading and no run of it would "
              f"be a reading of the {what}. The ladder wants a bigger smallest "
              f"point, not a quieter machine")
    print(f"NO VERDICT: the machine was also busy -- up to {busiest(ladder):.2f} of "
          f"this machine's {cores()} cores of other work, over the {limit():.2f} "
          f"this check will render a verdict against. Contention inflates the "
          f"start-up baseline, and the baseline is what this cliff compares "
          f"against, so a busy machine produces exactly this reading from a "
          f"ladder point that is perfectly big enough. Which of the two it was "
          f"cannot be told apart from here. This is not a pass and not a "
          f"failure: the measurement could not be taken. Re-run on an idle "
          f"machine, and if it says the same thing on one, the ladder point is "
          f"genuinely too small.")
    sys.exit(EXIT_NO_VERDICT)
