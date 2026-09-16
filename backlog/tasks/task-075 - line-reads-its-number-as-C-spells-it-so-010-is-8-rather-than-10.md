---
id: TASK-075
title: '#line reads its number as C spells it, so 010 is 8 rather than 10'
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
Found by cross-model review of task-013.01. `#line 010' relocates to line 8 here and to line 10 under gcc.

WHY. poc/08-cpp's `relocate' validates the token with match "[0-9]+" and then takes its value from poc/06-constants' evalICON, which reads a C integer constant -- and in C a leading zero means octal. The standard's #line takes a DIGIT SEQUENCE, which is decimal whatever it starts with; the same is true of the linemarker form lcc's resynch() parses, which reads digits with `lineno = 10*lineno + *cp++ - 48'.

So the regex is right about the shape and wrong to hand the text to a C constant evaluator afterwards. Reusing poc/06-constants was the correct instinct in the #if evaluator, where the operand IS a C constant, and the wrong one here.

The overflow guard on that call is still wanted -- `#line 99999999999' must not relocate to a clamped 4294967295 -- so whatever replaces evalICON has to keep it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 #line 010 relocates to line 10, matching gcc and lcc's resynch()
- [ ] #2 A line number too large to represent is still refused rather than clamped
- [ ] #3 poc/08-cpp/cases.nix carries a leading-zero relocation case
<!-- AC:END -->
