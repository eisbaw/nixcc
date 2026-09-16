---
id: TASK-053
title: Three rule-table rows that no corpus node selects
status: Done
assignee: []
created_date: '2026-09-15 23:52'
updated_date: '2026-09-16 03:46'
labels:
  - backend
  - rules
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix has three rules that label nothing in any ir/*.sym, so nothing but their own row asserts what they emit:

  reg_cnst_wide        a signed constant too wide for the 12-bit immediate field
  stmt_callv_indirect  a void call through a function pointer
  stmt_argp            a pointer argument

All three predate task-051 and all three are reachable C. Found while closing task-051, by walking every label table in the corpus and subtracting the rules that fired from the rules that exist -- which is a check the suite does not make and probably should:

  rules that label nothing in the corpus:
    reg_cnst_wide
    stmt_callv_indirect
    stmt_argp

What makes this worth a task rather than a note is what it costs to be wrong. cases.nix's 'lowerings' and 'libcalls' tables assert the TEMPLATE of a named rule and never that the matcher selects it, so a row nothing selects is pinned by a table describing itself. task-051 found five U-typed rows in exactly that state -- reg_rshu_reg among them, where 'srl' for 'sra' is the defect the whole slice was written to prevent -- and closed them by extending ir/unsig.c. These three are the remainder.

stmt_callv_indirect is the interesting one: poc/03-matcher/run.sh aims a mutation at it PRECISELY BECAUSE nothing else covers it ("a call rule's emitted text stops looking like a call"), and that mutation would stop proving what it proves if the rule were also selected somewhere. Read that one before changing it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every rule in poc/03-matcher/rules.nix is either selected by some node in the ir/ corpus, or named in a list of rows deliberately left unexercised with the reason written down
- [x] #2 The suite computes that set rather than a reader computing it: a rule added to the table and selected by nothing is a named failure, not a silence
- [x] #3 The mutation aimed at stmt_callv_indirect still demonstrates what it says it demonstrates, or is re-aimed and says why
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ORCHESTRATOR: raised to high. Task-051's implementer is right that this is not a tidy-up -- it is the check that would have caught its own five unselected U-typed rows, including reg_rshu_reg where sra-for-srl is the exact defect that task existed to prevent. Two reviewers found it; the implementer had not.

The window matters: slice 2 (task-028) is adding rules as I write this, and it has been briefed on the lesson but cannot lean on a check that does not exist. Every rule added before this lands is a rule asserted only by a table that names it rather than by a corpus that selects it.

Schedule it immediately after slice 2, before slice 3 adds more.

DO NOT TIDY THIS, carried from task-028. poc/03-matcher/ir/lbuf.c has NO entry in cases.nix's 'emitted' table, and that absence is deliberate: the frame-displacement mutation is caught ONLY by the program returning 105 instead of 293. If a future cycle pins those lines in the emitted table as a consistency tidy-up, the claim silently stops being tested and nothing will go red.

This is the same species as the defect this task exists to fix -- a check that looks thorough and asserts nothing -- but inverted: here the absence IS the test. Anyone extending the emitted table should confirm each addition still leaves something that only execution can catch.

PLAN (implementer).

The check: a RULE CENSUS in poc/03-matcher/check.nix, computed from the corpus
rather than read by a person.

Two populations, because they are not the same claim:

  LABELLED  the rule won some nonterminal at some corpus node. Measured off the
            label tables, which is what the task describes. 104 of 107 rules.
  REDUCED   its template was actually expanded into emitted assembly. Measured
            by compiling the corpus a second time against a table whose every
            template carries its own rule id as a marker, and reading which
            markers came out. 99 of 107 rules.

Shipping the REDUCED one as the verdict, because that is the population whose
templates anything asserts: addr_addi labels an ADDI4 node (right opcode, right
kid shapes) and is never expanded, so its text is pinned by nothing, and the
labelling census would have called it covered.

One blind spot, and it is declared rather than hidden: a rule whose template is
a FRAGMENT reduced at a root in statement position has its text discarded, so
the marker cannot reach the emitted code. That is exactly one rule today
(stmt_from_reg, tmpl = ""), it gets its own census status, and its real state
was settled separately -- dropping it from the table leaves the whole corpus
compiling, so it is genuinely not reduced.

Declarations live in cases.nix as { rule; status; why; }. The table cannot be
padded to silence the census: a declared row whose actual status is BETTER than
declared is a failure, and a declared row naming no rule is a harness fault, so
the list is exactly determined by the corpus.

Ordering inside check.nix: after every existing verdict. Several existing
mutations incidentally leave a rule unreduced (pricing addr_addp out, adding
stmt_callp_direct), and the census must not pre-empt the diagnosis those
mutations exist to produce.

DONE. What landed, and the numbers it measures.

THE CHECK. poc/03-matcher/check.nix now carries a RULE CENSUS: for every row in
rules.nix it works out the strongest thing the corpus does with that row, and a
row nothing reduces is a named failure unless cases.nix's `unexercisedRules'
declares it with a reason.

  107 rules in the table
  104 LABELLED  -- won some nonterminal at some corpus node
   99 REDUCED   -- its template was actually expanded into emitted assembly

Both numbers are measured, not asserted. The verdict is the second one, and the
gap between them is why: addr_addi labels every ADDI4 in the corpus (right
opcode, right kid shapes) and is never expanded into a byte of assembly, so a
labelling-only census would have reported it covered. The three rows this task
is named for are unreached; the census found five more that are labelled and
never reduced.

HOW REDUCEDNESS IS MEASURED, since it is the part that could be fake. The
corpus is compiled a SECOND time against a table whose every template carries
its own rule id in front of it, and a marker reaching the emitted body means
that template was expanded there -- through a parent's %0 for a fragment, on
its own line for an instruction. One extra compile for the whole table rather
than one per rule; check.nix's wall time went from 0.14 s to 0.19 s.

THE ONE BLIND SPOT, declared rather than discovered later. A FRAGMENT reduced
at a root in statement position has its result text discarded by burg.nix
instead of emitted, so no marker of its can come out. Exactly one rule is in
that position (stmt_from_reg, whose template is empty); it gets its own census
status, "textless", so the census never claims to have measured it. Its real
state was settled by a different means -- with the row dropped from the table
the whole corpus still compiles, so nothing needs it -- and that is written
into its declaration.

THE TABLE CANNOT BE PADDED TO QUIET THE CENSUS, which is what stops it becoming
a silencer and why it needs no floor: a declared row whose rule is in a BETTER
state than declared fails, a declared row naming no rule is a harness fault, an
unknown status word is a harness fault, and a reason under 40 characters is a
harness fault. Emptying the table makes the census stricter, not weaker. All
five refusal paths were run and produce the message they claim.

THREE NEW MUTATIONS, 53 -> 56, each detected with its own distinct failure:

  matcher: a rule is added to the table that no corpus case can reach
           -- a `reg: CVUU4' row, which is the mistake the file invites:
           rules.nix's conversion block says in so many words that CVUU4 is a
           missing cell. Nothing in ir/ produces one, so every other check in
           the suite passes it clean.
  harness: the unexercised-rule declarations are emptied
  harness: a rule the corpus reduces is declared unexercised, to quiet the
           census

CRITERION #3. The mutation aimed at stmt_callv_indirect is UNCHANGED and still
demonstrates what it says: no corpus case calls a void function through a
pointer, so the derived callMarkers check is still the only thing that catches
its template ceasing to look like a call. What changed is that the coupling is
now written where it can be acted on -- cases.nix declares that row unreached
and says this mutation is why it must stay so -- instead of only in a comment
beside the mutation.

CRITERION #1, said carefully. Eight rows are declared with reasons. THREE ARE
GENUINELY DELIBERATE: stmt_callv_indirect (above), reg_calli_indirect (the duel
reduces it under a perturbed cost table and checks its text, which is weaker
than selection and is why it is declared rather than counted), and
stmt_from_reg (droppable with no effect on the corpus). The other five are
KNOWN rather than deliberate, and are filed: task-055 for reg_cnst_wide,
task-056 for the labelled-never-reduced five. Ticking #1 on that basis; if
"deliberately" was meant to exclude a written-down accident, the criterion is
not met and the fix is task-055 and task-056, not a re-wording here.

GATE: nix develop --command just e2e, green. 7 PoCs, matcher mutation count
53 -> 56.

CORRECTION, after review. Three claims in the note above were wrong and the
code has been changed rather than the wording.

1. "THE TABLE CANNOT BE PADDED TO QUIET THE CENSUS" WAS FALSE. `reduced' was
   an accepted status word, so a row declaring an already-reduced rule as
   `reduced' agreed with its real state, the staleness check stayed silent,
   and the undeclared check never looks at reduced rules. Demonstrated: one
   row for `reg_indiri' passed the whole matcher check and printed "99 of 107
   rules reduced and the other 9 declared" -- a summary whose own arithmetic
   does not add up. Fixed three ways: `reduced' is no longer a status a
   declaration may use; the census asserts reduced + declared == the table's
   length, which also catches a rule declared twice (listToAttrs keeps the
   FIRST row and ignores the rest in silence); and both have mutations.

2. EMPTYING THE TABLE IS NOT THE THREAT, which is what made "it needs no
   floor" sound sufficient. Nobody erodes a corpus by shrinking the excuse
   list; they shrink the CORPUS. Delete the `lbuf' function from cases.nix and
   declare the rule it reached, and every floor in check.nix survives it --
   lbuf carries no `emitted' assertions by design, so neither the assertion
   floor nor the instruction count moves, and minFunctions and minNodes both
   land exactly on their values. The census was then the only check that
   noticed, and it told the author how to legalise it. `minReduced' is the
   floor for that, with the mutation that demonstrates it.

3. THE "textless" STATUS WAS UNFALSIFIABLE AND ITS DECLARATION WAS WRONG. It
   was decided from the rule's SHAPE before the corpus was consulted, so no
   evidence could ever contradict it, and it duplicated a predicate private to
   burg.nix. Replaced: when the marker is silent the row is taken OUT of the
   table and the corpus compiled again, and identical assembly means nothing
   needed it. `stmt_from_reg' is therefore `labelled', not "reduced but
   invisible" as its reason claimed -- all fourteen corpus functions emit
   BYTE-IDENTICAL assembly without it.

Also fixed, all factual errors in the prose rather than in the code:

  * the `unreached' glossary said "no node in the corpus labels it at all".
    The census computes "never the cheapest rule for any (node, nonterminal)",
    and only `stmt_argp' is genuinely never a candidate: the corpus holds 31
    CNSTI4 nodes that `reg_cnst_wide' matches and loses at, and one CALLV that
    `stmt_callv_indirect' matches and loses at.
  * check.nix said `addr_addi' clears the labelling bar "at every ADDI4 in the
    corpus". It wins `addr' at 7 of 29. The argument stands; the number did
    not, and it was the sentence carrying the whole REDUCED-beats-LABELLED
    case.
  * `stmt_argp's reason cited ir/argmul.c as a corpus case that passes ints.
    argmul is a must-fail CONTROL -- a program the matcher is required to
    refuse (task-017) -- so it censuses nothing and compiles never.
  * the mutation expectation "8 rule(s) affected" was a count that moves the
    moment a rule is legitimately added and declared. It names a rule now.

One hazard the review found that was latent rather than live: the census
marker is glued to the front of a template, and burg.nix reads call-ness off
the emitted TEXT with an unanchored match, so a rule id ending in `call' in
front of a template beginning with a space would make the marked table call
something the real one does not. No rule is spelled that way; check.nix now
asserts it rather than leaving it to how the ids happen to look.

Cost after the change: check.nix evaluates in 0.53 s against 0.14 s before,
the difference being one ablation per declared row. They run only on a pass,
because Nix's laziness puts the census behind the whole verdict chain.

Matcher mutation count 53 -> 58.

ORCHESTRATOR: verified and accepted, with one finding worth more than the task itself.

Census verified directly: 113 rule rows, 7 declared unexercised, so 106 reduced, and check.nix asserts the identity. Good.

THE THING THAT MATTERS MORE. reg_cvup4_4 was selected, reduced, AND named in the lowerings table -- so this task's own census would have passed it -- and it was still tested by nothing. A one-kid node reduces at the same depth as its kid, so 'mv %c,%0' was a self-move; setting it to 'mv %c,%c' left the assembly byte-identical and the program printing the same string in the same step count.

That is task-051's defect recurring ONE TASK AFTER the check written to prevent it, in a form the check structurally cannot see. Verified myself: with the fix, ir/ptr.c returns 103398 pristine and 101392 with the self-move restored, so the mutation now bites.

The lesson to carry, and it is sharper than the one this task was filed for: SELECTED is not TESTED, and REDUCED is not TESTED either. A rule is tested when corrupting it changes an executed answer. The census proves a rule is reached; only a mutation proves it matters. Three variants of this disease have now shipped -- a rule named but never selected, a rule selected but never reduced, and a rule reduced but whose corruption is unobservable -- and the third was found by a reviewer, not by the check.

Accepting the removal of minReduced. The reasoning holds: with the floors at their actual values, and the census asserting reduced + declared = total, lowering the reduced count requires ADDING a declaration, which is a visible act someone has to write a reason for. A floor adds nothing on top of that. Noting that the implementer's first stated reason for the removal was wrong and it corrected itself before reporting.

Criterion #1 said 'deliberately left unexercised' and five of the seven are KNOWN rather than deliberate. The criterion's intent was that no rule goes unexercised without someone knowing and saying why, which is satisfied. 'Deliberately' was too strong -- my wording, and the fourth time it has been the loose part rather than the work. Tasks 055 and 056 are the fix, not a re-wording.
<!-- SECTION:NOTES:END -->
