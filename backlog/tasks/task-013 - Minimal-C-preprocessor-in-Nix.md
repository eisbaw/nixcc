---
id: TASK-013
title: Minimal C preprocessor in Nix
status: To Do
assignee: []
created_date: '2026-09-14 20:04'
labels:
  - frontend
  - preprocessor
dependencies:
  - TASK-002
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Per decision-005. Scope: #include (both forms), object-like and function-like #define, #undef, #if/#ifdef/#ifndef/#elif/#else/#endif with constant-expression evaluation, and #line. Deliberately NOT lcc/cpp's compatibility baggage.

Without this the project's headline claim -- Nix alone compiles C with no external toolchain -- is false, so this is a deliverable rather than a nicety.

Binding constraints from decision-001 and task-002: no traversal with input-proportional depth; never one substring per token against a whole-file haystack (superlinear, invisible below ~300kB); deepSeq inside every loop or the symptom is stack overflow rather than slowness. Task-002 left a forward-carried note about a backslash-newline divergence -- read it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Emits '# n "file"' linemarkers in the form lcc's input.c resynch() expects, so the frontend consumes our output unchanged
- [ ] #2 Function-like macro expansion handles nested and recursive invocations without re-expanding a macro inside its own expansion
- [ ] #3 Constant-expression evaluation in #if covers defined(), integer arithmetic, and the C operator precedence lcc's frontend agrees with
- [ ] #4 Differential test against a real cpp (gcc -E or lcc/cpp) on a corpus of headers, comparing token streams rather than whitespace
- [ ] #5 Loop shape obeys decision-001; linearity demonstrated on a real multi-file include graph, not asserted
- [ ] #6 Harness is mutation-tested: breaking the preprocessor and breaking the harness each fail distinctly
<!-- AC:END -->
