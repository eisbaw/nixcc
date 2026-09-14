---
id: TASK-003
title: 'PoC-3: lburg-style bottom-up tree matcher for RV32'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 19:50'
labels:
  - poc
  - backend
  - codegen
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement instruction selection as lcc does it: rules as declarative data, matched bottom-up over the DAG with dynamic programming, then reduced to emit instructions.

Kill-risk: this is the single thing that made us pick lcc over tcc. An lburg rule is (nonterminal, tree pattern, cost, template), e.g. `base: ADDI4(reg,acon) "%1(%0)"`. If declarative tree matching does not work well in Nix, the choice of lcc was wrong and we should reconsider before porting 10k lines against it.

Does not need the full rule set. A handful of rules that prove labeling, cost-driven choice, and reduction is enough.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rules are data (nonterminal, pattern, cost, template), not hand-written emission code
- [ ] #2 Bottom-up labeling assigns each DAG node a cost and winning rule per nonterminal
- [ ] #3 Reduction walks the labels and emits RV32 assembly
- [ ] #4 Covers at least CNSTI4, ADDRLP4, ADDRGP4, INDIRI4, ASGNI4, ADDI4, SUBI4, LSHI4, CALLI4, RETI4 and one conditional branch
- [ ] #5 At least one test where two rules match the same subtree and the cheaper one demonstrably wins
- [ ] #6 Emitted assembly for a hand-built DAG assembles cleanly with riscv32-none-elf-as
- [ ] #7 The hand-built DAG is taken from real lcc output ('just ir') for a small C function, not invented
- [ ] #8 Runnable as 'just poc-matcher'
- [ ] #9 Covers MULI4 and DIVI4 as libcalls, not patterns: RV32I has no multiplier, so these lower to __mulsi3/__divsi3 calls (see decision-003)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: the loop shape is settled, use it rather than rediscovering it.

A pass that walks a sequence and EMITS one value per step is builtins.genericClosure, not foldl'. foldl' carries a scalar accumulator and cannot emit; acc ++ [x] is quadratic (decision-001); a self-referential genList has depth n. genericClosure is an iterative worklist in the evaluator, measured linear at constant stack depth: 0.07/0.11/0.18/0.35/0.49 s at 25000/50000/100000/200000/400000 steps. Its keys must be unique -- it silently DROPS duplicates -- and it forces only 'key', so the operator must deepSeq the item it returns or the unforced field chain grows as deep as the loop and dies with 'stack overflow (possible infinite recursion)'. Not slowly: at 100000 steps.

A bottom-up tree matcher is mostly recursive descent over an expression tree, whose depth tracks nesting rather than input length, so it is fine. But the labeller walking a whole function's DAG in one pass is exactly the emit-per-step shape above, and lburg's own cost tables are attrsets, which have the same O(size) copy cost as lists: build a rule table once, never by repeated //.

builtins.substring COPIES ITS HAYSTACK. Any pass that cuts text out of a long string once per node is quadratic in the file: 22.68 s against 2.13 s on a 2.2 MB file. Slice out of an exploded character list with concatStringsSep instead; builtins.split "(.)" explodes a string 10x faster than genList+substring.

Cost to expect: the lexer runs at 47000 tokens/s and about 4 kB of peak RSS per token -- 82 MB for 1143 lines, 501 MB for 16720. Memory, not asymptotics, is the budget that will bite a pass that keeps a labelled tree live.

Harness lessons, all earned the hard way: order the guards so a HARNESS FAULT can never pre-empt a real diagnosis; assert the fields nothing else looks at (a lexer reporting 'line 1' for everything passed every test in poc/02-lexer until a reviewer noticed); check what errors SAY, not only that they threw, which needs a shell loop because builtins.tryEval never gives you the message; and mutation-test the measurement code too, not just the code under test.
<!-- SECTION:NOTES:END -->
