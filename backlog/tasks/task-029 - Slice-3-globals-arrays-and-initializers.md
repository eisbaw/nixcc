---
id: TASK-029
title: 'Slice 3: globals, arrays and initializers'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-15 22:26'
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
<!-- SECTION:NOTES:END -->
