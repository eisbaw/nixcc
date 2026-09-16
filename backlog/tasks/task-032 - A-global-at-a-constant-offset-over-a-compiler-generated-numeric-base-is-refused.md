---
id: TASK-032
title: >-
  A global at a constant offset over a compiler-generated numeric base is
  refused
status: Done
assignee: []
created_date: '2026-09-15 05:33'
updated_date: '2026-09-16 01:30'
labels:
  - poc
  - matcher
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lcc folds a string literal's subscript into a symbol expression over a NUMERIC label:

    int f(void) { return "abcdefgh"[4]; }
      ->  4. ADDRGP4 2+4

poc/03-matcher/emit.nix's `operand' asks `isLabelName sym', which is `match "[0-9]+"' and returns null for "2+4", so the ADDRGP4 branch emits the symbol verbatim as `la a0,2+4'. poc/04-assembler's `normalise' has meanwhile renamed every numeric label definition to .Lnum_<k>_<i>, so the base `2' is not in the symbol table and the unit is refused -- loudly, naming `2' as the undefined base, which is the right failure but still a failure.

task-023 made `msg+8' over a named global work. This is the same fold over a base the compiler generated rather than the programmer, and it is the spelling every string literal will produce, so it blocks task-028 (char and strings) rather than being hypothetical.

The fix is in emit.nix, not the assembler: the numeric base has to go through the same labelOf() the bare numeric symbol does, i.e. `2+4' becomes `.Lf_2+4'.

Found by the task-023 review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A C function that indexes a string literal by a constant compiles, assembles and runs with the right value
- [ ] #2 The numeric base is mangled by the same rule a bare numeric ADDRGP4 goes through, in one place
- [ ] #3 A matcher corpus case covers it, taken from real lcc output
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Closed by task-028. poc/03-matcher/emit.nix's `operand' now splits a symbol from its displacement (`splitDisp'/`withDisp') and renames a numeric base two ways: `.L<fn>_<n>' when the function DEFINES it as a label, `.Llit_<n>' when it does not, because lcc numbers branch labels and file-scope statics from one counter. `litLabel' is exported so poc/07-parser/data.nix, which lays the lit segment down, spells the same name.

The task described the ADDRGP4 half. There is a second half it did not: `ADDRLP4 buf+3', which a LOCAL array at a constant index produces. That is a FRAME SLOT plus an integer, not a name at all, and the slot lookup failed with "which is neither a parameter nor a local". poc/03-matcher/ir/lbuf.c is the case, and it deliberately has NO entry in cases.nix's `emitted' table so that only executing the program catches a dropped displacement: it returns 105 instead of 293.
<!-- SECTION:NOTES:END -->
