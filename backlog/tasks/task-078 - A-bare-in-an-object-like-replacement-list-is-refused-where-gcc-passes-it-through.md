---
id: TASK-078
title: >-
  A bare # in an object-like replacement list is refused where gcc passes it
  through
status: To Do
assignee: []
created_date: '2026-09-17 07:37'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Carried from task-013.01 and kept by task-013.02.

In a FUNCTION-LIKE macro a `#' is the stringify operator and slice 2 implements it. In an OBJECT-LIKE macro there are no parameters for it to take, so C89 gives it no meaning and gcc simply passes the `#' through as an ordinary preprocessing token -- measured: '#define S # x' preprocesses without complaint.

poc/08-cpp refuses it instead, naming this task. The reason is the one slice 1 gave: a `#' that reached poc/07-parser would be reported as unpreprocessed input ('this frontend is fed raw C and has no preprocessor yet'), which points the reader at the wrong stage entirely. Refusing at the `#define' points at the line that wrote it.

This is a deliberate divergence rather than a gap, and it is filed so it is not mistaken for one. What would close it: emit the `#' as an ordinary token and let the parser's own diagnostic name the preprocessor -- which is only an improvement once that diagnostic can say WHERE the `#' came from.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Either a bare # in an object-like replacement list passes through as gcc does, or the refusal is declared permanent under task-061
<!-- AC:END -->
