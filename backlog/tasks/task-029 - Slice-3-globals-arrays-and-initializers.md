---
id: TASK-029
title: 'Slice 3: globals, arrays and initializers'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-16 01:30'
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

FORWARD-CARRIED from task-028 (slice 2). Read this before writing a file-scope variable.

WHAT SLICE 2 LEFT YOU, and it is more than the criteria say. The machinery for
laying BYTES DOWN AT FILE SCOPE now exists and works end to end: listing.nix
has `defglobal' (decl.c's, which picks the segment, exports a non-static and
announces it), `doconst' and `defstringText'; poc/07-parser/data.nix reads
`segment lit', `global N', `defstring' and `defconst' back out of the listing
and produces .data items; and poc/03-matcher/emit.nix knows how to name a
generated file-scope symbol (`.Llit_<n>') as distinct from a branch label
(`.L<fn>_<n>'). A slice-3 global in `segment data' or `segment bss' needs
data.nix to grow TWO more line kinds -- `space N' for bss and `defaddress' for
a pointer initialiser -- and a decision about the label name for a NAMED
global, which is not `.Llit_' anything: it is the identifier itself.

`defglobal' takes the segment as a bare integer (1 text, 2 bss, 3 data, 4 lit)
because that is how parse.nix already calls `swtoseg'. listing.nix's `segName'
is the one table that names them. If slice 3 grows a third caller, that is the
moment to make the enum a named attrset rather than three bare numbers.

WHAT WILL BITE YOU FIRST, and it is not the initialiser. `listing.nix's
doglobal' refuses a TENTATIVE global naming task-029, and `parse.nix' refuses
`int g = 1;' and a local `static'. All three are one-line refusals with the
task named, so they are easy to find -- but the THIRD one is the interesting
one: a local static is a GLOBAL with a generated name, and it reaches
`idtree' through the `scope == GLOBAL || sclass == static' arm that string
literals now use. Two consumers of one path.

lcc's init.c is the file you have not read yet and it is where the endianness
lives. decision-004 says the oracle must be rcc-rv32 and NEVER raw
`rcc -target=symbolic', because the raw one declares little_endian = 0 and
init.c consults that when it SPLITS an initialiser into defconst pieces. Slice
2 hit the same seam from the other side: a wide string literal is emitted as
one `defconst unsigned.2' per unit and data.nix lays those down little-endian.
If your defconst bytes come out backwards, that is where to look first.

THE BACKEND HAS FIVE GAPS SLICE 2 OPENED and did not close: CNSTP4, CVUP4,
CVPU4, SUBP4 and RETP4 have no row in poc/03-matcher/rules.nix. That is
task-054. `char *p; p = 0;' compiles to IR that diffs clean against lcc and is
refused at instruction selection. A slice-3 global whose initialiser is a
pointer will meet the same wall, so 054 is probably a prerequisite rather than
a neighbour.

STILL REFUSED AND STILL YOURS: struct, union, enum, switch, goto, labels,
float, the preprocessor (task-013), a literal byte above 127 (task-046) and a
mixed-width literal join (task-047).

AND THE TWO LESSONS, restated because they cost this project the most:

  * A rule the corpus never SELECTS is asserted by nothing (task-053, still
    unwritten). Slice 2 added no rows to rules.nix but did add three paths to
    emit.nix, and each got its own mutation; one of them deliberately has NO
    entry in cases.nix's `emitted' table so that only executing the program
    catches it.

  * A test case's ARGUMENTS are part of the test. run/strings.c prints its
    argument, and the assumption that it is two digits is a guard on the
    critical path in cases.nix with a mutation aimed at it -- not a comment.

ONE PRACTICAL THING. The parser PoC's mutation stage is 56 mutations and takes
the best part of half an hour. Several fragments are a LINE OF THE DIFF, and
oracle.py prints only the first two differing files, so ADDING A CORPUS FILE
THAT SORTS EARLY moves fragments out of the window: `ptrs.c' and `strings.c'
did that to four existing mutations in this slice. To find them all in one run
rather than one per run, temporarily change the distinctness loop at the bottom
of run.sh to record a mismatch and `continue' instead of `exit 1', run once,
read every mismatch, then put the loop back. Half a day saved.
<!-- SECTION:NOTES:END -->
