---
id: TASK-066
title: An incomplete aggregate cannot be carried into a declarator
status: To Do
assignee: []
created_date: '2026-09-16 12:56'
labels:
  - frontend
  - compound-types
dependencies:
  - TASK-058
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-058 refuses every use of a struct, union or enum whose members have not been seen yet -- a forward-declared `struct P;' followed by `struct P *p;', and the self-referential `struct N { struct N *next; };' that every linked list in C is made of.

THE REASON IS NOT SQUEAMISHNESS, it is the type-identity design task-058 settled. lcc completes an aggregate by MUTATING the Type through the tag symbol's pointer, so every copy already handed out -- the `struct N *' built inside `struct N' -- sees the members appear. A Nix copy cannot. It would keep size 0 for ever: sizeof of it would be 0 rather than wrong-and-loud, and two copies of one type taken either side of the completion would compare UNEQUAL, so `*a = *b' between them would be refused on a program lcc compiles. That is exactly the silent class the refusal exists to avoid, which is why it is a refusal and not a TODO.

Two ways out, and choosing between them is the task:

  * Take size and align OFF the aggregate type and resolve them through the
    tag symbol at every use. Faithful -- it is what lcc's pointer does -- and
    it means threading the state into poc/07-parser/types.nix, which today is
    a pure module every other layer imports. `t.size' is read in about thirty
    places.

  * Keep them on the type and PATCH the stale copies when the aggregate is
    completed, by rebuilding any type that mentions the tag. Cheaper, and it
    is a cache that can go stale, which is the thing this project does not do.

The refusal is poc/07-parser/parse.nix's `requireComplete' and it names this
task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A self-referential struct -- struct N { int v; struct N \*next; } -- parses, and p->next->v diffs byte-for-byte against rcc-rv32
- [ ] #2 sizeof of a completed aggregate is right whether the type value was taken before or after the members were seen; a test holds both
- [ ] #3 A forward-declared tag completed later is ONE type: assigning between a value declared before the definition and one declared after is accepted, as lcc accepts it
<!-- AC:END -->
