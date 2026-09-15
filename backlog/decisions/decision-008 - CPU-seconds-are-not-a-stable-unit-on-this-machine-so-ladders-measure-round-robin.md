---
id: decision-008
title: >-
  CPU seconds are not a stable unit on this machine, so ladders measure
  round-robin
date: '2026-09-15 10:47'
status: accepted
---
## Context

Three PoCs assert that a Nix pass is linear by comparing the evaluator's CPU
seconds across a size ladder. That comparison is only sound if a CPU second
means the same thing at every point of the ladder. On the machine this project
is developed on, an Intel Core Ultra 7 165U, it does not, and the ladders spent
four gate runs and four wrong diagnoses finding out.

Two effects, both measured here rather than read anywhere.

**The 14 "cores" are three different processors.** `lscpu -e` gives cpu0-3 as
P-cores capped at 4.9 GHz, cpu4-11 as E-cores at 3.8 and cpu12-13 as LP-E cores
at 2.1. The same 431 kB lexer ladder point, pinned with `taskset` and repeated
three times on each, costs 1.79 s of CPU on a P-core, 2.40 on an E-core and
3.93 on an LP-E core. That is 1.34x and 2.20x for byte-identical work, and
nothing in `wait4`'s rusage says which processor ran it.

**The P-cores do not hold their clock.** Six consecutive runs of that same
point, pinned to cpu0-3 and instrumented with `NIX_SHOW_STATS=1`, reported an
identical two GC cycles and an identical 541807808 totalBytes every time, and
cost 1.60, 1.60, 1.67, 1.66, 2.11 and 2.16 s. Same work, same allocation, same
core class, 35% more CPU seconds once the package had warmed up -- and the
slower state persisted rather than alternating.

Both effects are functions of WHEN a point is measured, and the ladders
measured block-wise, in ascending size order: every repeat of the smallest
point, then the next, up to the largest. That confounds "when" with "how big"
perfectly, and always in the same direction, because the largest point is
always measured last on the warmest machine. It is not a subtle bias:

  * Over five recorded gate runs the largest point never once reached the
    76-81k tokens/s the four smaller points sustained; it read 50-61k at every
    level of contention, including an idle machine at 0.54 busy cores.
  * Measured in DESCENDING order instead, on the same tree and the same
    machine, the ladder read SUBLINEAR: the last step came in at 0.83 to 1.01
    times its input ratio over five runs, and the end-to-end step as low as
    0.51. Ladder order alone moved the verdict from FAIL to a comfortable pass.

The effect was misdiagnosed three times as contention from other processes and
once as decision-001's large-working-set degradation. It is neither. The
contention guard was measuring a real thing that was mostly innocent, and
decision-001's "2.2 MB takes 18.3 s where the small-file rate predicts 14.5" is
about a working set four times larger than any ladder point here: measured
round-robin, the 500 MB point is not distinguishable from the 81 MB one.

## Decision

`poc/lib/contention.py`'s `rounds()` measures every ladder point once per
ROUND, round-robin, rather than one point at a time, with the within-round
order reversed on alternate rounds. Each point's figure is still the cheapest
of its runs, so each point is judged on its best observation of the same
sequence of machine states. The contention reading moves from per-point to
per-round, which is the granularity it can now be taken at, and a point's
figure is the worst round it was measured in.

The linearity tolerances do NOT move. Measured round-robin over six sessions on
this machine, the worst adjacent step anywhere in the lexer ladder came in at
1.052, 1.058, 1.060, 1.067, 1.077 and 1.092 against a tolerance of 1.35. The
readings that failed the gate were 1.39 and 1.71. Widening the tolerance to
cover those would have hidden an instrument fault behind a plausible constant,
which is the failure this project has now rejected three times.

Interleaving also retires a check that was proposed and not built: refusing a
STEP whose two endpoints were measured under materially different contention.
With every point measured in every round there is no such step, so the check
could never fire, and a check that cannot fire is the shape of harness this
project keeps shipping by accident.

`poc/lib/selftest.py` asserts the order rather than trusting the comment: three
jobs over two rounds must run alpha-bravo-charlie then charlie-bravo-alpha.
Blocked order, no alternation, and alternation the wrong way round all fail it.

## Consequences

Ladder numbers from before this change are not comparable with ones after it,
and the ones from before are biased against the top of the ladder. Any
throughput figure quoted from a task note older than this decision should be
re-measured before it is built on.

Every ladder point must now be measured before any of them can be judged, so a
ladder that is going to refuse at its bottom rung pays for the whole climb
first. That cost is real and was accepted: interleaving is not possible
otherwise.

Round-robin removes the confound between size and machine state. It does not
make a drifting clock go away -- a point measured on a P-core in one round and
an E-core in the next still has two readings 1.3x apart, and all interleaving
guarantees is that every point got the same chances. The residue is noise
rather than bias, and it is what the tolerances are measured against.

The honest fix for the residue would be to count cycles or retired
instructions rather than seconds, which is invariant to both effects.
`perf_event_open` can do it and this machine's `perf_event_paranoid` of 2 would
allow it, but that is a counter the harness cannot assume it may open -- not in
a container, not under a stricter paranoid level, and not inside the bubblewrap
sandbox task-034 is putting the harnesses in. It is filed rather than built.

A machine whose cores are homogeneous and whose clock is fixed -- most build
servers -- was never affected by any of this, and the change is a no-op for it
beyond the measurement order.
