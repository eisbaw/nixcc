---
id: TASK-052
title: A single expression is capped at about 1300 operands by Nix's call depth
status: To Do
assignee: []
created_date: '2026-09-15 20:20'
labels:
  - frontend
  - scale
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Measured while closing task-027. A translation unit with 8000 statements compiles (467 kB of listing); a translation unit with 2000 functions compiles (728 kB). But ONE expression of the form `a+a+a+...+a' compiles at 1200 terms and fails at 1400 with "stack overflow; max-call-depth exceeded".

This is not the banned shape from decision-001 -- the statement, declaration and top-level loops are tail-recursive and were measured to 8000 iterations without trouble, so nothing has depth proportional to FILE length. What is proportional is depth per EXPRESSION, and there are three contributors, all of which would have to be fixed together to move the number:

  * poc/07-parser/parse.nix's expr3/sameLevel recurses once per binary operator at the same precedence level. lcc's is a `while' loop.
  * The tree it builds is a left spine, so poc/07-parser/trees.nix's root1 and poc/07-parser/dag.nix's listnodes each walk it that deep.
  * poc/07-parser/dag.nix's genForest (symbolic.c's visit) walks the resulting dag the same depth.

lcc has the same property -- listnodes and visit are recursive there too -- so this is not a divergence from the reference, it is a smaller constant. decision-001's guidance is that recursive descent is fine because its depth tracks expression NESTING, well under a hundred for real C; a 1300-term expression is not real C.

WHY IT IS FILED ANYWAY: task-029 (slice 3) adds initialisers, and a large array initialiser is exactly a long operand chain. Whoever writes it should measure before assuming the limit is far away.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The limit is re-measured after slice 3's initialisers land, and the task is closed or the number raised
- [ ] #2 If it is raised, expr3's operator loop is iterative and the tree walks are the only remaining contributors
<!-- AC:END -->
