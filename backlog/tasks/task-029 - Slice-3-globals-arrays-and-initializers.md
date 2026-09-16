---
id: TASK-029
title: 'Slice 3: globals, arrays and initializers'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-16 00:13'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-023
  - TASK-028
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Third vertical slice per decision-007. Depends on the backend understanding a symbol with a constant offset (task-023), since lcc folds msg[2] into ADDRGP4 msg+8.

Note decision-004: little_endian affects initializer splitting in lcc/src/init.c, so the rcc-rv32 wrapper matters here more than anywhere else -- diffing against the raw oracle would silently compare against a big-endian layout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 File-scope globals, arrays and their initializers parse, reach the DAG and are placed in .data by the assembler
- [ ] #2 Initializer splitting matches rcc-rv32 for multi-byte and mixed-type initializers
- [ ] #3 A C program using a global array and an initializer compiles from .c and runs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-027 (slice 1), commits d64d382 and 9330404.

WHERE THE GLOBAL REFUSAL IS. poc/07-parser/listing.nix's `doglobal' throws naming this task the moment a tentative global needs a BSS definition, and parse.nix's `dclglobal' throws on an initialiser. decl.c's doglobal() is what you are porting: `defglobal(p, BSS)' then `(*IR->space)(p->type->size)'. listing.nix had `globalSym' and `space' written and unused; they were deleted rather than left as dead code you would have to trust, so write them again from symbolic.c's I(global) and I(space) -- they are two lines each.

THE ORDER OF THE TRAILING DIRECTIVES IS NOT OBVIOUS and is already half-ported. decl.c's finalize() walks `externals' then `identifiers', and lcc's foreach() iterates a table's `all' list, which install() PUSHES onto -- so it is REVERSE installation order. listing.nix's `finalize' reverses `externalOrder' and `globalOrder' for exactly that reason. Getting it wrong moves every `import' and `global' line.

ARRAY TYPES ALREADY PRINT CORRECTLY and that took a fix: lcc COLLAPSES nested dimensions, so a two-dimensional array is `array 2,3 of int' and not `array 2 of array 3 of int'. poc/07-parser/c/arrays.c holds it, and a mutation is aimed at it. Initialisers are the part that is missing.

THE ONE MEASURED CEILING THAT CONCERNS YOU: task-052. A single expression caps at about 1300 operands before Nix's call depth gives out, while statements scale to 8000 and functions to 2000. A large array initialiser is exactly a long operand chain, so MEASURE before assuming the limit is far away. The three contributors are named in that task.

AND decision-004's warning is live here more than anywhere: lcc/src/init.c consults little_endian for initialiser splitting, so `just ir' through the rcc-rv32 wrapper is the only oracle that means anything.

CARRIED FROM TASK-051 (the bitwise, unary and unsigned rule gap).

The rule table is no longer the thing that stops a program running. poc/03-matcher/rules.nix now covers the bitwise and unary opcodes and the whole U-typed family, __udivsi3/__umodsi3 exist in runtime.s, and five programs compile from .c and execute. If this slice's C is refused, the refusal is about the FRONTEND or about a genuinely absent row -- it is no longer the backend having no rules for ordinary integer C.

WHAT TO EXPECT TO ADD ANYWAY. The table covers what the corpus emits and nothing more, and that is a trace rather than a specification. Absent today and a loud refusal naming the opcode: CVUU4, CVIU4 below width 4, CALLP4, CALLD4, and a NEGU4 that lcc never emits (its ops.h gives NEG only the I and F kinds, so -u arrives as BCOMU4 then ADDU4 of 1 -- checked against rcc-rv32, not inferred). Add rows; do not assume the absence is deliberate design.

THE LESSON THAT COST THE MOST, and it applies to any rule this slice adds. A rule the corpus never SELECTS is asserted by nothing, however many tables name it. cases.nix's lowerings and libcalls tables check the template of a NAMED rule and never that the matcher chooses it, so five U-typed rows shipped that could be changed to the wrong instruction with the whole suite green -- reg_rshu_reg among them, where sra for srl is the exact defect the slice existed to prevent. Two reviews found it; I had not. Walk the label tables and subtract the rules that fired from the rules that exist. task-053 is that check, unwritten.

AND THE ONE THAT COST THE SECOND MOST: a test case's ARGUMENTS are part of the test. ir/unsig.c with a divisor of 7 returned the same number whether the unsigned divide called __udivsi3 or __divsi3, because a later mask carried the difference away; ir/udiv.c combined its two halves with + and the two errors cancelled exactly modulo 2^32. Both found by running the mutation and watching the exit code not move. Run your mutations before believing your corpus discriminates.

For slice 2 specifically: the narrow load and store rules (task-024) are in and executed, and the signed/unsigned load pair is still INVISIBLE to any executed answer because lcc promotes every narrow access -- cases.nix's lowerings table is what tells lb from lbu, and task-033 is what would make it observable.

For slice 3: ADDRGP4 sym+N is taken verbatim by the rule table and resolved by poc/04-assembler at layout time (task-023), so the matcher's only job there is not to lose the displacement. ir/gsym.c pins that.
<!-- SECTION:NOTES:END -->
