#!/usr/bin/env python3
"""Prove that contention.py MEASURES, not just that it decides.

The guard cases each ladder's run.sh runs move the threshold to force the
decision one way or the other. None of them can see a broken measurement: stub
busy_cpu_seconds() out to return 0.0 and every one of them still passes,
because they never produce contention -- they declare it. That is the
fail-open half of the guard, and this is what covers it.

Five checks, each for a defect the others cannot see.

 -1. /proc/stat and nproc still describe the HOST. Everything below, and every
     linearity verdict any ladder renders, is read out of a /proc that is now
     on the far side of a bubblewrap mount namespace. A plain user namespace
     does not virtualise either of them -- but that is a property of this
     kernel rather than a guarantee, and a /proc that started describing the
     sandbox would change no line of any harness's output while making every
     contention reading a measurement of the wrong machine. So the sandbox
     records the host's figures on its way in and this checks they came back.

  0b. step_ratio() is the median of the per-round ratios and not something
     else. It is the single most consequential line in this tree -- every
     linearity verdict is a comparison against it -- and nothing else can see
     it: the guard cases move the contention threshold, the tolerances and the
     baseline cliff, and with the estimator changed to a minimum, to a maximum
     or to the quotient of the two minima, every one of them still passes.
     Synthetic Points with known costs, checked against a case where those
     four answers are four different numbers.

  0. rounds() really goes round-robin. This one is structural rather than
     statistical, so it is first: it needs no free cores and still runs on a
     machine too busy for the other two. It matters because measurement ORDER
     is what four gate runs were lost to -- a ladder walked in size order
     measures its largest point last, on the warmest machine, every time --
     and "we interleave now" is exactly the kind of claim that keeps passing
     after somebody writes the loop back the other way for readability. So the
     jobs record when they ran and the order is asserted, including the
     reversal on alternate rounds.

  1. Load that IS put on the machine is seen. Differential, not absolute: this
     machine is carrying whatever else it is carrying and the only thing that
     can be arranged is the difference, so a known number of cores is occupied
     with a spin loop and the readings are taken with and without it. A
     stubbed-out reading, a sign error, a wrong /proc/stat field and a units
     error all fail this.

  2. Load that WE put on the machine is not. The guard subtracts its own
     child's CPU from the delta, which is the only reason a ladder point does
     not read as a busy machine; drop that subtraction and every ladder
     refuses itself forever. So the same reading is taken around a child that
     burns OWN cores for the whole window, and has to come back the same as
     around one that sleeps through it. Several cores rather than one, because
     the background moving between two readings is worth a fraction of a core
     and the defect has to stand well clear of it.

Checks 1 and 2 both difference a probe against a BASELINE taken seconds away
from it, so both can be asked an unanswerable question rather than a hard one:
when the background moves in between, the move is attributed to the probe. That
is a third outcome, not a failure, and both render it as one -- see ATTEMPTS
and BASELINE_MOVED below.

Deliberately not a test of the threshold, of the ladders, or of nix: it spawns
no evaluator and takes about twenty-five seconds.

    usage: selftest.py SCRATCH_DIR

SCRATCH_DIR is somewhere check 0's jobs may append a line to a file. It is the
caller's, and is neither created nor removed here: whoever owns the directory
owns its lifetime.
"""
import os
import pathlib
import subprocess
import sys
import time

sys.path.append(str(pathlib.Path(__file__).resolve().parent))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e})")
    sys.exit(2)

# Cores to occupy for check 1. Enough that the reading cannot be background
# noise, few enough to leave the machine room: 4 extra busy cores cannot show
# up as 4 on a machine that had only 2 free.
LOAD = 4
# How much of that has to show up. Wide, because what this is looking for is a
# measurement that is broken rather than one that is imprecise, and because the
# background moving between two readings is the one thing it cannot hold still
# -- on this machine it has swung by 2.5 cores between one window and the next.
# Measured with 4 cores of unrelated work about: 3 spin loops read as 3.3 and
# 3.5, 4 as 3.2 to 4.4, 6 as 6.0 and 6.2. A blinded measurement reads 0.0 and a
# doubled one would read 8, so this band has room to be generous.
LOW, HIGH = 0.4, 1.7
# Cores check 2's own child burns, and how far that may move the reading. The
# defect would move it by OWN; the slack is what two readings taken a few
# seconds apart drift by on a machine with other work on it.
OWN = 4
OWN_CPU_SLACK = 1.5

# --- when the background moves under the probe ----------------------------
# Both checks below difference a probe against a baseline, and neither can hold
# the background still while it does. Seen in the wild on this machine: the
# baseline read 1.71 cores before the probe and 4.11 after, and check 1 read
# 8.32 of 4 and declared the contention measurement broken. It was not broken.
# It had been asked a question with no answer, and the honest outcome is NO
# VERDICT -- the same third outcome the ladders render, for the same reason.
#
# Two mechanisms, because the measurements show two shapes.
#
# BRACKETING. Each probe is taken BETWEEN two baseline readings rather than
# beside one, so that a background which is not holding still is visible in how
# far the two disagree. BASELINE_MOVED is where "not holding still" begins.
#
# It is MEASURED rather than derived, and the derivation that looks available
# is wrong -- recorded here because it is the first thing anyone will reach
# for. That argument runs: `added' is LOAD when the background holds still and
# the nearer band edge is LOAD - LOAD*LOW below that, so refuse at a spread big
# enough to carry a good reading past it. It over-states by exactly two. With
# `before' at b and `after' at b + d, quiet is b + d/2 whatever the background
# did in between, so the most a spread of d can shift `added' by is d/2, and
# the limit that argument actually supports is 2*(LOAD - LOAD*LOW) = 4.8. It
# also fails to describe the event above: 8.32 is 4.3 clear of LOAD and half of
# 2.40 is 1.2, so the background moved a great deal further than the brackets
# caught.
#
# Which is the point, and the reason the spread is used as EVIDENCE and not as
# a bound. Three samples of a moving quantity put a LOWER bound on how far it
# moved and bound nothing from above. So the question asked here is not "could
# the drift account for the anomaly", which is unanswerable, but "was the
# background observably not holding still" -- and the threshold for that is a
# property of this machine, measured on it:
#
#   * 12 runs of check 1 at load average 1.5-2.8: the two baseline readings
#     disagreed by 0.01, 0.02, 0.04, 0.04, 0.06, 0.07, 0.08, 0.09, 0.15, 0.16,
#     0.18 and 0.80 cores.
#   * 22 runs of check 2 at load average 1.9-5.5, with 1.6 to 3.7 cores of
#     other work about: 0.01 to 0.93, median 0.16.
#
# 0.93 is the worst a merely busy machine produced over those 34 observations;
# 2.40 is what the churning one produced. BASELINE_MOVED sits in the gap, at
# more than twice the first and below the second, and both halves are
# load-bearing: much under 1.9 and it would start refusing ordinary runs, above
# 2.40 and it would not have caught the event it exists for. Said plainly: 34
# observations are not a distribution, and 0.80 being 4.4x the next worst says
# there is a tail here nobody has characterised. This is "nothing has come
# close", not "it cannot fire".
#
# One constant for both checks, because it is one physical quantity -- how far
# the background moved between two readings taken about seven seconds apart --
# and it does not become a different number because a different check took
# them.
#
# RETAKING. A spike that lives entirely BETWEEN the two baseline readings
# leaves them agreeing, so bracketing cannot see it, and one was measured here:
# 1 run in 12 moved check 2's reading by 1.74 cores with the machine otherwise
# near idle. Repetition is the only instrument that separates a spike from a
# defect, so an anomalous reading is taken again, up to ATTEMPTS times.
#
# The verdict is then decided by the BASELINES and not by a vote. If any
# attempt was anomalous while its own baseline held still, that is a defect and
# the answer is SELF-TEST FAILED however many of the others drifted. Only when
# every anomalous attempt came with a background that was visibly moving is
# there nothing to report. Written the other way round -- refuse if ANY attempt
# drifted -- a stubbed measurement plus one unlucky wobble escapes into exit 3,
# which is what the first draft of this did and what review caught.
#
# That is also why this is not "retry until green". Every defect these checks
# exist to catch is deterministic and comes with baselines that agree to two
# decimal places, so it is reported at the first attempt whose baseline held
# still. poc/02-lexer/run.sh is what keeps that true: it stubs
# busy_cpu_seconds() out and requires SELF-TEST FAILED from a copy that reaches
# check 1 and exhausts every retake.
#
# A NO VERDICT costs nothing in safety, and the callers are why: `just poc'
# treats exit 3 as neither a pass nor a failure and the suite still ends red.
# The asymmetry is deliberate -- a refusal is cheap, and a false SELF-TEST
# FAILED teaches people to discount a red gate.
ATTEMPTS = 3
BASELINE_MOVED = 2.0
SPIN = ("import time\n"
        "end = time.monotonic() + %f\n"
        "while time.monotonic() < end:\n"
        "    pass\n")
# wait4's rusage covers the descendants a child has reaped, so a child that
# forks OWN spinners and waits reports OWN cores' worth of CPU -- measured at
# 8.14 s of CPU over a 2.08 s window for OWN = 4.
FORK = ("import subprocess, sys\n"
        "kids = [subprocess.Popen([sys.executable, '-c', %r]) for _ in range(%d)]\n"
        "for k in kids:\n"
        "    k.wait()\n")
SLEEPER = "/bin/sleep"


def fail(msg):
    print(f"SELF-TEST FAILED: {msg}")
    sys.exit(contention.EXIT_FAIL)


def attempts():
    """`3 attempts' / `1 attempt' -- the count is a knob a guard case moves."""
    return f"{ATTEMPTS} attempt" + ("s" if ATTEMPTS != 1 else "")


def no_verdict(msg):
    """The measurement could not be taken, so there is nothing to report.

    Neither a pass nor a failure: the same third outcome the ladders render,
    and it has to stay distinguishable from both at every caller. The one thing
    it must never become is a quiet success.
    """
    print(f"NO VERDICT: {msg}")
    sys.exit(contention.EXIT_NO_VERDICT)


def idle_window():
    """Cores of other work, measured over a window in which we do nothing."""
    return contention.busiest(
        contention.rounds([[SLEEPER, str(contention.MIN_WINDOW)]], 1))


def busy_window():
    """The same, over a window in which children of ours burn OWN cores."""
    return contention.rounds(
        [[sys.executable, "-c", FORK % (SPIN % contention.MIN_WINDOW, OWN)]], 1)


if not os.access(SLEEPER, os.X_OK):
    contention.fault(f"no {SLEEPER} to measure an idle window with")
if len(sys.argv) != 2:
    contention.fault("usage: selftest.py SCRATCH_DIR")
scratch = pathlib.Path(sys.argv[1])
if not scratch.is_dir():
    contention.fault(f"{scratch} is not a directory to write check 0's trace into")

# --- -1. the sandbox did not take /proc and nproc with it -----------------
# Only when there IS a sandbox: this file is also runnable on its own, and a
# missing variable then means "nobody put one there" rather than "the sandbox
# lost it". Inside one, both variables are required -- poc/lib/sandbox.sh sets
# them unconditionally, so their absence is itself the defect.
if os.environ.get("NIXCC_SANDBOX"):
    try:
        host_cores = int(os.environ["NIXCC_HOST_CORES"])
        host_busy = float(os.environ["NIXCC_HOST_BUSY"])
    except (KeyError, ValueError) as e:
        contention.fault(
            f"running inside the harness sandbox, but the host's core count and "
            f"busy counter did not come in with it ({e}). Without them there is "
            f"no way to tell a /proc that describes this machine from one that "
            f"describes the sandbox, and every contention reading rests on that")
    seen_cores, seen_busy = contention.cores(), contention.busy_cpu_seconds()
    print(f"contention self-test: {seen_cores} cores and {seen_busy:.0f} busy "
          f"CPU-seconds inside the sandbox, {host_cores} and {host_busy:.0f} "
          f"outside it")
    if seen_cores != host_cores:
        fail(f"the host has {host_cores} cores and /proc reports {seen_cores} "
             f"inside the sandbox. The sandbox is virtualising the core count, "
             f"so every contention threshold in this tree is being compared "
             f"against the wrong machine")
    # Monotonic and plausible: the counter only climbs, and it cannot climb by
    # more than one core-second per core per second of wall clock. A namespaced
    # or reset /proc/stat shows up as a counter that went backwards or one that
    # bears no relation to the figure taken moments earlier.
    # The interesting half is monotonicity: a counter that went BACKWARDS is a
    # /proc that was reset or namespaced. The upper bound is deliberately loose
    # and does correspondingly little work -- the observed gap across the
    # sandbox's own start-up is a few tens of core-seconds, and this tolerates
    # ten minutes of the whole machine, so it catches a wildly different
    # counter and nothing subtler. Said plainly rather than dressed up as a
    # plausibility check.
    if not 0 <= seen_busy - host_busy <= host_cores * 600:
        fail(f"/proc/stat read {host_busy:.0f} busy CPU-seconds outside the "
             f"sandbox and {seen_busy:.0f} inside it. The two do not describe "
             f"the same machine's history, so the contention measurement is "
             f"reading something other than this host")

# --- 0. the rounds really are interleaved ---------------------------------
# Three jobs that do nothing but name themselves, so the trace file ends up
# holding the order they actually ran in. Three rather than two because two
# cannot tell a reversal apart from a rotation; two rounds rather than more
# because rounds() pads every round out to MIN_WINDOW and two are enough to
# separate blocked order, no alternation, and alternation the wrong way round.
# The file is named after this process and must not already exist: appending to
# somebody else's trace would read as a wrong order, and truncating one is the
# shape of cleanup this harness is getting rid of.
ORDER_ROUNDS = 2
NAMES = ["alpha", "bravo", "charlie"]
trace = scratch / f"rounds-order-{os.getpid()}.txt"
if trace.exists():
    contention.fault(f"{trace} already exists, so check 0 cannot tell what it "
                     f"wrote from what was already there")
# Python rather than `sh -c', so that the caller's directory reaches the job as
# a quoted literal instead of as shell syntax: a scratch path with a space in
# it would otherwise send the append somewhere else and this check would report
# a wrong ORDER for what is really a wrong PATH.
contention.rounds(
    [[sys.executable, "-c",
      f"open({str(trace)!r}, 'a').write({n!r} + chr(10))"] for n in NAMES],
    ORDER_ROUNDS)
# Each job ran ORDER_ROUNDS times, so the trace holds that many rounds' worth.
ran = trace.read_text().split()
want = []
for r in range(ORDER_ROUNDS):
    want.extend(reversed(NAMES) if r % 2 else NAMES)
print(f"contention self-test: {len(NAMES)} jobs over {ORDER_ROUNDS} rounds ran "
      f"as {' '.join(ran)}")
if ran != want:
    fail(f"rounds() ran its jobs as {' '.join(ran)}, wanted {' '.join(want)}. "
         f"It is measuring one job at a time, or not alternating the order "
         f"within a round -- which puts the largest ladder point last on the "
         f"warmest machine every time, and that is what made the lexer ladder "
         f"read SUPERLINEAR on a lexer nobody had touched")

# --- 0b. the estimator is the median of the per-round ratios -------------
# Costs chosen so that the four plausible answers are four different numbers:
# the per-round ratios are 1, 5 and 12, whose MEDIAN is 5, whose mean is 6,
# whose minimum is 1 and whose maximum is 12 -- and the quotient of the two
# points' cheapest rounds, which is what this replaced, is 1. Nothing here
# spawns a process; it is arithmetic on a NamedTuple, and it runs in
# microseconds.
_synthetic = contention.Ladder(points=(), foreign=(0.0,), windows=(1.0,))
_base = contention.Point("", 0.0, 0.0, 0, (1.0, 1.0, 1.0))
_a = contention.Point("", 0.0, 0.0, 0, (2.0, 2.0, 2.0))     # net 1, 1, 1
_z = contention.Point("", 0.0, 0.0, 0, (2.0, 6.0, 13.0))    # net 1, 5, 12
_got, _spread = contention.step_ratio(_synthetic, _base, _a, _z, "a synthetic ladder")
print(f"contention self-test: per-round ratios {_spread} judged as {_got}")
if _spread != (1.0, 5.0, 12.0):
    fail(f"step_ratio read the per-round ratios as {_spread}, not (1.0, 5.0, 12.0). "
         f"It is not dividing each round's costs by each other, or not net of "
         f"that round's own baseline")
if _got != 5.0:
    fail(f"step_ratio judged per-round ratios of {_spread} as {_got}, not their "
         f"median of 5.0. A minimum reads 1.0, a maximum 12.0, a mean 6.0, and "
         f"the quotient of the two points' cheapest rounds -- which is what this "
         f"replaced -- reads 1.0. Whichever of those it has become, every "
         f"linearity verdict in this tree now rests on a different statistic "
         f"from the one its tolerances were measured against")

free = contention.cores() - idle_window()
if free < LOAD + 2:
    # task-042: this says "not a verdict on anything" and then exits 2, which
    # every caller reads as a broken harness. A machine carrying ten cores of
    # somebody else's work is the third outcome, not a defect, and it is filed
    # rather than changed here because task-039 was bounded to the case where
    # the background MOVES rather than the case where it is simply large.
    contention.fault(
        f"only {free:.1f} of this machine's {contention.cores()} cores are "
        f"free; {LOAD} more put on it could not show up as {LOAD}, so the "
        f"contention measurement cannot be checked here. Not a verdict on "
        f"anything -- re-run on a less busy machine.")

# --- 1. load that is put on the machine is seen ---------------------------
def probe_added():
    """LOAD spin loops, bracketed: (baseline before, reading, baseline after).

    The baseline is read on BOTH sides rather than once beside the probe, so
    that a background ramping under the probe shows up as two readings that
    disagree instead of as LOAD cores that read wrong.
    """
    before = idle_window()
    spinners = [subprocess.Popen([sys.executable, "-c", SPIN % 30.0])
                for _ in range(LOAD)]
    try:
        time.sleep(0.3)                   # let them all reach the loop
        during = idle_window()
    finally:
        for s in spinners:
            s.kill()
        for s in spinners:
            s.wait()
    return before, during, idle_window()


steady, worst, readings = 0, 0.0, []
for attempt in range(1, ATTEMPTS + 1):
    before, during, after = probe_added()
    quiet, spread = (before + after) / 2, abs(after - before)
    added = during - quiet
    worst = max(worst, spread)
    readings.append(added)
    print(f"contention self-test: {quiet:.2f} cores busy with nothing of ours "
          f"running ({before:.2f} before, {after:.2f} after, {spread:.2f} "
          f"apart), {during:.2f} with {LOAD} spin loops, so {added:.2f} of "
          f"{LOAD} were seen")
    if LOAD * LOW <= added <= LOAD * HIGH:
        break
    if spread < BASELINE_MOVED:
        steady += 1
    if attempt < ATTEMPTS:
        print(f"contention self-test: {added:.2f} of {LOAD} is outside "
              f"{LOAD * LOW:.1f} to {LOAD * HIGH:.1f}; taking the reading "
              f"again ({attempt} of {ATTEMPTS - 1} retakes used)")
else:
    seen = ", ".join(f"{r:.2f}" for r in readings)
    if steady == 0:
        no_verdict(
            f"{LOAD} busy cores read as {seen} over {attempts()}, every "
            f"one outside {LOAD * LOW:.1f} to {LOAD * HIGH:.1f} -- and every "
            f"one taken against a baseline that moved under it, by up to "
            f"{worst:.2f} cores against the {BASELINE_MOVED:.1f} at which this "
            f"machine counts as no longer holding still. A background that is "
            f"moving is not a measurement that is broken: nothing is shown "
            f"about the contention guard either way. Re-run on a quieter "
            f"machine.")
    fail(f"{LOAD} busy cores read as {seen} over {attempts()}, every one "
         f"outside {LOAD * LOW:.1f} to {LOAD * HIGH:.1f}, and on {steady} of "
         f"them the baseline it was differenced against held still to within "
         f"{BASELINE_MOVED:.1f} cores, so the background cannot account for it. "
         f"The contention measurement is not measuring contention, and every "
         f"verdict either ladder renders rests on it")
# There used to be a second assertion here -- `if during < LOAD * LOW' --
# against a measurement "not reporting this machine's load at all". It is gone
# rather than repaired because it could not fire: reaching it means `added' was
# at least LOAD * LOW, so `during' is at least quiet + LOAD * LOW, and `quiet'
# is a contention reading that _round() floors at about -0.14 cores -- its skew
# allowance is 2 * cores / CLOCK_TICK = 0.28 core-SECONDS, and the figure
# returned is that over a window of MIN_WINDOW. It could only bite for a
# baseline in roughly [-0.14, 0). The defect it named -- a
# blinded reading of 0.0 -- is caught by the band above, which is what the
# lexer and matcher harnesses mutate against. A check that cannot fire is the
# shape this tree keeps shipping by accident, so it is recorded here rather
# than left standing as reassurance.

# --- 2. load that we put on the machine is not ----------------------------
def probe_own():
    """A child of ours burning OWN cores, bracketed the same way.

    Returns (baseline before, reading around our child, baseline after, that
    child's Point, the window it was measured over).
    """
    before = idle_window()
    ladder = busy_window()
    return (before, contention.busiest(ladder), idle_window(),
            ladder.points[0], ladder.windows[0])


steady, worst, readings = 0, 0.0, []
for attempt in range(1, ATTEMPTS + 1):
    alone_before, around_ours, alone_after, ours, window = probe_own()
    quiet, spread = (alone_before + alone_after) / 2, abs(alone_after - alone_before)
    moved = around_ours - quiet
    worst = max(worst, spread)
    readings.append(moved)
    print(f"contention self-test: {quiet:.2f} cores of other work around an "
          f"idle child ({alone_before:.2f} before, {alone_after:.2f} after, "
          f"{spread:.2f} apart), {around_ours:.2f} around ours burning "
          f"{ours.cpu:.1f} CPU seconds in a {window:.1f} s window, so it moved "
          f"the reading by {moved:.2f}")
    # Before the verdict, not after it: a child that did not burn what it was
    # asked to leaves this check with nothing to subtract, and that is a
    # harness fault rather than either answer about the guard.
    if ours.cpu < OWN * contention.MIN_WINDOW * 0.75:
        contention.fault(
            f"the child meant to burn {OWN} cores only used {ours.cpu:.1f} CPU "
            f"seconds over {window:.1f} s, so this check has nothing to "
            f"subtract and proves nothing")
    if moved <= OWN_CPU_SLACK:
        break
    if spread < BASELINE_MOVED:
        steady += 1
    if attempt < ATTEMPTS:
        print(f"contention self-test: {moved:.2f} is more than the "
              f"{OWN_CPU_SLACK:.1f} cores a child of ours may appear to move "
              f"the reading by; taking it again ({attempt} of {ATTEMPTS - 1} "
              f"retakes used)")
else:
    shown = ", ".join(f"{r:.2f}" for r in readings)
    if steady == 0:
        no_verdict(
            f"a child of ours burning {OWN} cores appeared to move the reading "
            f"by {shown} over {attempts()}, every one above the "
            f"{OWN_CPU_SLACK:.1f} cores it is allowed -- and every one taken "
            f"against a baseline that moved under it, by up to {worst:.2f} "
            f"cores against the {BASELINE_MOVED:.1f} at which this machine "
            f"counts as no longer holding still. Whether the guard subtracts "
            f"its own children's CPU is not shown either way. Re-run on a "
            f"quieter machine.")
    fail(f"a child of ours burning {OWN} cores moved the reading by {shown} "
         f"over {attempts()}, every one above the {OWN_CPU_SLACK:.1f} it "
         f"is allowed, and on {steady} of them the baseline held still to "
         f"within {BASELINE_MOVED:.1f} cores; the guard is counting its own "
         f"measurement as somebody else's load, which would refuse every ladder "
         f"forever")
print("the contention measurement sees other work and not its own")
