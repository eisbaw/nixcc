---
id: TASK-082
title: 'render decides adjacency pairwise, and the lexer munches maximally over a run'
status: To Do
assignee: []
created_date: '2026-09-17 09:13'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by cross-model review of task-013.02.

poc/08-cpp/cpp.nix's `render' decides whether to write a space before token j by asking `staysApart' about the PAIR (j-1, j). The lexer is maximal-munch over a RUN, so a boundary that is safe pairwise can still be unsafe once three tokens are written together. The only three-character punctuator in poc/02-lexer is `...' (ELLIPSIS), so the shape needs three `.':

    #define D .
    int a; a D..b;

gcc renders `a . ..b'; we render `a ...b', which re-lexes to ELLIPSIS where our own token stream has three separate `.'. oracle.nix's third comparison -- "our own render, re-lexed, against our token stream" -- is exactly the check that would catch this, and no corpus input reaches it.

SEVERITY IS LOW AND WORTH SAYING WHY. `..' is not valid C anywhere, and `...' in valid C appears only in a prototype where it is written as one token, so the reachable instances turn invalid C into differently invalid C. It is filed because the comment above `lexJoined' claims `##' and `render' are "the same question asked for opposite answers", and that is true per BOUNDARY and not true per line.

WHAT THE FIX COSTS. Re-checking each token against the accumulated tail rather than against its predecessor makes `textOf' quadratic in line length, in a function that already calls the lexer once per zero-whitespace boundary. The cheaper shape is to ask `staysApart' about the pair and, only when it says they may be written together, ask again about the three-character window -- bounded by the longest punctuator, which is a property of poc/02-lexer's `punct3' rather than of the input.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A rendered line re-lexes to the token stream it was rendered from, for a run of three tokens as well as a pair
- [ ] #2 The corpus gains the input that reaches it, so oracle.nix's render round-trip is what proves it
<!-- AC:END -->
