---
id: TASK-013.01
title: 'cpp slice 1: object-like macros and the conditional family'
status: To Do
assignee: []
created_date: '2026-09-16 17:27'
labels:
  - frontend
  - preprocessor
  - slice
dependencies:
  - TASK-011
parent_task_id: TASK-013
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First preprocessor slice, and deliberately the one that needs no header provenance decision -- it operates on a single translation unit with no #include.

Scope: line splicing (backslash-newline), #define of object-like macros, #undef, #ifdef/#ifndef/#else/#elif/#endif, #if with constant-expression evaluation including defined(), and #line. Plus the linemarker output the frontend already expects.

Ends with something that RUNS: a C file using object-like macros and conditional compilation compiles and executes through the existing pipeline.

Note the lexer already handles backslash-newline continuations, and task-002 left a forward-carried note about a divergence there worth checking. Constant-expression evaluation should reuse poc/06-constants rather than growing a second integer evaluator -- and remember Nix integer overflow THROWS (decision-001), which is why that module detects by comparison before the multiply.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Object-like #define and #undef expand correctly, including a macro whose body references another macro
- [ ] #2 The full conditional family works, with #if constant-expression evaluation covering defined(), integer arithmetic and C operator precedence
- [ ] #3 Emits '# n "file"' linemarkers in the form lcc's input.c resynch() expects, so the frontend consumes the output unchanged
- [ ] #4 Differential against gcc -E on a corpus, comparing TOKEN STREAMS rather than whitespace
- [ ] #5 A C program using macros and conditional compilation compiles from .c and RUNS end to end
- [ ] #6 Harness mutation-tested: breaking the preprocessor and breaking the harness each fail distinctly
<!-- AC:END -->
