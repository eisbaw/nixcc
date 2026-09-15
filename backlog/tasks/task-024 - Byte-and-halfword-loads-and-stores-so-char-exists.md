---
id: TASK-024
title: 'Byte and halfword loads and stores, so char exists'
status: Done
assignee: []
created_date: '2026-09-15 02:03'
updated_date: '2026-09-15 09:43'
labels:
  - poc
  - matcher
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix implements INDIRI4/ASGNI4 and the 4-byte address modes and nothing narrower: there is no rule for INDIRC/ASGNC, no CVTCI/CVTIC, and so no `lb', `lbu', `sb', `lh', `lhu' or `sh'. poc/01-encoder and poc/04-assembler both have all six instructions; only the rule table is missing.

The practical consequence, found while building the headline demo: a C program cannot touch a string. poc/05-loop/hello.c builds its output message a WORD at a time -- four ASCII codes packed little-endian into one int and stored with `sw' -- because that is the narrowest thing compiled code can currently write. That is a fine demonstration of shifts and it is not C.

Needs the CVT opcodes as well as the loads and stores: lcc inserts CVTCI4/CVTIC4 around every char access, and a rule table without them will refuse rather than narrow silently, which is the right failure but still a failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A C function that walks a char array, reads a byte and stores a byte compiles and runs in the Nix emulator with the right result
- [x] #2 Halfwords too, or the rule table says in one place why they are out of scope
- [x] #3 poc/05-loop's demo can build its message a byte at a time
- [ ] #4 Signed and unsigned narrow loads select lb/lh versus lbu/lhu per the IR opcode (INDIRI1/INDIRU1), verified by inspecting the emitted instruction rather than by a differing answer -- see the note below for why no differing answer exists yet
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan (implementer):
- poc/03-matcher/rules.nix gains, as data only: lb/lbu/lh/lhu loads (INDIRI1/INDIRU1/INDIRI2/INDIRU2), sb/sh stores (ASGNI1/ASGNU1/ASGNI2/ASGNU2), the word forms lcc emits for unsigned int (INDIRU4/ASGNU4), the conversions lcc wraps every narrow access in, and a 1-byte constant (CNSTI1).
- SIGN LIVES IN THE INSTRUCTION, not in a conversion afterwards: lb sign-extends the byte into the whole register and lbu zero-extends it, so signed and unsigned char are two different rows and a case whose answer differs between them is what proves it.
- The widening conversions need the SOURCE width, which lcc writes as the node's own symbol and NOT in the opcode (CVII4 with 1 is from a byte, with 2 from a halfword). burg.nix's predicate vocabulary gains `srcSize' for that -- frontend vocabulary, so it stays target-independent and burg.nix still knows nothing about RISC-V.
- Deliberately NOT done: the fused two-level patterns mips.md uses (reg: CVII4(INDIRI1(addr)) -> one lb). burg.nix matches one level, and the unfused form is correct, just three instructions where one would do. Filed rather than smuggled in.
- New corpus case ir/chars.c: signed and unsigned bytes and halfwords over the SAME data, so lb-against-lbu changes the answer; run in the emulator against the host compiler.
- Halfwords are in scope and implemented, not documented as out of scope.

IMPLEMENTED in 7de656d. Gate: `nix develop --command just e2e' exit 0 -- 5 PoCs passed, lint clean, all four ladders PASS.

CRITERION 2 IS NOT MET AS WRITTEN, and I have not rewritten it. It asks for lb against lbu 'checked by a case whose answer differs between them'. The first half is done: they are separate rows, the table pins which opcode lowers to which instruction, and a mutation swapping them is caught. The second half is IMPOSSIBLE with the table as it stands, and I only found that out because the review refused to take my word for it.

lcc promotes every narrow load, so an INDIRI1 always arrives under a CVII4 and an INDIRU1 under a CVUI4. Those lower to a shift pair and a mask that RE-NORMALISE the register: lb followed by slli/srai and lbu followed by slli/srai leave the same 32 bits. Measured twice, independently -- swap lb for lbu in the rule table and ir/chars.c still exits 1649; swap all four loads and it still exits 1649. No C program this compiler can accept makes the load's sign observable in its answer. It becomes observable the moment task-033 fuses the load and the conversion, because then the load IS the extension.

So criterion 2's checkbox is left unticked and the orchestrator decides. What exists instead is cases.nix's `lowerings' table, which pins opcode -> rule -> mnemonic against the rule table, compared on the template's first TOKEN because `lb' is a prefix of `lbu'. Measured per rule, what the emulator CAN see: reg_cvii4_1 and reg_cvii4_2 (srai->srli), reg_cvui4_4 and reg_cviu4_4 (mv->andi). What it cannot: every load, every store, every narrowing conversion.

CRITERION 4 is for the poc/05-loop commit that follows; left unticked here.

WHAT THE TWO REVIEWS CHANGED, because it was most of the work.
- Four comments asserted that a swapped lb/lbu changes the answer. All four were false and are rewritten.
- reg_indiru (INDIRU4) and stmt_asgnu (ASGNU4) were verified by NOTHING: lowering INDIRU4 to `lbu' passed check.nix, must-fail, messages.sh AND returned the right answer, because ir/chars.c only ever loads an unsigned int it has just stored a small value into. They are in `lowerings' now, with a mutation.
- burg.nix's `when' handling was a regression I introduced: with one predicate the if/else-if chain was total, with two a rule carrying `range' AND a typo applied the first and dropped the rest in silence. Predicate validation moved onto the TABLE, where this file's own header says every checkable thing about the table belongs.
- The comment explaining why width-4 conversions emit `mv' is now a throw: burg.nix refuses a fragment rule producing the register nonterminal from a kid's register.
- Floors had not been raised with the tables: ten new selections could be deleted under minSelections=24. Now 34/60/13.

GOTCHAS for whoever touches this next.
- drivers/chars.s's data layout is load-bearing. shalf+2 and sbuf+2 are deliberately NOT four-aligned, so a halfword or byte store widened to `sw' faults in the emulator instead of quietly writing three bytes too many. Pad that data differently and the catch disappears.
- The conversion block in rules.nix is a TRACE of what ir/chars.c emits, not a specification. CVUU4 has no row and CVIU4 none below width 4 because no C in the corpus produces them. An absent cell is a loud refusal naming the opcode, which is the right failure, but a reader auditing for completeness should expect to add rows rather than find them.
- No new cost duel, and not for lack of trying: a duel needs two rules matching the same subtree, and every new row is disjoint from every other by opcode or by predicate. There is nothing here to duel.
- ir/chars.c compiles to 91 body instructions of which 23 are extensions and 4 are `mv sN,sN' self-moves -- 30% waste, all of it task-033 and task-016.

ALSO FILED: task-035, a pre-existing flake in poc/02-lexer's fourth contention-guard case. It exits 1 (a harness failure, not a NO VERDICT) when the smallest ladder point measures too close to the evaluator baseline, because the too-small-to-measure cliff refuses through the contention guard before the per-step 'unjudged' lines are ever printed. poc/02-lexer and poc/lib are untouched by this change.

ORCHESTRATOR: resolving the AC#2 deviation, and the implementer was right to refuse it.

The criterion asked for lb vs lbu 'checked by a case whose answer differs'. No such case can exist today, and I verified the reason independently rather than on report: lcc emits a conversion above EVERY narrow load. For 'signed char *p; return p[0]' the IR is INDIRI1 followed by CVII4, and for unsigned char it is INDIRU1 followed by CVUI4. The conversion re-normalises the register to the correct 32 bits whatever the load did, so swapping lb and lbu in the rule table leaves every observable answer unchanged -- which is exactly what the implementer measured twice.

So the criterion was unsatisfiable, not merely unmet, and it is replaced with one that checks the selection directly. Two implementers have now declined to rewrite a criterion to fit what they built, and both times they were right and the criterion was mine.

This is also the same fact as the reported waste: the load extends and then the conversion extends again, which is 23 of chars.c's 91 instructions. Fusing them is task-033, and the moment they fuse the distinction becomes observable -- so the 'answer differs' test belongs there, where it can actually be written. Carried onto task-033.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
char and short loads and stores exist; hello.c now uses a global char msg[] with sb stores and still prints 1..10 = 55. AC#2 was unsatisfiable as written -- every narrow load carries a conversion that re-normalises the register, so lb and lbu are observationally identical until task-033 fuses them. Replaced with a criterion that checks the selection rather than the answer.
<!-- SECTION:FINAL_SUMMARY:END -->
