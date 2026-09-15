---
id: TASK-028
title: 'Slice 2: char, byte loads and stores, and string literals'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-15 09:30'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-024
  - TASK-027
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second vertical slice per decision-007. Depends on the backend gaining byte load/store rules (task-024), which is why that comes first.

This is the slice that makes string handling real. Note decision-001: Nix strings cannot hold NUL, so a decoded C string literal must be a byte list throughout -- this is also why the closed loop works at all.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 char declarations, byte loads and stores, and string literals parse and reach the DAG
- [ ] #2 String literals are byte lists end to end; a literal containing an embedded NUL survives compilation and execution
- [ ] #3 A C program using char arrays and string literals compiles from .c and runs, printing correct output
- [ ] #4 DAG diffs against rcc-rv32 for the extended corpus
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-024, which this depends on (commit 7de656d).

THE BACKEND IS READY FOR char, AND THE SHAPE MATTERS. poc/03-matcher/rules.nix has lb, lbu, lh, lhu, sb and sh, the conversions lcc wraps every narrow access in, and CNSTI1. poc/03-matcher/ir/chars.c is the worked example: it reads the same bytes signed and unsigned, stores back through every width, and returns 1649 with gcc agreeing.

WHAT WILL BITE YOU FIRST, and it is not char. lcc folds a string literal's subscript into a symbol expression over a COMPILER-GENERATED numeric base:

    int f(void) { return "abcdefgh"[4]; }
      ->  4. ADDRGP4 2+4

poc/03-matcher/emit.nix's `isLabelName' is `match "[0-9]+"', which does not recognise "2+4", so it passes the symbol through unmangled and poc/04-assembler refuses it -- the numeric label was renamed to .Lnum_<k>_<i> at layout time, so the base `2' is undefined. Loud, not silent, but it is the spelling EVERY string literal produces. Filed as task-032 and it is squarely in this slice's path. Do it first or you will hit it on your first literal.

STRING LITERALS AND NUL. decision-001 is why this slice exists in the shape it does: Nix strings cannot hold a NUL byte, so a decoded literal must be a byte list from the lexer all the way to .data. poc/05-loop/items.nix's `asciiBytes' is the existing converter and it THROWS on a character it has no code for rather than emitting a zero -- keep that property; a message that silently lost a character would still assemble, run, and print something plausible.

WHAT THE EXECUTION ORACLE CANNOT SEE, which changes how you test this slice. lcc promotes every narrow load, so an INDIRI1 always arrives under a CVII4 whose shift pair re-normalises the register: `lb' and `lbu' leave the same 32 bits and NO C program's answer distinguishes them today. Measured -- the whole rule table with the two exchanged still returns 1649. poc/03-matcher/cases.nix's `lowerings' table is the only thing checking it, against the table rather than a result, and it says so. Two consequences for you: do not write a test whose premise is that the load's sign is observable, and do not delete that table when it looks redundant. It stops being the only witness when task-033 fuses the load and the conversion.

COST OF THE UNFUSED FORM: ir/chars.c compiles to 91 body instructions, of which 23 are extension shifts and masks and 4 are `mv sN,sN' self-moves. Roughly 30% of a char-heavy function is currently waste. task-033 has the measurement and the two ways out, including the trap in the cheaper one (a zero-cost fragment producing the register nonterminal hands its users the register its KID was reduced into, and burg.nix now refuses such a rule outright).

NOT COVERED by the rule table, so expect a refusal: CVUU4 at any width, CVIU4 below width 4. Both are one row each when a case produces them; the conversion block in rules.nix says explicitly that it is a trace of what has been seen and not a specification.
<!-- SECTION:NOTES:END -->
