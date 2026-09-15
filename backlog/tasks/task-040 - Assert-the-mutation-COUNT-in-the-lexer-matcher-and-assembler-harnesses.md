---
id: TASK-040
title: 'Assert the mutation COUNT in the lexer, matcher and assembler harnesses'
status: Done
assignee: []
created_date: '2026-09-15 14:07'
updated_date: '2026-09-15 17:10'
labels:
  - poc
  - testing
  - harness
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/05-loop/run.sh ends its mutation stage with a floor on how many mutations ran. poc/02-lexer, poc/03-matcher and poc/04-assembler print ${#names[@]} without asserting it, so a mutate call that was dropped, commented out, or lost to a bad merge would take the count down and nothing would notice -- the suite would report a smaller number just as confidently.

Found by qa-test-runner while reviewing task-034. Pre-existing rather than introduced there.

This is the same shape as two defects fixed during task-034: an absence check with no binaries to look for, and a grep over a file list that had gone stale. Both print their cleanest line when they have stopped testing. A count that is reported rather than asserted is that shape with the alarm removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 poc/02-lexer, poc/03-matcher and poc/04-assembler each refuse to pass if fewer mutations ran than the floor, the way poc/05-loop already does
- [x] #2 Each floor is the number that runs today, so lowering it is a deliberate edit rather than a silent drift
- [x] #3 A deliberately removed mutate call makes the harness fail, and that is demonstrated rather than asserted
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Count what actually runs in poc/02-lexer, poc/03-matcher and poc/04-assembler by running them, not by grepping for mutate calls.
2. Add the floor poc/05-loop already has to each, set at that number, with the same reasoning recorded once and referenced rather than copied three times.
3. Demonstrate it: remove a mutate call in a scratch copy of each harness and show the floor fires. Criterion 3 asks for demonstrated, not asserted.
4. Sequenced after task-041, which adds one mutation to the matcher: the floor has to be the number that runs when it is written, not one that was already stale.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IMPLEMENTED.

The floor poc/05-loop already had, given to the other three, set at what runs today: poc/02-lexer 10, poc/03-matcher 36 (35 after task-041 folded the semantic mutation into the mutate() stage, plus the one task-041 added against the oracle itself), poc/04-assembler 28.

The reasoning is written ONCE, in poc/lib/mutant.sh -- the file all four harnesses' mutations go through -- and each site carries a one-line pointer to it. Four copies of a paragraph is how the selftest exit policy had already drifted this batch, and this is the same shape.

FOUND WHILE DOING IT, and fixed here rather than filed: poc/05-loop's own floor was 34 while 36 mutations ran. Two could have been dropped in silence, in the one harness that had a floor at all -- exactly the slack the floor exists to remove. It is 36 now. Flagging it because this task names three harnesses and I changed four: if you would rather that were its own task, it separates cleanly.

CRITERION 3, DEMONSTRATED AND NOT ASSERTED. A copy of poc/ outside the tree, with the LAST mutate call removed from each harness in turn, run for real:

  poc/02-lexer      exit 1, "only 9 mutations ran, against the 10 this harness has"
  poc/03-matcher    exit 1, "only 35 mutations ran, against the 36 this harness has"
  poc/04-assembler  exit 1, "only 27 mutations ran, against the 28 this harness has"
  poc/05-loop       exit 1, "only 35 mutations ran, against the 36 this harness has"

The fourth is what shows the raised floor is at the right number rather than merely higher.

A LIMIT WORTH SAYING. This asserts how many mutations RAN, not that the right ones ran. A mutate call swapped for a different one, or one that quietly tests the same thing as its neighbour, keeps the count and passes. What guards against that is the distinctness loop above the floor, which requires each mutation's fragment to appear in its own output and in no other's -- so a duplicate would have to invent a new failure message to survive. That is real but it is not the same claim, and the floor should not be read as making it.

REVISED after qa-test-runner and mped-architect. They converged independently on the same finding, and it changes the shape of the fix.

A FLOOR AT THE EXACT COUNT IS NOT A FLOOR, AND IT ROTS IN THE DIRECTION THAT ACTUALLY HAPPENS HERE. mped-architect traced poc/05-loop's -ge 34: nobody ever lowered it. It was correct when written, and two commits in the immediately preceding batch added mutations and left it behind. That is how the slack got there -- and the slack is then available to be spent downward in silence, which is the defect this task names. A floor only catches the direction that has never occurred in this repo, and shipping three more of them would have restarted the same clock in three more places.

So each harness DECLARES its count and the assertion is equality, not a floor:

  declared=36
  [ "${#names[@]}" -eq "$declared" ] || ...

Safe today because all 110 mutate calls in the tree are unconditional and at column 0 -- both reviewers checked that independently. If a runtime-gated mutation is ever added, equality fails loudly and someone has to think, which is the right outcome. The edit equality forces when a mutation is added is the edit that was wanted anyway.

This is a change to what criterion 2 asks for, so it is flagged rather than folded in: the criterion says "so lowering it is a deliberate edit rather than a silent drift", and what shipped makes RAISING it deliberate too. I read that as satisfying the criterion more strictly rather than differently. If you meant a genuine floor with slack -- the shape poc/05-loop/closed-loop.sh uses for its closure and absence counts, where the number is deliberately far below the real one -- say so and it is a one-word change.

ALSO FROM THE REVIEWS.

  * The number was written twice per site, once in the test and once in the message. That is the same two-places-one-number defect one level down. It is a `declared' variable used in both now.
  * The message said "against the 36 this harness has", which is false whenever it prints -- the harness demonstrably does not have 36 at that moment. It says "declares".
  * The message guessed one cause. It names both, because equality now catches both.
  * The comment in poc/lib/mutant.sh claimed "every harness that uses this has one", which nothing enforces. task-027 and task-028 both instruct their implementer to copy mutate() from an existing harness and neither mentions the count, so the next harness written to those instructions will not have one. The sentence is now a statement of fact with its own limit attached: four today, nothing checks a fifth. Enforcing it properly means extracting mutate() itself, which is task-044.
  * The comment led with the one-missing case and called it "the cleanest line once it had stopped testing". mped-architect is right that this overreaches: one missing mutation changes the printed number, so it is visibly different, and what is wrong is only that no machine notices. The case where the analogy is exact is the EMPTY one -- an empty table makes the distinctness loop iterate zero times and the stage print "0 mutations, each detected with its own distinct failure". The comment leads with that now.
  * poc/lib/mutant.sh is the wrong home for a statement about a caller's table, and says so in its own first line rather than pretending otherwise. It is the only file all four stages share; the reason there is nowhere better is task-044.

CRITERION 3, DEMONSTRATED AGAIN against the equality version, in both directions. A copy of poc/ outside the tree:

  the LAST mutate call removed from each harness in turn, run for real --
    poc/02-lexer      exit 1, "9 mutations recorded, against the 10 this harness declares"
    poc/03-matcher    exit 1, "35 ... against the 36"
    poc/04-assembler  exit 1, "27 ... against the 28"
    poc/05-loop       exit 1, "35 ... against the 36"

  and the direction the old floor could not catch, modelled by leaving the
  table alone and setting the declaration one low --
    poc/02-lexer      exit 1, "10 mutations recorded, against the 9 this harness declares"

FILED, NOT FIXED: task-044 (mutate() copied four times, so there is nowhere to share a statement about a table and nothing can enforce that a fifth harness declares a count) and task-045 (two more counts that are printed rather than asserted -- `just poc' prints "$ran PoC(s) passed" after checking only that $ran is above zero, and the guard stages in poc/02-lexer and poc/03-matcher count nothing at all).

WHAT THIS STILL DOES NOT BUY, restated after review sharpened it. It counts; it does not check that the RIGHT mutations ran. The distinctness loop above it is weaker than I first wrote: it requires each mutation's fragment to appear in its own output and in no other's, so it catches an exact duplicate -- but a near-duplicate that tests the same defect through a different file produces a different message and passes both checks. Inventing a new failure message is the default, not a bar.
<!-- SECTION:NOTES:END -->
