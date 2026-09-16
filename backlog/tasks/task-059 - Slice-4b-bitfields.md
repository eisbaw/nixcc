---
id: TASK-059
title: 'Slice 4b: bitfields'
status: To Do
assignee: []
created_date: '2026-09-16 08:21'
updated_date: '2026-09-16 13:58'
labels:
  - frontend
  - slice
  - compound-types
dependencies:
  - TASK-058
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split from slice 4a deliberately, because this is where the defect density is. Also zero new backend rules -- a bitfield read-modify-write through a pointer lowers entirely in the frontend to INDIRU4/BANDU4/RSHU4/LSHU4/BORU4/CNSTU4/CVUI4/CVIU4/ASGNU4, all delivered by task-051. Max tree depth of the store is 3 against depthRegs of 6, so task-016 is not a prerequisite either.

The sharp edge is that the lsb computation is little_endian-dependent. decision-004 rests on exactly this example: `unsigned b:5` produces shift constant 24 at little_endian=0 and 3 at 1. Get it wrong and the oracle catches it only if the wrapper is right.

THE BITE: a bitfield whose value survives a round trip is not a test. Store a value, read it back, AND read back a NEIGHBOURING field in the same word -- a shift constant off by one changes the neighbour, not the field you stored.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bitfield declaration, read and write parse and diff against rcc-rv32 through the little_endian=1 wrapper
- [ ] #2 A program stores a bitfield, reads it back, AND reads back a neighbouring field in the same word; an off-by-one shift constant changes the neighbour
- [ ] #3 Signed and unsigned bitfields both covered, since their extension differs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
WHAT task-058 LEFT IN PLACE FOR THIS, and the two traps it deliberately did
not spring.

THE FIELD RECORD IS ON THE TAG SYMBOL. poc/07-parser/sym.nix's emptySymbol
carries `fields = [ { name; type; offset; } ]', `cfields' and `vfields' -- lcc's
u.s, in the same place lcc keeps it and for the same reason: decl.c fills them
in AFTER the type has been handed out. A bit field adds `bitsize' and `lsb' to
those records and nothing else moves.

THE LAYOUT LOOP IS decl.c's WITH EVERY BIT-FIELD TERM REMOVED, and the removal
is documented at the site (parse.nix's `fields', the `place' fold). `bits' is
always zero there and `bits2bytes(bits - 1)' is zero with it, so what is left
is the roundup-place-advance pair. Putting the terms back is reading decl.c's
loop again with `bits' live; the comment says which terms were dropped.

ONE THING THAT MUST COME BACK WITH THEM and is not in the code at all:
decl.c's fields() REMOVES from the flist, after the layout, every field whose
name begins with a digit. Those are the generated names newfield() gives an
unnamed bit field. They still consumed offsets, so the filter has to run after
the layout and not during it. task-058 left it out because it is unreachable
while a `:' is refused -- there is no way to make a digit-named field -- and
because dead code that looks live is worse than a note.

`sizeof' APPLIED TO A BIT FIELD is an lcc error that this frontend does not
raise: expr.c checks `rightkid(p)->op == FIELD' in the SIZEOF arm and parse.nix
does not. It is unreachable today for the same reason.

THE REFUSALS ARE ALREADY WHERE THEY BELONG, three of them, and each names this
task: parse.nix's `fields' on the `:' (the reachable one), dag.nix's FIELD arm
in listnodes, and trees.nix's asgntree. simp.nix's `zerofield' is the fourth
and the interesting one -- task-058 turned it from ABSENT into a throw, wired
into all four of simp.c's EQ/NE chains at exactly the position simp.c's macro
sits, so making it the real rewrite is replacing a body rather than finding a
place to put one. Read the note above it before deleting it: it exists because
task-058 lifted the gate that used to make it unnecessary.

THE ORACLE WRAPPER NOW PASSES TWO FLAGS, not one: -little_endian=1 and
-wants_argb=0. decision-004's worked example is still yours -- `unsigned b:5'
shifts by 24 at little_endian=0 and by 3 at 1 -- and the second flag does not
touch bit fields. Do not diff against raw `rcc -target=symbolic'.

trees.nix's `asgntree' already carries lcc's FIELD bypass (`lvalue' is skipped
when the left operand is a FIELD) and the const-field check that task-058 added
beside it. The read side, dag.c's FIELD case with its shift-mask pair, has no
counterpart yet.
<!-- SECTION:NOTES:END -->
