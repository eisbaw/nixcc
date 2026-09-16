---
id: TASK-055
title: A wide signed constant that no corpus case materialises
status: To Do
assignee: []
created_date: '2026-09-16 02:02'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/rules.nix's `reg_cnst_wide' is the fallback for a signed constant too wide for the 12-bit immediate field -- `li %c,%a', which GNU as expands to lui+addi. task-053's census reports it "unreached": every CNSTI4 in poc/03-matcher/ir/ is small enough for `con_cnst', and with the `reg: con' chain that is cheaper, so this row wins the `reg' nonterminal nowhere and its template is asserted by nothing but the row itself.

Its UNSIGNED twin `reg_cnstu_wide' is reduced -- ir/unsig.c's data has bit 31 set -- and run.sh's mutation "a wide unsigned constant is materialised with lui alone" is what says so. The signed side has no such witness.

Reachable C, and cheap: any `x + 100000' whose constant survives folding arrives as ADDI4(reg, CNSTI4 100000).

WHAT MAKES IT WORTH DOING RATHER THAN DECLARING FOREVER: the census's declaration is honest but it is still a gap, and `li' with a 32-bit operand is where poc/04-assembler's lui/addi materialisation meets the rule table. An executed answer discriminates here -- a constant materialised wrong changes the number the program returns -- which is not true of most of the rows `lowerings' covers.

The arguments are part of the test: pick a constant whose low 12 bits are NEGATIVE as signed (so the lui half has to be incremented), because a materialisation that forgets that is right for every constant whose low half is small.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 poc/03-matcher's corpus contains a signed constant too wide for the immediate field, and cases.nix's census reports reg_cnst_wide reduced rather than unreached
- [ ] #2 The constant's low 12 bits are negative as signed, so the lui/addi carry is exercised
- [ ] #3 A mutation makes the materialisation wrong and the executed answer moves
<!-- AC:END -->
