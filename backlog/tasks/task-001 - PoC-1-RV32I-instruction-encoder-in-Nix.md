---
id: TASK-001
title: 'PoC-1: RV32I instruction encoder in Nix'
status: Done
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 18:32'
labels:
  - poc
  - backend
  - done-before-backlog
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Encode every RV32I instruction format from pure Nix, given that Nix has bitAnd/bitOr/bitXor but no shift operators. Shifts become multiply/divide against a precomputed power-of-two table.

Kill-risk: can Nix do instruction-encoding bit manipulation correctly and readably at all?

Outcome: yes. Verified byte-identical to GNU as.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Encoder covers R, I, S, B, U, J formats plus shift-immediate and system instructions
- [x] #2 Negative immediates encode correctly (div truncates toward zero, so values are folded to unsigned before field extraction)
- [x] #3 Out-of-range immediates throw rather than silently truncating
- [x] #4 Differential test against riscv32-none-elf-as passes for all cases
- [x] #5 Runnable as 'just poc-encoder'
- [x] #6 Throw paths covered by a must-fail suite with control cases, since a differential test cannot exercise them
- [x] #7 Harness is mutation-tested: breaking the harness itself must fail, not silently pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in poc/01-encoder/. 126 instructions compared against GNU as, all byte-identical, covering every RV32I format including the shuffled B-type and J-type immediate layouts, S-type split immediates at both bounds, FENCE, and all 33 register names spelled out explicitly.

QA review found the first harness could report PASS while comparing nothing, and reproduced it: pointing objcopy at a nonexistent section still printed "48 instructions compared / PASS". Root cause was zip() truncating to the shortest sequence while the printed count came from len(ours) -- a claim, not a measurement. Harness now guards case count, asm/encoder agreement and as/encoder agreement, and reports a counted total.

Mutation-tested afterwards to prove the guards work: breaking the harness, emptying cases.nix, corrupting srl funct7, and inverting the range predicate each now fail with distinct exit codes.

QA also found six instructions (slti, sltu, ori, srl, lh, lhu) survived deliberate funct3 corruption because nothing exercised them, and that throw paths were entirely untested. Added must-fail.nix: 17 reject cases plus 6 control cases so a blanket-throw encoder cannot pass, and a toBytes round-trip property since toBytes is on the emulator path rather than the GNU-as diff path.
<!-- SECTION:NOTES:END -->
