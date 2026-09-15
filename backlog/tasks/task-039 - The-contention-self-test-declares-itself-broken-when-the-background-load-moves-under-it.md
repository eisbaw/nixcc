---
id: TASK-039
title: >-
  The contention self-test declares itself broken when the background load moves
  under it
status: Done
assignee: []
created_date: '2026-09-15 10:48'
updated_date: '2026-09-15 15:39'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Third symptom recorded on task-035, and NOT fixed by the round-robin work there. Seen in the wild:

    contention self-test: 2.91 cores busy with nothing of ours running (1.71 before, 4.11 after), 11.23 with 4 spin loops, so 8.32 of 4 were seen
    SELF-TEST FAILED: 4 busy cores read as 8.32, outside 1.6 to 6.8

The measurement is not broken; it was asked an unanswerable question. poc/lib/selftest.py check 1 takes a baseline, adds a known load, measures again, and differences the two. That is only valid if the background is stationary across the window. Here it went from 1.71 to 4.11 cores while the check ran, and the whole 2.4-core difference was attributed to the four spin loops.

The bracketing data needed to notice is ALREADY collected and already printed -- the before and after readings -- and simply not used. If the two bracket readings are 2.4 cores apart, the baseline is unknown to within 2.4 cores, which swamps a 4-core probe, and the honest outcome is NO VERDICT (exit 3) rather than SELF-TEST FAILED (exit 1).

Order matters: this must not become a way for a genuinely blinded measurement to escape. poc/02-lexer/run.sh and poc/03-matcher/run.sh stub busy_cpu_seconds() out to 0.0 and require SELF-TEST FAILED; with the stub in place both bracket readings are 0.0, so they agree perfectly and the new refusal must not fire. Check that, because that is exactly the hole this kind of change opens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A self-test whose two bracket readings of the baseline disagree by enough to swamp the probe renders NO VERDICT and exits 3, not SELF-TEST FAILED
- [x] #2 The margin is measured on this machine and cited in the source, not chosen to make a red run go green
- [x] #3 The blinded-measurement mutation in the lexer and matcher harnesses still reports SELF-TEST FAILED: a stubbed reading agrees with itself, and agreeing with itself must not buy an escape
- [x] #4 A run that renders NO VERDICT here does not let the PoC that called it report a pass
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Measure on this machine how far apart check 1's two bracket readings normally drift, over repeated runs, and record the spread.
2. Add a bracket-disagreement refusal to poc/lib/selftest.py check 1: if |after - before| is large enough that the background alone could carry `added' outside the accept band, render NO VERDICT (exit 3) rather than SELF-TEST FAILED. Margin derived from the band itself (LOAD - LOAD*LOW), cross-checked against the measured spread so it cannot fire on an ordinary quiet run.
3. Retake the bracket a bounded number of times before refusing: a drifting background is transient, and a refusal that fires on the first spike would trade a flaky red for a flaky no-verdict.
4. Order it so it cannot buy an escape: the refusal is only reachable when the two readings DISAGREE, so a stubbed measurement (both 0.0) still reaches the accept-band check and still says SELF-TEST FAILED. Demonstrate that against the blinded copy both inside and outside the sandbox.
5. Deal with the unreachable second assertion (during < LOAD*LOW) named in the task notes: reachable form or removed with the reason recorded.
6. Make the callers treat a NO VERDICT self-test as NO VERDICT for the PoC -- never a pass.
7. Evidence: consecutive gate runs with the machine's load recorded.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Second defect in the same file, found by qa-test-runner while reviewing task-035. poc/lib/selftest.py check 1 ends with two assertions:

    if not LOAD * LOW <= added <= LOAD * HIGH:  fail(...)
    if during < LOAD * LOW:                     fail(... 'not reporting this machine's load at all')

The second cannot fire in practice. Reaching it means `added >= 1.6', i.e. `during >= quiet + 1.6', and `quiet' is a contention reading which the guard floors at about -0.14 cores. So the second check only bites when `quiet' lands in roughly [-0.14, 0). The defect it names -- a blinded measurement -- reads `added = 0' and is already caught by the first.

A check that cannot fire is the shape this project keeps shipping by accident, so it wants either a reachable form or deleting with the reason recorded. Grouped here rather than fixed during task-035 because changing what check 1 asserts risks the blinded-mutation contract that poc/02-lexer/run.sh and poc/03-matcher/run.sh both depend on: they stub busy_cpu_seconds() to 0.0 and REQUIRE the string 'SELF-TEST FAILED'. Whatever replaces it has to keep that true.

IMPLEMENTED (see the commit that follows this note).

WHAT THE MEASUREMENTS SAID, before touching anything. 12 runs of poc/lib/selftest.py on this machine at load average 1.5-2.8:

  * check 1's two bracket readings disagreed by 0.01, 0.02, 0.04, 0.04, 0.06, 0.07, 0.08, 0.09, 0.15, 0.16, 0.18 and 0.80 cores. The wild failure recorded in this task's description was 2.40 apart. There is a wide gap between those, and the margin sits in it.
  * 1 run in 12 FAILED -- and not at check 1. It was check 2: 'a child of ours burning 4 cores moved the reading by 1.74' against a slack of 1.5. Check 2 differences two readings taken seconds apart in exactly the way check 1 does, so it has the same defect, and on this machine it is the one that actually fires. A further 22 bracketed runs of check 2 at load average 1.9-5.5 put its own baseline spread at 0.01 to 0.93 with a median of 0.16, so 1.74 was a transient and not the machine.

That is why the fix covers BOTH checks and not only the one criterion #1 names. Criterion #1 speaks of 'two bracket readings', which check 1 had and check 2 did not; check 2 has been given them. Flagging it rather than quietly widening the criterion: if you meant 039 to be check 1 only, the check 2 half is separable and can be moved to a task of its own.

THE FIX, in poc/lib/selftest.py. Two mechanisms, because the data shows two shapes.

  * BRACKETING. Each probe is taken between two baseline readings. If they disagree by enough that the background alone could have carried the answer past the threshold, the outcome is NO VERDICT (exit 3), not SELF-TEST FAILED. The margins are DERIVED from the thresholds they protect rather than chosen: check 1 expects LOAD and its nearer band edge is LOAD - LOAD*LOW = 2.4 cores away; check 2 expects 0 and its threshold is OWN_CPU_SLACK = 1.5. Both are cited in the source together with the measured spreads above -- 2.4 is 3x the worst check 1 ever showed here and 1.5 is 1.6x the worst check 2 showed.
  * RETAKING. A spike that lives entirely BETWEEN the two baselines leaves them agreeing, and bracketing cannot see it -- which is exactly the 1.74 event. An anomalous reading is therefore taken again, up to ATTEMPTS = 3 times, and only a reading that is anomalous every time is reported. If any of those attempts also drifted, the answer is NO VERDICT; if none did, it is SELF-TEST FAILED.

WHY RETAKING IS NOT 'RETRY UNTIL GREEN'. Every defect these checks exist to catch is deterministic -- a stub, a sign error, a wrong /proc/stat field, a units error, a dropped subtraction -- and fails all three attempts with baselines that agree perfectly. The proof is not an argument, it runs on every gate: poc/02-lexer and poc/03-matcher stub busy_cpu_seconds() out and REQUIRE 'SELF-TEST FAILED'.

DEAD CHECK REMOVED. 'if during < LOAD * LOW' is gone, with the reason recorded at the site. It could not fire: reaching it needs added >= 1.6 and during < 1.6, so quiet < 0, and quiet is floored at about -0.28 by _round()'s skew guard. The defect it named is caught by the band above it.

NEW PERMANENT GUARD CASE, poc/02-lexer/run.sh: 'a baseline that moves under the probe is NO VERDICT, not a failure'. It copies poc/lib, steps the fourth window's reading up by six cores -- with ATTEMPTS cut to 1 in the copy, those four windows are the free-cores check, the baseline before the probe, the probe, and the baseline after it, so the step lands between the two baselines and nowhere else -- and requires exit 3, the string NO VERDICT, and the ABSENCE of SELF-TEST FAILED. A step and not a ramp on purpose: bracketing takes the midpoint of the two baselines, which corrects a linear ramp exactly and by construction, and it was a step that the wild failure was. Costs about 13 s.

Its controls are the two blocks immediately above it, both pre-existing: a blinded reading must still say SELF-TEST FAILED, and an honest run must still pass. Without them this case would be satisfied by a self-test that refused everything.

CALLERS. poc/02-lexer, poc/03-matcher and poc/04-assembler capture the self-test's status instead of letting set -e propagate it. Exit 3 is carried to the last line, where it downgrades the LADDER's verdict and nothing else -- everything in between is deterministic and has already exited if it was red, so this can refuse a reading but cannot hide one. A ladder HARNESS FAULT (2) is left alone, being a defect rather than a reading.

FILED, NOT FIXED: task-042. The same function refuses to run at all when fewer than LOAD + 2 cores are free, and does it with contention.fault() -- exit 2, HARNESS FAULT, red. Its own message says 'not a verdict on anything'. On this 14-core machine ten cores of someone else's work is enough to trigger it, so it is a live second source of red gates. Referenced in the source at the site.

REVISED after qa-test-runner and mped-architect. Both found real defects in the first draft; four of them were mine and blocking.

1. THE NEW GUARD CASE WAS FLAKY, in the direction that reddens the gate -- the exact failure this task exists to remove. The step of 6 cores landed on the trailing baseline, and bracketing takes the MIDPOINT of the two baselines, so only half of it reached `added': 4 - 3 = 1.0 against a band edge of 1.6. A margin of 0.6 cores. Both reviewers measured it failing 2 runs in 11. It steps by 20 now, which puts the reading about 6 cores outside the band; 12 consecutive runs gave exit 3 with `added' between -6.20 and -5.48, so flipping it would take 7 cores of transient on a 14-core machine.

2. THE DERIVATION WAS WRONG BY A FACTOR OF TWO, in the loosening direction, and the number it produced did not describe the event it cited. With before at b and after at b + d, quiet is b + d/2, so the most a spread of d can shift the answer by is d/2 -- the limit that argument supports is 4.8, not 2.4. And the wild event needed 4.3 of movement while its spread was 2.40, so the spread did not account for it at all. The whole derivation is gone. There is now ONE constant, BASELINE_MOVED = 2.0, and it is measured rather than derived: the spread is EVIDENCE that the background is not holding still, not a bound on the error, because three samples of a moving quantity bound it from below and not from above. 2.0 sits in the gap between the worst a merely busy machine produced over 34 observations (0.93) and what the churning one produced (2.40). The rejected derivation is recorded at the site, with why, because it is the first thing anyone will reach for.

3. THE REFUSAL BOUGHT AN ESCAPE. `drifted' was an OR across attempts, so ONE drifting attempt sent the whole loop to NO VERDICT even when the others were anomalous with baselines agreeing to 0.00. qa-test-runner demonstrated a stubbed measurement escaping into exit 3 that way. The predicate is the complement now: if ANY attempt was anomalous while its own baseline held still, that is a defect and the answer is SELF-TEST FAILED. Verified on the reviewer's own scenario -- blinded plus one 6-core drift -- which now reports SELF-TEST FAILED naming the 2 steady attempts.

4. THE CLAIM THAT THE RETAKES ARE PROVEN ON EVERY GATE WAS FALSE. Inside the sandbox the blinded copy dies at check -1 on the /proc cross-check, in 0.035 s, and never reaches check 1. So the retake path had no standing coverage at all. There is a second case now, in poc/02-lexer only: the same stub with NIXCC_SANDBOX taken out of the environment so check -1 stands aside, MIN_WINDOW cut to 0.5 s (sound only because a stubbed reading is a constant and cannot care how long it was taken over), requiring exit 1, the string SELF-TEST FAILED, evidence that both retakes were used, and evidence that all three attempts were steady. About 6 s.

5. THE DOWNGRADE HID A REAL RED. Turning a ladder FAIL into a refusal made `just poc' print 'Every other check in them passed' about a run where one had not. It only downgrades a ladder PASS now, and the comment says which and why.

6. THE POLICY WAS COPY-PASTED INTO THREE HARNESSES and had already drifted at birth -- 04-assembler printed nothing at the call site where the other two explained themselves. It is poc/lib/selftest.sh now, two functions, one copy of the reasoning.

7. THE GUARD CASE COULD HAVE STOPPED TESTING SILENTLY. Adding or removing an idle_window() call above check 1 moves the step onto the probe window, at which point the reading leaves the band through the CEILING instead and every assertion still passes. The printed spread is now read back out of the log and required to be most of the step.

8. A UNITS ERROR in the dead-check record: _round()'s skew allowance is 0.28 core-SECONDS, so the floor is about -0.14 cores over a MIN_WINDOW window, not -0.28. Fixed, with the arithmetic shown.

Also from the reviews, not changed and recorded instead: check 2 still raises a HARNESS FAULT when its child under-burns, with no retake, even though an under-burning child on a loaded machine is as transient as the spike the retakes exist for. Appended to task-042, which owns the exit-2-on-a-busy-machine family.

CRITERIA, one by one, with the qualification each needs.

#1 MET, and wider than written. The refusal fires when the reading is outside the accept band AND every attempt that produced it came with a baseline that had moved. A reading that lands INSIDE the band with a drifting baseline passes rather than refusing -- the criterion says 'not SELF-TEST FAILED', which holds, but it is not a blanket refusal on drift and should not be read as one. Requiring both is what keeps a refusal from being reachable on an ordinary run.

#2 MET, and the source cites 34 measurements taken here rather than an argument. Stated plainly because it is the criterion most easily fudged: the limit is bounded BELOW by the worst spread a merely busy machine produced (0.93) and ABOVE by the spread the churning one produced (2.40). The upper bound does come from a run that was red -- and that run was red WRONGLY, which is what this task is about. If you read criterion #2 as forbidding that too, then the honest position is that only the lower bound is measured and the upper one is the event being fixed, and the gap between them is 2.6x.

#3 MET twice over, and the first draft's version of this was not enough. Inside the sandbox the stub is caught by check -1 in 35 ms and never reaches the code this task changed, so a second case runs it with NIXCC_SANDBOX out of the environment: exit 1, SELF-TEST FAILED, both retakes used, all three attempts steady.

#4 MET. Exit 3 from the self-test is carried to the harness's last line and turns a ladder PASS into exit 3. It does NOT turn a ladder FAIL into exit 3, which the first draft did and which made `just poc' print 'Every other check in them passed' about a run where one had not.

EVIDENCE. Two consecutive green gate runs, both `nix develop --command just e2e', exit 0: 7m41 at load average 1.96/2.08/3.14 rising to 2.92/3.22/3.37, and the second at 1.98/2.42/2.66 to 2.64/2.61/2.66. Separately, the new drift guard case run 12 times consecutively: exit 3 every time, with the probe reading between -6.20 and -5.48 against a band floor of 1.6, so the margin is over 7 cores on a 14-core machine. The version review caught had a margin of 0.6 and failed 2 runs in 11.
<!-- SECTION:NOTES:END -->
