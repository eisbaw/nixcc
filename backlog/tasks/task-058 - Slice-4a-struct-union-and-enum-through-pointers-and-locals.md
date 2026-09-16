---
id: TASK-058
title: 'Slice 4a: struct, union and enum through pointers and locals'
status: Done
assignee: []
created_date: '2026-09-16 08:21'
updated_date: '2026-09-16 13:59'
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
- [x] #1 Type identity for aggregates is decided and written down BEFORE fields are built on it: two distinct structs with identical field lists must not compare equal, nor must a tag redeclared in an inner scope
- [x] #2 struct, union and enum parse, reach the DAG, and diff byte-for-byte against rcc-rv32 including the listing spellings (type=struct P, type=array 2 of struct P, type=pointer to union U)
- [x] #3 A C program using a struct through a pointer AND a local struct compiles from .c and runs on the emulator
- [x] #4 The executed answer weights fields 1/2/4/8 so a dropped, misaligned or wrong-offset field changes the NUMBER, not just an address -- a struct whose fields all hold the same value discriminates nothing
- [x] #5 A member forcing padding (char then int) and a union overlap are both in the corpus, so a layout ignoring alignment returns a different number
- [x] #6 sizeof(struct) is checked against the EXECUTED value, not only against the IR diff
- [x] #7 simp.nix's absent zerofield is addressed explicitly -- implemented or made to throw -- since this slice un-gates it
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
WHAT LANDED. struct, union and enum parse, reach the DAG, diff byte for byte
against rcc-rv32, and RUN. 34 translation units and 73 functions diff clean --
2195 numbered node lines, 1867 `#n' back-references and all 16 lines of lcc's
stderr -- and eight C programs compile from .c and run on the emulator, up from
seven. Frontend-only, as the task predicted: ZERO new backend rules were needed
for anything that runs.

TYPE IDENTITY, which was the thing to get wrong quietly.

lcc's newstruct mints a fresh Symbol per declaration and the Type points at it;
identity is that pointer. types.nix had replaced pointer identity with Nix
STRUCTURAL equality, so two anonymous structs with the same members -- and a tag
redeclared in an inner scope -- would have been ONE type.

The resolution is to reproduce lcc rather than approximate it: newstruct
installs a symbol into a new TAG NAMESPACE and the aggregate type carries
`sym', that symbol's id. Ids come from a counter, so structural equality over
{ op; name; sym; size; align; } IS lcc's pointer equality. The uid was not
invented alongside lcc's symbol; it IS lcc's symbol.

eqtype therefore gained NO struct arm, and that is the point rather than an
omission -- lcc's has none either. Its first line is `ty1 == ty2' and its last
is `return 0', and between them an aggregate matches nothing.

WHAT PROVES IT. Three must-fail pairs, because no oracle diff can reach any of
them: lcc REJECTS all three programs, so the differential never runs on them,
and lcc prints the tag NAME, so two distinct anonymous structs look identical
in a listing either way. Measured with the oracle: lcc's own diagnostic for the
first is "operands of = have illegal types `struct defined at 1' and `struct
defined at 1'".

The one that would MISCOMPILE rather than misdiagnose is the third, and it is
the one worth having. A struct-to-struct assignment between two wrong types is
caught twice -- `cast' has no STRUCT arm and refuses it whatever assign() said.
A POINTER assignment has no such second line: one four-byte pointer to another
is a retype and nothing else. So `struct { int a; } x; struct { int b; } *p; p =
&x;' COMPILES under a sym-blind comparison, and every `p->b' after it reads the
wrong layout. That is the mutation "two aggregate types compare without their
tag symbols", and must-fail catches it.

A DEFECT THIS SLICE SHIPPED FOR AN HOUR, recorded because it is the shape of the
next one. `requireComplete' first returned the TYPE, and Nix never forced it:
`dclr' builds `pointer to <t>' without looking at `t', a field's type is never
printed, and nothing downstream forces the thunk. `struct N { struct N *next; }'
compiled, with an unevaluated throw sitting inside the member. It returns the
STATE now, because the next token read forces the state and the condition with
it. A guard whose result nothing consumes is not a guard.

WHAT IS REFUSED, each naming a task:
  * bit fields (task-059)
  * an incomplete aggregate in a declarator, which costs the self-referential
    struct and so the linked list (task-066)
  * a typedef of an ANONYMOUS aggregate, whose spelling lcc looks up in the
    symbol table at print time (task-067)
  * defining or calling a function that RETURNS an aggregate by value, which
    needs decl.c's hidden retv parameter and a CALLB no rule table has
    (task-068)
  * a braced initialiser (task-029, which already owned initialisers)

ZEROFIELD. simp.nix recorded its absence as sound because parse.nix refused
`struct' before a field could be declared -- and this slice lifted exactly that
gate. It THROWS now, naming task-059, in all four of simp.c's EQ/NE cases and at
the position simp.c's macro sits. It is unreachable, because the bit-field
refusal in `fields' comes first, and it has NO mutation for that reason:
corrupting an unreachable guard changes nothing that runs, and a mutation of it
would report "not detected" for the right reason. What IS tested is the
reachable gate -- a must-fail pair with a control and its text in messages.sh.
The point of the throw is that the next slice to lift a refusal cannot un-gate
the rewrite without opening the file it lives in.

DECISION-009, applied in its own commit first. It was recorded and never
applied; the wrapper now passes -wants_argb=0. Measured inert on the corpus as
it stood -- 62 files byte-identical -- and it is what keeps task-019 off this
slice's critical path: a by-value struct parameter becomes `pointer to struct P
flags=structarg' and passes emit.nix's `pointer to .*' arm. c/structs.c's
`byvalue' and `pass' are what exercise it, and two mutations aim at it.

THE ORACLE'S LAYOUT IS NOT RV32's, and this is reproduced rather than corrected.
symbolicIR's structmetric is { size = 0, align = 4 }, so EVERY aggregate here is
four-byte aligned: `struct { char a; char b; }' is four bytes and `union { char
c; }' is four. Correcting it would make every listing differ from lcc's. It joins
decision-009's by-reference argument passing on the list of divergences that
bite the day this links against anything else.

WHAT RUNS AND HOW IT DISCRIMINATES. run/records.c writes four members of a
padded struct and reads the same storage back TWICE: once weighted 1/2/4/8
through the members, and once byte by byte through a union, weighted by
position. The second is the one that catches a WRONG OFFSET, because a member
written and read through the same wrong offset agrees with itself. Measured, the
layout mutations move it: no member alignment prints `8 16 4 113 127' where the
correct answer is `12 16 4 113 190'; a union laid out like a struct prints
`12 28 4 113 0'; every member at offset zero prints `12 16 4 135 9'; and no size
round-up prints `11 16 4 113 190', which is criterion #6 -- sizeof checked
against what EXECUTED. cases.nix lays the struct out a second time in Nix, from
decl.c's rule rather than from the C, and three mutations say that second
implementation is doing the work.

COUNTS. 26 corpus files (from 23) and 64 opcodes (from 58). must-fail 37 (from
25). Mutations 75 (from 57): 18 new, of which three are aimed at type identity,
five at the layout, seven at the rest of the frontend and three at this
harness's own second implementation. One PRE-EXISTING mutation had to be
repaired -- "a volatile load is common-subexpression-eliminated" aimed at a
condition that grew a second clause here, and its sed stopped matching; it now
blinds the scalar half and the struct half has a mutation of its own.

THREE OPCODES ARE EMITTED AND CANNOT BE LOWERED, and cases.nix says so: ASGNB
and INDIRB wait for task-060's block copy, and CNSTI2 for task-069. CNSTI2 is
NOT a compound-type gap -- `short h; h = 9;' has emitted it since task-027 and
nothing in c/ happened to write it until c/unions.c did, which is how task-051
and task-054 each found their missing rules too.

THE GATE, measured, not adjectival:
  nix develop --command just e2e   ->  exit 0
  7 PoCs passed
  34 translation units and 73 functions diffed byte for byte against rcc-rv32:
    2211 numbered node lines, 1879 `#n' back-references, 16 lines of stderr
  26 corpus files, 49 functions, 64 opcodes
  must-fail 37 refusals, each with a control and its own diagnostic
  40 random programs and 803 boundary forms, byte for byte
  8 programs compiled from .c and RUN:
    bits 3 21 15, gcd 21 55, pointers deabcd419d, primes 22 57,
    records 12 16 4 113 190, strings ab-cd10, sumto 55,
    unsigned 1431655683 3 242
  75 mutations, each detected with its own distinct failure
  359 kB peak RSS per source line, unchanged

THREE MUTATION FRAGMENTS HAD TO BE REPAIRED and none of them was new work
going wrong -- all three are the harness noticing that the slice moved what it
was looking at, which is what it is for:
  * "a volatile load is common-subexpression-eliminated" aimed at a condition
    that grew a second clause here; its sed stopped matching. It now blinds the
    scalar half, and the struct half has a mutation of its own.
  * "a conversion node loses its source width" and "one of the running programs
    goes missing" both had their fragments moved by the new corpus files --
    oracle.py prints the first two differing files, and c/enums.c took a
    position ahead of the one that used to supply the fragment.
  * A fourth was a genuine COLLISION rather than a move: the enum mutation's
    obvious fragment, `we  ' 2. CNSTI4 0'', also appears in the generated
    corpus under the shift-overflow mutation. run.sh's distinctness loop
    caught it, on the gate, after the per-mutation check had passed -- a
    fragment being PRESENT in its own output says nothing about whether it is
    absent from the other 74. The replacement is the local's node number,
    because an enumerator that stopped counting renumbers the forest as well as
    changing the constant.
<!-- SECTION:NOTES:END -->
