---
id: TASK-051
title: 'Backend rules for the bitwise, unary and unsigned integer opcodes'
status: To Do
assignee: []
created_date: '2026-09-15 19:44'
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
- [ ] #1 poc/03-matcher/rules.nix covers the bitwise, unary and unsigned integer opcodes listed above
- [ ] #2 poc/07-parser/run/ gains a program that uses &, |, ^, ~, unary - and unsigned arithmetic, and it RUNS with the right output
- [ ] #3 The unsigned divide and remainder go through a runtime routine differential-tested the same way __divsi3 and __modsi3 are
<!-- AC:END -->
