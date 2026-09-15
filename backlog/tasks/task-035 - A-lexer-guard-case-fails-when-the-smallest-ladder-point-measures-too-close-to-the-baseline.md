---
id: TASK-035
title: >-
  A lexer guard case fails when the smallest ladder point measures too close to
  the baseline
status: Done
assignee: []
created_date: '2026-09-15 07:47'
updated_date: '2026-09-15 14:04'
labels:
  - poc
  - testing
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/02-lexer/run.sh's fourth contention-guard case -- "a reading that passes under contention is no verdict, not a PASS" -- intermittently fails the whole PoC with exit 1 rather than passing. Observed during task-024, on a tree where poc/02-lexer and poc/lib are untouched.

The guard case forces BUSY_FRACTION and BUSY_CEILING to -1.0 so that every reading counts as contended, and then requires the output to contain both "NO VERDICT" and "unjudged". "unjudged" is printed per ladder STEP, near the end of throughput.py, and is only reached if every ladder point was measured.

There is an earlier refusal that skips it. In throughput.py's measurement loop:

    if work < base_cpu * MIN_BASELINE_RATIO:
        contention.require_quiet([("baseline", base), (f"{nbytes} bytes", point)], "lexer")
        fault(...this ladder point is too small to measure...)

That cliff fires when the smallest point's CPU is not comfortably above the evaluator's start-up baseline -- a timing accident, not a property of the lexer. When it fires under the forced threshold, require_quiet refuses immediately and the run exits 3 having printed NO VERDICT and never the word "unjudged". The guard case sees the right exit status, the wrong text, and reports a harness failure.

Observed output:

    GUARD CASE 'a reading that passes under contention is no verdict, not a PASS' never said "unjudged":
    NO VERDICT: other work occupied up to 1.01 of this machine's 14 cores ... over the -14.00 ...
          baseline:  1.01 cores of other work over 2.0 s  <--
       31025 bytes:  0.69 cores of other work over 2.0 s  <--

Note 1.01 cores: the machine was essentially IDLE. It is the -14.00 threshold, which the guard case itself set, that made the baseline count as contended.

Two candidate fixes, and they are not the same claim:
  * The guard case should accept EITHER refusal path, because both are the refusal it is testing for. Cheapest, and arguably what it meant all along.
  * Or the too-small-to-measure cliff should not consult the contention guard at all when the guard has been told everything is contended, because then it reports the wrong cause.

poc/03-matcher/run.sh and poc/04-assembler/run.sh carry the same guard_case shape and may have the same hole; only the lexer has been seen to hit it, because its smallest ladder point is the one closest to the baseline.

Found while running the gate for task-024.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The guard case passes on an idle machine and on a busy one, whichever refusal path the ladder takes
- [x] #2 If the too-small-to-measure cliff can still be reported as contention, the diagnostic says which of the two it is
- [x] #3 The matcher and assembler ladders are checked for the same hole and either fixed or shown not to have it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Re-measure the lexer ladder on the now-quiet machine: N full runs, recording per-point tokens/s, peak RSS and busy cores, plus the ratio-of-ratios for every adjacent step. Keep the raw log.
2. Shared fix in poc/lib/contention.py: a STEP whose two endpoints were measured under materially different contention is not comparable and is not judged, whatever the absolute numbers were. Margin measured, not guessed. An unjudged step may never leave a PASS behind: the ladder renders NO VERDICT, and a real FAIL on a comparable step still outranks it.
3. Lexer tolerance for the large-working-set step, keyed on peak RSS rather than on step index, with the number taken from step 1 and cited in the source alongside decision-001. Not a widened TOLERANCE.
4. The too-small-to-measure cliff: one diagnostic that names BOTH candidate causes rather than blaming contention alone (criterion #2), and guard cases that accept either refusal path while still proving which one was taken (criterion #1).
5. Check matcher and assembler ladders for the same holes; fix or show absent (criterion #3).
6. Prove the new machinery with mutations: a harness that cannot fail is the failure mode this project has shipped six times.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SECOND SYMPTOM, same family, observed during the task-023/024/025 batch on a tree where poc/02-lexer and poc/lib are untouched.

The lexer ladder rendered a FAIL -- not a NO VERDICT -- on its largest point:

       223124 ->   430998: 1.93x input, 3.30x CPU  SUPERLINEAR
        31025 ->   430998: 13.89x input, 24.07x CPU  SUPERLINEAR
    FAIL: 223124 -> 430998 bytes grew 1.93x but cost 3.30x CPU

The three smaller steps read 1.95x, 1.96x and 1.90x in the same run, so the lexer is linear and the largest point alone was distorted. The contention guard measured 1.97 busy cores at that point -- comfortably under the 3.50 threshold -- so it rendered a verdict against a reading it should not have.

THE GUARD IS MEASURING THE WRONG RESOURCE FOR THAT POINT. busy_cpu_seconds counts other processes' CPU time. The largest ladder point holds a 500 MB working set (decision-001: memory is the binding constraint, not throughput), and what distorts it is memory bandwidth and page-cache pressure from other processes, which barely register as CPU. Three other Claude sessions and a browser were resident at the time. A machine can be quiet by the guard's measure and still be a bad place to measure a half-gigabyte working set.

So the two symptoms have one shape: the guard's threshold is a proxy, and the ladder trusts it at both ends -- refusing when the proxy is high even though nothing is wrong (the first note), and rendering a verdict when the proxy is low even though the reading is distorted (this one). The second is the dangerous direction: it is a red gate on a correct compiler, and the obvious response to a red gate on correct code is to widen the tolerance, which is how a check gets quietly disabled.

Worth considering as part of the fix: a memory-pressure term alongside the CPU one (available memory, or major faults during the window), or dropping the largest point from the ratio when its RSS is within some fraction of the ceiling.

THIRD SYMPTOM, same machinery, same batch, poc/lib still untouched. The contention SELF-TEST failed:

    contention self-test: 2.91 cores busy with nothing of ours running (1.71 before, 4.11 after), 11.23 with 4 spin loops, so 8.32 of 4 were seen
    SELF-TEST FAILED: 4 busy cores read as 8.32, outside 1.6 to 6.8

Look at the baseline it printed: 1.71 cores before the window and 4.11 after. Other work MORE THAN DOUBLED while the self-test was measuring, and the self-test attributes the whole difference to its own four spin loops, so four cores read as 8.32 and it declares its own measurement broken.

It is not broken; it was asked an unanswerable question. selftest.py takes a baseline, adds a known load, measures again, and differences the two. That is only valid if the background is stationary across the window, and on a machine where other sessions come and go it is not. The self-test already brackets its baseline (before and after) and PRINTS both -- it just does not use the spread between them. If 1.71 and 4.11 bracket the baseline, the honest conclusion is that the baseline is unknown to within 2.4 cores, which swamps a 4-core probe, and the right outcome is NO VERDICT rather than SELF-TEST FAILED.

That makes three distinct outcomes from this machinery seen in one batch of work, all on an untouched poc/02-lexer and poc/lib:
  1. a guard case fails because the ladder took the other refusal path (the original note)
  2. a ladder renders a FAIL on a reading distorted by memory pressure the guard does not measure (the second note)
  3. the self-test declares itself broken because the background moved under it (this one)

All three have the same root: a single scalar taken at one moment is being used as if it described a whole window. The bracketing data needed to notice is already collected in case 3 and could be collected cheaply in the others.

FOURTH INSTANCE, and the clearest, because the evidence is printed on the same lines. The lexer ladder rendered a FAIL and the table shows exactly which point was distorted:

       nodes   bytes    ...   cpu s   ...   peak RSS   busy cores
        2306   62419           0.25         123 MB        0.83
        4564  119926           0.51         205 MB        3.17   <-- this one
        8613  223124           1.33         347 MB        0.97
       16720  430998           2.38         501 MB        0.85

       119926 ->   223124: 1.86x input, 2.62x CPU  SUPERLINEAR
       FAIL: 119926 -> 223124 bytes grew 1.86x but cost 2.62x CPU

Every other point measured under one busy core; the 119926-byte point measured 3.17. The step that failed is the step out of it, and it failed because the DENOMINATOR was inflated -- 0.51 s where the trend says about 0.70 -- not because the numerator was. A contended point makes the step INTO it look cheap and the step OUT of it look expensive, and only the second is reported.

3.17 is under the 3.50 threshold, so the guard rendered a verdict. That is the threshold doing what it was told: it is a single all-or-nothing cut, and a point at 90% of it is still distorted enough to move a ratio by 40%.

The fix this suggests is cheaper than the memory-pressure work in the earlier note and probably wants doing first: the ladder already records busy cores PER POINT. A step whose two endpoints were measured under materially different contention is not comparable, whatever the absolute numbers were. Refusing a STEP -- rather than the whole ladder -- when its endpoints' contention readings differ by more than some margin would have caught all four instances recorded on this task, and would have kept the three good steps in this run.

Counted across this batch: four gate runs lost to this machinery, in four distinct ways, on a poc/02-lexer and poc/lib that no commit in the batch touches.

THE DIAGNOSIS CHANGES. It is probably not contention at all, and decision-001 already predicted it.

The largest lexer ladder point, across five gate runs in this batch:

    run            busy cores   347 MB point    500 MB point
    e2e-hello5        0.90/0.64    55870 tok/s     54723 tok/s   PASS
    e2e-025b          0.77/0.61    78854           61493         PASS
    e2e-024g          1.67/1.51    46389           50569         PASS
    e2e-final         0.97/0.85    51906           55710         FAIL
    e2e-final2        0.54/0.59    76262           54855         FAIL

The 500 MB point is RELIABLY 50-61k tokens/s -- it never once reached the 77-81k the four smaller points sustain, at any level of contention including 0.59 cores, which is an idle machine. That is not noise. The four smaller points run at 76-81k every time.

The noisy one is the PENULTIMATE point, 347 MB, which has measured anywhere from 46k to 79k. The ladder passes or fails on which of those it happens to get: a fast 347 MB reading makes the step into 500 MB look superlinear, a slow one hides it.

So the underlying fact is stable and unreported, and the verdict is a coin flip on a different point's noise.

DECISION-001 ALREADY RECORDS THIS EFFECT: '2.2 MB costs 976 MB and takes 18.3 s where the small-file rate predicts 14.5'. That is the same 25-30% degradation at a large working set, measured a wave earlier and written down as the thing to watch. What is wrong is not the lexer and not the machine -- it is that the ladder's linearity tolerance does not account for an effect this project has already decided is real and expected.

That makes the fix a different one from anything above: either the ladder's largest point has to sit below the working set where the evaluator's own overhead bends the curve, or the tolerance for the last step has to be set from the measured degradation rather than from the same constant as the others. Dropping the largest point would be a loss -- it is the only one that exercises the regime decision-001 cares about -- so the second is probably right, with the number taken from a run on a quiet machine and cited.

The three earlier notes on this task stand as separate symptoms of the guard machinery. This one says the guard was mostly innocent: the ladder is failing on a real, documented, expected property of the evaluator, and reading it as contention sent four investigations in the wrong direction -- including two of mine.

THE DIAGNOSIS CHANGES A FIFTH TIME, and this one is measured three independent ways. It is not contention, not memory pressure, not GC, and not decision-001's large-working-set degradation. **A CPU second is not a stable unit on this machine, and the ladder measured its points in an order that confounded that perfectly with size.**

Evidence, all taken today on the now-quiet machine (load ~2, down from 9-20).

1. UNPINNED, the old block-order ladder reproduces the fault in ten runs. The 500 MB point read 70349, 70677, 70131, 69027, then 56373, 56157, 56946, 54297, 56947, 48335 tokens/s while the four smaller points held 75-87k throughout and busy cores never left 0.45-0.70. Runs 6 and 8 rendered FAIL. So the largest point degrades over a session with the machine idle by every measure the guard has.

2. PINNED, the cause is visible. `taskset` the same 431 kB point, three repetitions each:

       cpu0  (P-core,   4.9 GHz)  1.79 / 1.79 / 1.80 s CPU
       cpu4  (E-core,   3.8 GHz)  2.43 / 2.40 / 2.39
       cpu12 (LP-E,     2.1 GHz)  3.92 / 3.97 / 3.93

   1.34x and 2.20x for byte-identical work, and rusage does not say which processor ran it. lscpu -e confirms three classes: cpu0-3 at 4900 MHz, cpu4-11 at 3800, cpu12-13 at 2100. This is an Intel Core Ultra 7 165U -- `14 cores' is three different CPUs.

3. NIX_SHOW_STATS rules out the workload. Six consecutive runs of that point pinned to cpu0-3, every one reporting an identical 2 GC cycles and an identical 541807808 totalBytes: 1.60, 1.60, 1.67, 1.66, 2.11, 2.16 s. Same work, same allocation, same core class, 35% more CPU seconds once the package warmed up -- and it stayed slow rather than alternating. Direct-reclaim counters (pgscan_direct, pgsteal_direct, allocstall_*) were zero throughout and MemAvailable was flat at 9.8 GB, so the memory-pressure hypothesis from the second note is dead too.

4. THE CONTROL that settles it: run the ladder in DESCENDING size order, so the largest point is measured first on a cool machine and the smallest last on a warm one. Five runs, same tree, same machine, last step and end-to-end:

       1.96x / 7.02x   1.80x / 7.99x   1.82x / 13.87x   1.67x / 11.55x   1.61x / 9.75x

   against a 1.93x and 13.89x input ratio. The ladder reads SUBLINEAR, end-to-end as low as 0.51 of its input ratio, and the smallest point drops to 38066 tok/s. Measurement ORDER alone moves the verdict from FAIL to a comfortable pass. The lexer is not superlinear at the top of the ladder; it is measured last.

WHAT LANDED, and the number the brief asked for.

poc/lib/contention.py gains rounds(): every ladder point is measured once per ROUND, round-robin, with the within-round order reversed on alternate rounds, and each point's figure is the cheapest of its runs. best() becomes a one-job wrapper on it. Contention moves from a per-point window to a per-round window -- a round is 4-6 s, which is where /proc/stat's whole-tick quantisation is small -- and a point's figure is the worst round it was measured in. A Ladder NamedTuple carries the per-round figures so report() and require_quiet() can show them. All three ladders and poc/05-loop/measure.py go through it. decision-008 records the finding.

THE TOLERANCE DID NOT MOVE, and that is the answer rather than an omission. Measured round-robin over six sessions, the worst adjacent step ANYWHERE in the lexer ladder came in at 1.052, 1.058, 1.060, 1.067, 1.077 and 1.092, and end-to-end at 0.95 to 1.11. TOLERANCE is 1.35 and END_TO_END_TOLERANCE 1.5. The readings that failed the gate were 1.39 and 1.71; covering those would have needed 1.75, which is 'widen it until it goes green'. The largest step is not distinguishable from the other three once the order is fixed, so there is no large-working-set degradation at 500 MB to give its own constant. decision-001's 26% is at 976 MB and 2.2 MB of input, four times any ladder point here, and it may itself have been measured under this same confound -- worth re-measuring before anything is built on it. The measured figures are cited in throughput.py above TOLERANCE.

THE PER-STEP COMPARABILITY CHECK WAS NOT BUILT, deliberately. The brief suggested refusing a step whose two endpoints were measured under materially different contention. With every point now measured in every round there is no such step: the endpoints share their rounds by construction. Building it anyway would have produced a check that cannot fire, which is the failure mode this project has shipped six times. Said here rather than quietly dropped.

Criterion #1: guard_case in poc/02-lexer/run.sh and poc/03-matcher/run.sh now takes a SET of acceptable fragments ('unjudged|too small to measure') for the refusal cases, so either refusal path passes. The control cases -- contention discounted, which must still render a real PASS or a real FAIL -- are what stops that being a free pass.

Criterion #2: the cliff moves into a shared contention.too_small(). It names the reading, then says which of the two causes it is: on a quiet machine a HARNESS FAULT ('the ladder wants a bigger smallest point, not a quieter machine', exit 2), on a busy one a NO VERDICT that states plainly that contention inflates the baseline this cliff compares against and that the two 'cannot be told apart from here' (exit 3). Two new guard cases force the cliff deterministically by setting MIN_BASELINE_RATIO to 1e6, one at each threshold, and each forbids the other's fragment -- so the discrimination is tested, not asserted.

Criterion #3: the matcher HAD the same hole (same guard_case shape, same 'unjudged' requirement, same cliff) and is fixed the same way, cliff cases included. The assembler has no guard_case block at all -- it delegates that proof to the matcher's -- but its scale.py carried the same cliff and now uses the shared one.

PROOF THE NEW MACHINERY IS REAL. poc/lib/selftest.py gains check 0: three jobs over two rounds must run alpha-bravo-charlie then charlie-bravo-alpha, read back from a trace the jobs themselves write. Blocked order, no alternation, and alternation the wrong way round all fail it. It is first because it is structural and still runs on a machine too busy for the two statistical checks. selftest.py now takes a scratch directory argument, owned by the caller.

GATE, measured on this machine within the same hour:

    pre-change tree (clone of 8f42068)   7m10  exit 3  -- 3 of 5 PoCs rendered NO VERDICT
    changed tree                         7m22  exit 0  -- 5 PoCs passed
    changed tree                         7m28  exit 0  -- 5 PoCs passed
    changed tree                         6m15  exit 0  -- 5 PoCs passed

The +2-4% is the two new guard cases and check 0's padding; interleaving itself saves padding, since a ladder now pads 3 rounds rather than 6 points to MIN_WINDOW.

LIMITS. Round-robin removes the BIAS, not the noise: a point measured on a P-core in one round and an E-core in the next still has two readings 1.3x apart, and that residue is what 1.35 absorbs. Counting retired instructions would be invariant to both effects and is filed as task-038 rather than built, because it needs a perf counter the harness cannot assume it may open. The third symptom on this task -- the self-test declaring itself broken when the background load moves under it -- is NOT fixed here and is filed as task-039.

WHAT THE TWO REVIEWERS CHANGED, because both independently attacked the same weakest point and both were right.

The first draft relaxed two guard cases to accept EITHER refusal fragment ('unjudged' or 'too small to measure'). mped-architect called that a workaround and qa-test-runner showed what it cost: if the cliff starts firing every run, those two cases silently become duplicates of the two cliff cases, the suite stays green, and 'a PASS measured under contention becomes NO VERDICT rather than PASS' loses all coverage with nothing saying so. That is the harness-that-cannot-fail shape, reintroduced while fixing something else.

The deterministic fix, and it deletes code rather than adding it: every guard case now PINS MIN_BASELINE_RATIO. The four contention cases set it to 0.0, which makes the cliff 'work < 0' and therefore unreachable, so 'unjudged' is a hard requirement again and those four exercise require_quiet on every run. The two cliff cases set it to 1e6, which makes every point too small on any machine. The variable is removed rather than the answer widened. The alternation machinery and one parameter went with it. It also closes a hole qa-test-runner found on the other side: with the cliff live, the JUDGED cases could flake with exit 2, and the observed margin was only 1.3x.

Other review findings acted on, all in this change:
  * Point.foreign and Point.window are gone. They held the whole session's worst round copied onto every row -- derived state stored once per point -- and made too_small()'s diagnostic name a per-point granularity that no longer exists. Contention lives on the Ladder, which is the honest granularity once the points are interleaved. best() went with them; selftest.py calls rounds() directly.
  * contention.ladder(), baseline_argv() and bench_argv() replace twelve identical lines in each of three ladders. 'the baseline is job 0' was an unwritten positional contract in four files: reorder the list and every row is compared against the wrong baseline and the ladder still passes.
  * zip(files, points, strict=True). A silently truncated zip is how this repo's first harness reported '48 instructions compared / PASS' having compared nothing.
  * too_small() now prints the per-round contention table before it refuses. It exits before the ladder's own machine line, so a refusal naming contention as a candidate cause was asking the reader to take the contention on trust.
  * guard_case takes NAME=VALUE arguments. At nine positionals the call sites were an unlabelled list of numbers and quoted strings, and the function needed a paragraph to decode its own signature. mkdir -p became plain mkdir, since the comment above it says 'never a reused one' and -p accepts one.
  * The per-round CPU column width is computed from REPEATS. Hardcoded at 24 it was exactly saturated at REPEATS = 5, and the first point to cross 10 s CPU would have pushed the table out of line.
  * Wrong comments fixed: the skew arithmetic in _round() (one tick on 14 cores at 100 Hz is 0.14 core-seconds, not 0.28; over MIN_WINDOW that is under a tenth of a core, not 'a few hundredths'), two 'see best()' cross-references to a function that no longer contains the argument, 'both timing ladders' where there are three, 'the four cases' where there are six in two files and none in the third, a claim that this machine idles at 3.6-4.7 cores which is no longer true, and a mangled line wrap in the threshold rationale.
  * poc/lib/selftest.py check 0 builds its jobs with sys.executable and a repr'd path instead of interpolating a caller-supplied directory into 'sh -c': a scratch path with a space in it would have reported a wrong ORDER for what was really a wrong PATH.

TWO LIMITS THE REVIEW SURFACED, now written into contention.py's LIMITS rather than left to be discovered:
  * Interleaving cost the contention reading TEMPORAL RESOLUTION. Block order gave one window per point -- six short ones for the lexer -- and took the worst; round-robin gives one per round, three, each covering the whole ladder. A two-second burst of eight cores used to read 8.0 on the point it hit; spread over a six-second round it reads 2.7 and clears the 3.5 ceiling. Sustained load is seen as before; a transient burst is about 3x harder to see. Taken that way because sampling between the children inside a round puts /proc/stat's whole-tick quantisation back on the short jobs, where one round of the smallest point is 0.15 s against a 0.14 core-second tick error.
  * Round-robin's residual is ASSUMED to be noise, not shown to be. Every point now runs immediately after a differently sized one, so each pays a cache-eviction cost the others set -- closer to a fixed adder than a proportional one, which costs the small points relatively more and bends the ratios towards SUBLINEAR. That is the direction the module's own docstring calls dangerous. task-038 (count retired instructions) is the fix; this is why it is filed rather than shrugged off.

NOT ACTED ON, and named rather than buried: qa-test-runner found that selftest.py check 1's SECOND assertion ('the measurement is not reporting this machine's load at all') is effectively unreachable, since reaching it means the first already passed. Pre-existing, and touching self-test semantics risks the blinded-mutation contract that the lexer and matcher harnesses depend on, so it is carried onto task-039 with the rest of the self-test work rather than changed here.

Landed as 678d352. Gate output on that commit: 7m09, exit 0, 5 PoCs passed, lint clean, 14 guard cases (7 lexer, 7 matcher) and 106 mutations across the five PoCs all caught, on a machine carrying 1 to 6.75 cores of other work during the run.

Criterion status, and one of them is NOT met as written:
  #1 MET, though by removing the ambiguity rather than tolerating it. The guard cases pass on an idle machine and on a busy one because the cliff is now pinned out of reach in the four contention cases and driven deliberately in two new ones -- so a case no longer takes 'whichever refusal path' by accident. Read strictly, the criterion asks for the guard case to accept either path; what landed makes the path deterministic instead. That is stronger, but it is a different thing from what the criterion says, so it is flagged rather than ticked quietly.
  #2 MET. contention.too_small() names the cause: HARNESS FAULT and 'the ladder wants a bigger smallest point, not a quieter machine' on a quiet machine, NO VERDICT and 'cannot be told apart from here' on a busy one, with the per-round contention table printed either way. Two guard cases force each branch and each forbids the other's fragment.
  #3 MET. The matcher had the same hole and is fixed identically, cliff cases included. The assembler has no guard_case block -- it delegates that proof to the matcher's -- but its scale.py carried the same cliff and now uses the shared one; checked and reported rather than assumed.

The headline complaint on this task -- the intermittent red -- is fixed by the round-robin change rather than by any of the three criteria, which were written against the first of five diagnoses.

REOPENED BRIEFLY AFTER 678d352: the estimator was still wrong in one place, and a gate run found it.

The lexer ladder rendered a FAIL on the END-TO-END step, 20.85x CPU for 13.89x input, a ratio of 1.50 against the 1.5 ceiling. The table beneath it:

    31 kB point   0.15 / 0.22 / 0.23 s CPU across the three rounds
    431 kB point  2.70 / 2.73 / 3.18

Nothing there is a superlinear lexer. What it is: the ROUND-ROBIN change made every point's headline figure the cheapest of its rounds, and a minimum is biased low by an amount that grows with the noise. The 31 kB point runs for 0.13 s, where evaluator start-up transients are a large fraction of the measurement, so its minimum is flattered far more than the 431 kB point's -- and it is the denominator of BOTH the first adjacent step and the end-to-end step, so one lucky reading of it moves two verdicts at once.

Read as three complete ratios instead, one per round, the same three rounds give 1.53, 1.07 and 1.13. The median is 1.13.

So contention.step_ratio() now measures the RATIO rather than assembling one afterwards out of two independently-minimised numbers: net of each round's own baseline, once per round, median across rounds. Two reasons rather than one. Within a round the endpoints are measured seconds apart on the same clock, so their ratio is invariant to the drift decision-008 records rather than merely averaged over it; across rounds a median rejects a bad round in EITHER direction, where a minimum only ever rejects in the direction that flatters. The per-round ratios are printed beside each step, so a reader can see the spread the verdict was taken from -- and can see why dividing the table's two cpu columns does not reproduce it.

Checked against 14 recorded round-robin sessions: the two estimators agree to within about 0.05 on a quiet machine (worst adjacent step 1.02-1.18 for the minima, 0.99-1.16 for the medians; end-to-end 0.87-1.16 and 0.84-1.11). They differ where it matters -- on the run with one flattering reading in it, which is the run that failed the gate.

The tolerances still did not move.

CORRECTION TO THE PROVENANCE OF ONE CITED FIGURE, prompted by the machine going to load 36 under an unrelated PDF-extraction job and by a reminder to check what was measured when.

Commit bf0170b's message says the two estimators were 'checked against fourteen recorded round-robin sessions ... agree to within about 0.05 on a quiet machine'. Eight of those fourteen were recorded at 14:44, on a machine whose worst per-run contention reading was 8.39 cores -- over the 3.50 the ladders refuse at. That set should not have been described as quiet. Split by the threshold the tree actually uses:

    under 3.5 busy cores (9 sessions, worst 3.36):
       minima-quotient    worst step 1.046-1.134   end-to-end 0.946-1.097
       per-round median   worst step 1.060-1.137   end-to-end 0.955-1.108
    over 3.5 busy cores (5 sessions, worst 8.39):
       minima-quotient    worst step 1.023-1.179   end-to-end 0.873-1.164
       per-round median   worst step 0.995-1.163   end-to-end 0.836-1.072

The conclusion is unchanged and the nine clean sessions carry it on their own: the two estimators agree closely on a quiet machine and part company on a run with one flattering reading in it. The argument for the median was never the dataset anyway -- it is that a minimum is biased low by an amount that grows with the noise, and the smallest ladder point is both the noisiest and the denominator of two steps. But 'fourteen sessions on a quiet machine' overstates what was recorded, so it is corrected here rather than left standing.

NO TOLERANCE OR THRESHOLD CONSTANT MOVED IN ANY COMMIT OF THIS BATCH. Checked mechanically rather than from memory: a diff of TOLERANCE, END_TO_END_TOLERANCE, MIN_BASELINE_RATIO, MIN_SPAN, BUSY_FRACTION, BUSY_CEILING, MIN_WINDOW and every MAX_* across 678d352~1..HEAD is empty. That is the point of the task's finding -- the constants were right and the measurement order was wrong -- so there is no number in this work that could have been contaminated by a busy window. The figures that ARE cited in source (the pinned per-core costs 1.79/2.40/3.93 s, the six NIX_SHOW_STATS runs, the descending-order control, and the 1.052-1.092 worst-step range quoted above TOLERANCE) were all taken between 11:45 and 13:10 at 0.5 to 2.3 busy cores, and every one of them argues for leaving a constant alone.
<!-- SECTION:NOTES:END -->
