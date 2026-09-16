---
id: TASK-051
title: 'Backend rules for the bitwise, unary and unsigned integer opcodes'
status: Done
assignee: []
created_date: '2026-09-15 19:44'
updated_date: '2026-09-16 00:12'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix has no rule for BANDI4, BORI4, BXORI4, NEGI4, BCOMI4, and no U-typed arithmetic at all -- no ADDU4, SUBU4, MULU4, DIVU4, MODU4, LSHU4, RSHU4, BANDU4, BORU4, BXORU4, BCOMU4, nor the unsigned comparisons GEU4/GTU4/LEU4/LTU4/EQU4/NEU4 or RETU4/ARGU4/CALLU4.

Found while closing task-027 (slice 1). The frontend now emits every one of these correctly -- poc/07-parser diffs node-for-node against rcc-rv32 on a corpus that includes all of them -- so the gap is entirely in the rule table. The symptom is burg refusing at selection time, loudly and by name, e.g.

  burg: no rule produces `stmt' from ASGNU4(ADDRFP4,RSHU4) in forest 4; the node with no rule at all is RSHU4(INDIRU4,CNSTI4)

which is the right behaviour -- it refuses rather than miscompiling -- but it means a C program using `&', '|', '^', '~', unary '-' or any `unsigned' arithmetic can be COMPILED to correct IR by us and still not run.

That is why poc/07-parser/run/ holds three programs and not five: sumto.c, gcd.c and primes.c stay inside ADD/SUB/MUL/DIV/MOD/LSH/RSH/comparisons/calls, and the bitwise program that was written for the slice had to be dropped.

Most of these are single-instruction RV32I rules (and, or, xor, andi, ori, xori, sub from x0 for NEG, xori -1 for BCOM); the unsigned comparisons are bltu/bgeu; DIVU4/MODU4/MULU4 need __udivsi3/__umodsi3 beside the signed stubs in poc/03-matcher/runtime.s (task-007 owns the real runtime).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 poc/03-matcher/rules.nix covers the bitwise, unary and unsigned integer opcodes listed above
- [x] #2 poc/07-parser/run/ gains a program that uses &, |, ^, ~, unary - and unsigned arithmetic, and it RUNS with the right output
- [x] #3 The unsigned divide and remainder go through a runtime routine differential-tested the same way __divsi3 and __modsi3 are
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Read the rule table, burg.nix, emit.nix and the two harnesses; establish from rcc-rv32 exactly which opcodes and operand shapes the frontend emits for bitwise, unary and unsigned C.
2. Add the missing rows to poc/03-matcher/rules.nix: BANDI4/BORI4/BXORI4 (reg,reg and reg,con), NEGI4, BCOMI4, and the U-typed set -- CNSTU4, ADDU4, SUBU4, MULU4, DIVU4, MODU4, LSHU4, RSHU4 (logical shift), BANDU4/BORU4/BXORU4/BCOMU4, GEU4/GTU4/LEU4/LTU4/EQU4/NEU4, RETU4, ARGU4, CALLU4.
3. Implement __udivsi3/__umodsi3 in poc/03-matcher/runtime.s, and differential-test them the way __divsi3/__modsi3 are: an ir/ case run in the emulator and cross-checked against the host compiler.
4. Extend poc/03-matcher's ir/ corpus, cases.nix selections/lowerings/libcalls/emitted/execution and check.nix floors to cover the new rows, plus mutations aimed at the rows an executed answer cannot see (logical vs arithmetic right shift, unsigned vs signed branch).
5. Restore the dropped bitwise program and add an unsigned one under poc/07-parser/run/, with their expected output computed independently in Nix; raise programCount to 5.
6. Full gate (nix develop --command just e2e) before every commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IMPLEMENTATION

poc/03-matcher/rules.nix: 42 new rows. BANDI4/BORI4/BXORI4 in both their register and their immediate forms, NEGI4 as `sub rd,zero,rs', BCOMI4 as `xori rd,rs,-1', and the whole U-typed family -- CNSTU4 (three rows: zero, immediate, wide), ADDU4, SUBU4, MULU4, DIVU4, MODU4, LSHU4, RSHU4, BANDU4, BORU4, BXORU4, BCOMU4, the six comparisons, RETU4, ARGU4 and all four CALLU4 rows.

poc/03-matcher/runtime.s: __udivsi3 and __umodsi3 IMPLEMENTED. They were missing, as task-007 said. They are __divsi3's restoring loop with the sign handling removed and nothing else added; the `bltu' that was already there is the one instruction that now has to be right over a wider range of operands. A first version caught the bit its shift might carry out, and that was dead code: after k iterations the remainder is the dividend's top k bits reduced modulo the divisor, so for k <= 31 it is below 2^31. Verified by instruction-for-instruction simulation over 400000 random pairs -- the carry bit was never set -- and the routines themselves agree with Python's // and % over 400000 pairs plus a hand-picked edge set.

Three executed cases: ir/bits.c (both forms of every bitwise and shift operator, negative operand), ir/unsig.c (every U-typed opcode and every U-typed rule, 0xfffffff0 / 9), ir/udiv.c (a DIVISOR above 2^31, which is the only thing that exercises the routines' own comparison).

WHAT THE ARGUMENTS COST TO GET RIGHT, because both were found by running the mutation rather than by reading the code:
  * ir/unsig.c with b = 7 returned the SAME number whether DIVU4 called __udivsi3 or __divsi3. The quotients differ; `x = x * b' and then `x = x & a' carried the difference away. b = 9 was chosen by checking that each signed-for-unsigned substitution moves the answer.
  * ir/udiv.c combined its quotient and remainder with `+', and under `+' the signed-compare mutation cancelled exactly modulo 2^32 (1 + 0x7ffffffd and 0xffffffff + 0x7fffffff are the same 32 bits). It is `^' now.

cases.nix gains a `pairs' table: which I-typed and U-typed rules must emit identical text and which must not, checked against the templates in both directions. That is what makes "MULU4 shares __mulsi3" a checked property instead of a comment.

REVIEW FOUND FIVE DEAD ROWS and I had shipped them. reg_rshu_reg, reg_lshu_reg, reg_boru_reg, reg_zerou and reg_cnstu_wide were selected by no corpus node, so the only thing asserting them was a mnemonic table that never consults the corpus -- each could be changed to the wrong instruction with the whole suite green, demonstrated rather than supposed. reg_rshu_reg is exactly the `sra'-for-`srl' defect this task exists to prevent. ir/unsig.c now reaches all five, and the mutations aimed at them were run against the old corpus first to confirm they passed it.

Review also found the `why' string on the bits execution case wrong at every step, with a final value contradicting its own `expect'; and drivers/udiv.s and a run.sh comment describing the signed-compare failure backwards (it subtracts at every iteration, not none). All corrected.
<!-- SECTION:NOTES:END -->
