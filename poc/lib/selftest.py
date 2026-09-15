#!/usr/bin/env python3
"""Prove that contention.py MEASURES, not just that it decides.

The guard cases each ladder's run.sh runs move the threshold to force the
decision one way or the other. None of them can see a broken measurement: stub
busy_cpu_seconds() out to return 0.0 and every one of them still passes,
because they never produce contention -- they declare it. That is the
fail-open half of the guard, and this is what covers it.

Three checks, each for a defect the others cannot see.

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

Deliberately not a test of the threshold, of the ladders, or of nix: it spawns
no evaluator and takes about twenty seconds.

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

free = contention.cores() - idle_window()
if free < LOAD + 2:
    contention.fault(
        f"only {free:.1f} of this machine's {contention.cores()} cores are "
        f"free; {LOAD} more put on it could not show up as {LOAD}, so the "
        f"contention measurement cannot be checked here. Not a verdict on "
        f"anything -- re-run on a less busy machine.")

# --- 1. load that is put on the machine is seen ---------------------------
before = idle_window()
spinners = [subprocess.Popen([sys.executable, "-c", SPIN % 30.0])
            for _ in range(LOAD)]
try:
    time.sleep(0.3)                       # let them all reach the loop
    during = idle_window()
finally:
    for s in spinners:
        s.kill()
    for s in spinners:
        s.wait()
after = idle_window()

quiet = (before + after) / 2
added = during - quiet
print(f"contention self-test: {quiet:.2f} cores busy with nothing of ours "
      f"running ({before:.2f} before, {after:.2f} after), {during:.2f} with "
      f"{LOAD} spin loops, so {added:.2f} of {LOAD} were seen")
if not LOAD * LOW <= added <= LOAD * HIGH:
    fail(f"{LOAD} busy cores read as {added:.2f}, outside {LOAD * LOW:.1f} to "
         f"{LOAD * HIGH:.1f}. The contention measurement is not measuring "
         f"contention, and every verdict either ladder renders rests on it")
if during < LOAD * LOW:
    fail(f"{LOAD} busy cores read as an absolute {during:.2f}; the measurement "
         f"is not reporting this machine's load at all")

# --- 2. load that we put on the machine is not ----------------------------
ladder = busy_window()
ours, seen, window = ladder.points[0], contention.busiest(ladder), ladder.windows[0]
alone = idle_window()
print(f"contention self-test: {alone:.2f} cores of other work around an idle "
      f"child, {seen:.2f} around ours burning {ours.cpu:.1f} CPU "
      f"seconds in a {window:.1f} s window")
if ours.cpu < OWN * contention.MIN_WINDOW * 0.75:
    contention.fault(
        f"the child meant to burn {OWN} cores only used {ours.cpu:.1f} CPU "
        f"seconds over {window:.1f} s, so this check has nothing to "
        f"subtract and proves nothing")
if seen - alone > OWN_CPU_SLACK:
    fail(f"a child of ours burning {OWN} cores moved the reading by "
         f"{seen - alone:.2f}; the guard is counting its own "
         f"measurement as somebody else's load, which would refuse every "
         f"ladder forever")
print(f"the contention measurement sees other work and not its own")
