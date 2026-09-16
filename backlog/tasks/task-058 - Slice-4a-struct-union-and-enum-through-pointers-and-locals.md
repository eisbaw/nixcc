---
id: TASK-058
title: 'Slice 4a: struct, union and enum through pointers and locals'
status: To Do
assignee: []
created_date: '2026-09-16 08:21'
labels:
  - frontend
  - slice
  - compound-types
dependencies:
  - TASK-027
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The user's steer, and the cheapest remaining cornerstone. Compound types are the single largest gap in the compiler and until now had NO TASK ANYWHERE -- the parser refuses them with "outside slice 1" while no later slice was ever filed to pick them up.

MEASURED, not assumed: a full cut-1 program (struct with char and int members forcing padding, union, enum with an explicit initialiser, sizeof, local struct, field read and write, pointer deref) emits 16 opcodes and EVERY ONE already has a rule in poc/03-matcher/rules.nix. Zero new backend rules, zero new nonterminals. Verified by the orchestrator. poc/03-matcher/ir/field.c has been compiling and executing struct field access since task-003 from lcc-supplied IR.

So this is a FRONTEND-ONLY slice that runs end to end on the day it lands -- exactly the shape decision-007 asks for.

RESOLVE THE TYPE-IDENTITY BOUNDARY IN THE PLAN, BEFORE BUILDING FIELDS ON IT. poc/07-parser/types.nix replaces lcc's pointer-identity on types with Nix STRUCTURAL equality, using the name field to keep int and long int distinct. lcc's newstruct mints a fresh symbol per declaration, so two distinct structs are never equal even with identical fields. Under structural equality two different anonymous structs with the same field list would compare EQUAL, and so would the same tag redeclared in an inner scope. eqtype has no STRUCT arm at all today. No oracle diff will catch this, because lcc prints the TAG NAME and the listings would agree.

Also: poc/07-parser/simp.nix documents that simp.c's zerofield is ABSENT rather than throwing, on the grounds that parse refuses struct first. Lifting the parse refusal silently un-gates it. That is the one place the "refuse loudly rather than miscompile" rule is satisfied by a gate elsewhere.

Groundwork already present: types.nix has STRUCT=9/UNION=10/ENUM=13 with lcc's numeric values, isstruct, isenum, and ttob returning a B kind for aggregates. parse.nix's specifier is a token-consuming accumulator whose typedef-name arm already injects an arbitrary type. ops.nix declares FIELD with refusal stubs in trees.nix and dag.nix. sym.nix records already carry structarg and listing.nix already prints it.

Genuinely new: a TAG NAMESPACE in sym.nix (a parallel table per scope frame, threaded through install/lookup/lookupIn/enterscope/exitscope), the field list and layout with padding, outtype and eqtype struct arms, and a type uid. Roughly 500-700 lines against a 5586-line frontend, comparable to slice 2.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Type identity for aggregates is decided and written down BEFORE fields are built on it: two distinct structs with identical field lists must not compare equal, nor must a tag redeclared in an inner scope
- [ ] #2 struct, union and enum parse, reach the DAG, and diff byte-for-byte against rcc-rv32 including the listing spellings (type=struct P, type=array 2 of struct P, type=pointer to union U)
- [ ] #3 A C program using a struct through a pointer AND a local struct compiles from .c and runs on the emulator
- [ ] #4 The executed answer weights fields 1/2/4/8 so a dropped, misaligned or wrong-offset field changes the NUMBER, not just an address -- a struct whose fields all hold the same value discriminates nothing
- [ ] #5 A member forcing padding (char then int) and a union overlap are both in the corpus, so a layout ignoring alignment returns a different number
- [ ] #6 sizeof(struct) is checked against the EXECUTED value, not only against the IR diff
- [ ] #7 simp.nix's absent zerofield is addressed explicitly -- implemented or made to throw -- since this slice un-gates it
<!-- AC:END -->
