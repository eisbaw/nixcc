---
id: TASK-074
title: 'A #if with thousands of flat operators exceeds max-call-depth'
status: To Do
assignee: []
created_date: '2026-09-16 19:35'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by cross-model review of task-013.01. A #if whose expression is 3000 flat + terms dies with "stack overflow; max-call-depth exceeded" in poc/08-cpp/cpp.nix's `level'.

WHY IT IS A REAL VIOLATION AND NOT A CORNER. decision-001 bans any traversal whose DEPTH tracks input length, and grants recursive descent an exemption because its depth tracks expression NESTING, which is under 100 for real C. A left-associative operator chain is not nesting: `level' recurses once per OPERATOR, so the depth is the number of terms. The implementation note in cpp.nix argued the depth is "bounded by one logical line of source", and that is not the exemption decision-001 grants -- a logical line can carry continuations, and the rule is about proportionality rather than about which line the input sits on.

The same shape is in `logand', `logor' and `conditional'. The #if expression parser is the only recursive descent in poc/08-cpp; everything else is a genericClosure.

WHAT THE FIX LOOKS LIKE. The binary levels are iterative in intent already -- `go' is a loop written as a tail call that Nix does not eliminate. poc/02-lexer's `runUntil' is the shape this tree uses for a scan that must not grow its depth: fold over windows that double, so the depth is O(log run length). A precedence-climbing parser driven by an explicit operator stack would also do it, and is the usual answer.

Nothing real is anywhere near this. It is filed because decision-001 is a rule this project keeps rather than a guideline, and because an expression built by macro expansion is not bounded by what anybody typed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A #if expression with 10000 flat operators evaluates, or is refused with a diagnostic -- not a max-call-depth overflow
- [ ] #2 The depth of the #if parser is shown not to track the number of operators, by measurement rather than by argument
- [ ] #3 cpp.nix's comment about recursive descent says which exemption it is claiming and why it holds
<!-- AC:END -->
