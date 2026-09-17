---
id: TASK-081
title: A phase-2 splice is refused even inside a group that is not being compiled
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
Found by cross-model review of task-013.02; the defect is slice 1's.

poc/08-cpp/cpp.nix's `stepAt' computes

    st = b.seq (checkGlue ts) st0;

BEFORE it forks on whether the line is a directive and on whether the group is live. So the phase-2 splice refusal (task-008) fires on text inside a group that is not being compiled:

    #if 0
    ab\
    cd
    #endif
    int z;

gcc gives `int z;'. poc/08-cpp throws.

WHY THAT IS WRONG RATHER THAN MERELY STRICT. C89 6.8.1 says a group that is not being compiled is examined only to keep track of nesting, and cpp.nix argues exactly that forty lines below, at `noOperands': "in a group that is not being compiled, a directive is examined only to keep track of nesting ... otherwise the rule holds for three directives out of five". Fencing off text that does not lex the way this stage wants is what `#if 0' is FOR -- poc/08-cpp/cases.nix already has a case asserting that nonsense and refused directives are inert inside one, and this is the same rule applied to the lexer's own refusal instead of to a directive.

THE FIX IS ONE LINE: only check a line's glue when the group it is in is live. The `#if 0' that OPENS the group is itself live at the point it is read, so it is still checked; the lines it fences off are not.

THE TEST IT NEEDS is a control rather than a refusal: the must-fail entry "a continuation that joins two token characters" already pins the refusal, so what is missing is a case asserting that the same text inside `#if 0' preprocesses to nothing. cases.nix's expansion table is where it goes, beside "a skipped group is not evaluated, so nonsense and refused directives are inert".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Text containing a continuation that joins two token characters is inert inside #if 0, as 6.8.1 requires
- [ ] #2 The refusal still fires for the same text in a live group
- [ ] #3 cases.nix carries the skipped-group control, and the must-fail refusal is unchanged
<!-- AC:END -->
