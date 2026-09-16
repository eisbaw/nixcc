---
id: TASK-058
title: 'Slice 4a: struct, union and enum through pointers and locals'
status: In Progress
assignee: []
created_date: '2026-09-16 08:21'
updated_date: '2026-09-16 12:35'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
STEP 0. decision-009 is recorded but was never applied. flake.nix's rcc-rv32 wrapper gains -wants_argb=0 beside -little_endian=1, and the gate is green on it BEFORE any parser code is written. That is what keeps task-019 (frame layout) off this slice's critical path: with it, lcc lowers a by-value struct in the FRONTEND to `pointer to struct P flags=structarg', which passes poc/03-matcher/emit.nix's fourByte guard through its `pointer to .*' arm.

1. TYPE IDENTITY, settled before a single field is built on it.

THE PROBLEM. lcc's newstruct mints a fresh Symbol per declaration and the Type points at it; type identity IS that pointer. poc/07-parser/types.nix replaced pointer identity with Nix STRUCTURAL equality, using `name' to keep `int' and `long int' apart. Under structural equality two DIFFERENT anonymous structs with the same field list would compare equal, and so would the same tag redeclared in an inner scope. No oracle diff can see either, because lcc prints the TAG NAME and the two listings would agree.

THE RESOLUTION: reproduce lcc rather than approximate it. newstruct installs a symbol into a new TAG NAMESPACE, and the aggregate type carries `sym = <that symbol's id>'. Symbol ids come from a counter, so they are unique by construction, and Nix structural equality over { op; name; sym; size; align; } is then pointer equality by another name. The type uid is NOT invented separately -- it IS the tag symbol, which is what lcc's is.

eqtype therefore needs NO new STRUCT arm. Its first line `ty1 == ty2' and its final `false' already give lcc's answer once `sym' is in the type -- lcc's own eqtype has no STRUCT arm either, for exactly this reason. Adding one would be a second place for the relation to be wrong.

THE TRAP THIS CREATES, and how it is closed. lcc fills in size, align and the field list by mutating THROUGH the pointer after the type value has been handed out, so `struct P { struct P *next; }' and a forward-declared `struct P;' both hand out a type that is completed later. A Nix copy taken before completion stays incomplete for ever, and `sizeof(*p->next)' would quietly be 0. Threading state into types.nix so sizes resolve on demand is a refactor of the whole frontend for a case cut-1 does not need. Instead every USE of an INCOMPLETE aggregate is refused, loudly, naming its own task -- which makes a stale copy unreachable rather than merely unlikely.

The field list, and lcc's cfields/vfields bits, live in STATE keyed by the tag symbol id -- as lcc keeps them on the symbol -- and never inline in the type, so two copies of one type cannot disagree about their fields.

2. WHAT LANDS. Tag namespace in sym.nix: a parallel table per scope frame, threaded through install/lookup/lookupIn/enterscope/exitscope, plus the globals-level table. decl.c's structdcl, enumdcl and fields in parse.nix, with layout and padding per decl.c's fields() and symbolicIR's structmetric (size 0, align 4 -- so EVERY struct is 4-aligned here, which is the oracle's rule and not RV32's). expr.c's field() behind `.' and `->'. types.nix gains the outtype arms (`struct P', `union U', `enum E') and newstruct/newfield/fieldref. trees.nix's assignType gains enode.c's `isstruct(xty) && xty == yty' arm. dag.nix gains INDIR's vfields arm and keeps INDIRB/ASGNB at the UNSIZED tree op, which is how lcc prints them. By-value struct parameters -- decision-009's whole point -- via idtree's PARAM arm, call()'s temporary-plus-ASGNB, and funcdefn's retyping of caller and callee to `pointer to ... flags=structarg'.

3. ZEROFIELD. simp.nix records it ABSENT rather than throwing, on the grounds that parse refuses `struct' first. This slice lifts that gate, so the refusal moves to simp.nix itself: simplify's EQ and NE arms THROW on a FIELD tree, naming task-059. Bit fields are ALSO refused at the field declaration. Both, not one: the declaration refusal is the reachable one, and the simp throw is what stops a later slice un-gating zerofield by accident again.

4. REFUSED, each naming a task id: bit fields (task-059); a struct or union initialiser `= { ... }' (task-029); a function returning a struct by value, which needs decl.c's retv and a CALLB no rule table has (new task); an incomplete aggregate reaching a declarator (new task). ASGNB and INDIRB are EMITTED and diffed against lcc but have no backend rule, so they stay out of run/ and are recorded the way CALLP4 already is -- cases.nix's opcode list is a claim about the frontend, not about what the backend can lower (task-060).

5. TESTS. c/structs.c, c/unions.c, c/enums.c for the listing diff, carrying `type=struct P', `type=array 2 of struct P', `type=pointer to union U' and `flags=structarg'. run/records.c for the EXECUTED answer: fields weighted 1/2/4/8 so a dropped, misaligned or wrong-offset field changes the NUMBER and not just an address; a `char' before an `int' forcing padding; a union overlap; and sizeof(struct) checked against the executed value, not only against the IR diff. Its expectation is COMPUTED a second time in cases.nix from the layout rules rather than read off a run. must-fail pairs for every refusal, and two for identity itself: two distinct anonymous structs with identical field lists are not assignment-compatible, and a tag redeclared in an inner scope is a different type -- each with a control that must still compile. Mutations: drop `sym' from the aggregate type (both identity cases must fire), drop the alignment round-up, drop the union's off/bits reset, drop structarg, drop the vfields arm, drop the field offset. Counts declared and checked for EQUALITY.

6. Full `nix develop --command just e2e' before every commit; one commit per logical unit.
<!-- SECTION:PLAN:END -->
