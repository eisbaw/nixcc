---
id: TASK-025
title: A call whose result is discarded has no rule
status: In Progress
assignee: []
created_date: '2026-09-15 02:03'
updated_date: '2026-09-15 08:45'
labels:
  - poc
  - matcher
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`wr(1, out, 11);' as a statement -- an int-returning function called for its effect -- does not compile. lcc emits a listed CALLI4 that nothing uses as a kid, so burg.nix reduces it to `stmt' through the chain rule `stmt: reg', which passes dst = null down to a rule whose template says `call %0\nmv %c,a0\n'. The result is:

    error: burg: template `call %0
    mv %c,a0
    ' uses %c outside an instruction

A refusal, not a miscompile, and the diagnostic points at the template rather than at the C -- a reader would have to know burg.nix to see that the problem is a discarded return value.

The fix is one or two rows in poc/03-matcher/rules.nix:

    { nt = "stmt"; op = "CALLI4"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\n"; }
    { nt = "stmt"; op = "CALLI4"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\n"; }

which is exactly the claim the rule table makes about itself -- adding an instruction means adding a row -- so it is also a small test of that claim. CALLP4 and CALLD4 want the same treatment if they can reach a statement position.

Found by TASK-004: poc/05-loop/hello.c checks write()'s return value instead, which is better C but was not a free choice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A C statement that calls an int-returning function and discards the result compiles, assembles and runs
- [x] #2 The call still clobbers the caller-saved registers: the new rule's template is matched by rules.nix's callMarkers
- [x] #3 A case in poc/03-matcher's corpus covers it, taken from real lcc output rather than hand-written IR
- [x] #4 If a discarded result still cannot be compiled in some position, the diagnostic names the C-level cause rather than the template
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan (implementer):
- Two rows in poc/03-matcher/rules.nix: `stmt: CALLI4(acon)' and `stmt: CALLI4(reg)', which is exactly what the task predicted, and therefore also a small test of the table's own claim that adding an instruction means adding a row.
- Criterion 2 wants the new templates matched by callMarkers. That is currently derived and asserted nowhere, so cases.nix gains a `callRules' table naming every rule that CALLS something, checked against the table's OWN callMarkers -- a new call rule the markers do not match would keep a value in a0 across a call, silently.
- Criterion 4 wants a diagnostic naming the C-level cause. burg.nix's `%c outside an instruction' message names the template and not the node; it gains the opcode and the position, keeping the existing fragment so must-fail still holds.
- New corpus case ir/voidcall.c: an int-returning function called twice for its effect beside a void call, taken from real lcc output, run in the emulator against the host compiler.
- CALLP4 and CALLD4 are NOT added: nothing in the corpus produces them and there is no `reg' rule for either either, so they refuse loudly. Filed rather than guessed at.

IMPLEMENTED in 7875e71. Gate: `nix develop --command just e2e' exit 0 -- 5 PoCs passed, lint clean, all four ladders PASS. 34 mutations in the matcher PoC, each with its own distinct failure.

ALL FOUR CRITERIA MET.
1. ir/voidcall.c: put(n) and put(n+1) discarded, plus hook(n+2) through a function pointer and a void done(). Compiles, assembles, runs in the Nix emulator, exits 70, gcc agrees.
2. The new templates ARE matched by callMarkers -- and the check that says so is derived, not listed, see below.
3. The case is real lcc output: run.sh regenerates ir/voidcall.sym from ir/voidcall.c with rcc-rv32 and diffs it on every run.
4. The refusal now names the C-level cause. must-fail.nix removes BOTH stmt rows -- removing only the direct one lets the indirect row take the node, which is correct code and not this case -- and messages.sh pins the text.

WHAT THE REVIEWS CHANGED, and the first item is the one that matters.

THE FIRST VERSION OF THE CRITERION-2 CHECK DID NOT WORK. It listed the call rules by hand in cases.nix and claimed 'a rule added to the table and forgotten here is caught by the floor'. It was not: a floor of 9 against a list of 9 catches SHORTENING and never failing to grow. Both reviewers independently added a `stmt: CALLP4' rule emitting `jal', left the list alone, and got a clean pass -- which is exactly the omission task-036 was about to walk into. The population is now DERIVED from the CALL opcode prefix, the marker test stays reimplemented (a check sharing burg.nix's implementation would agree with it however wrong it was), the hand-written list and its floor are gone, and the mutation that was previously impossible is in the suite. task-036's third criterion was removed because the obligation it recorded no longer exists.

COSTS. The first draft priced the statement rows at `callCost - 1', which mixes units: callCost is documented as pipeline, not instructions. Re-based so callCost is the call and each further instruction is one more. It also turned out the margin over `stmt: reg' was doing real work -- at equal cost the choice is a tie broken by the order the labeller seeds its map in, and dearer it refuses outright. Measured both ways and written down.

THE CORPUS CASE COULD NOT SEE THE BUG IT EXISTED FOR. acc started at 0, so put(n) returned exactly n and a compiler that used the discarded result where the argument belongs computed the right answer by luck. Both reviewers found this. acc starts at 7 now. A `why' claiming a wrong counterfactual (61, which only arises from a third call) is corrected.

stmt_calli_indirect was originally held up by nothing but a string comparison -- no C in the corpus reached it. ir/voidcall.c calls through a function pointer now, which is the only way C produces CALLI4 with a register kid.

The mutation aimed at the callMarkers guard originally targeted a rule the corpus exercises, so the emitted-assembly check caught it too and it proved nothing about the guard. It targets stmt_callv_indirect now -- a void call through a pointer, which no case reaches -- and with the guard disabled that mutation passes clean.

GOTCHAS.
- `present' is membership, so it cannot see that put() is called TWICE. The instruction count is what distinguishes one call from two, and what catches a rule that grew a result move (which emits `mv s1,a0' with no %c to refuse over).
- The diagnostic describes rather than prescribes. A table WITH a stmt rule whose own template asks for %c reaches the same throw, and telling that reader to add a rule that is already there sends them nowhere.
- poc/05-loop/hello.c's sentence claiming a discarded result is still refused was corrected here rather than left for the demo rewrite. Its `if (wr(...) == 11)' stays -- checking write's return value is better C -- but it is a free choice now.

FILED: task-036, CALLP4 and CALLD4 have no rule in either position. CALLP4 is ordinary C and is reachable the moment a frontend slice declares anything returning a pointer.
<!-- SECTION:NOTES:END -->
