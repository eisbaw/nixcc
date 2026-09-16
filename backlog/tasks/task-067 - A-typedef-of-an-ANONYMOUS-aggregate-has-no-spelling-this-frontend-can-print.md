---
id: TASK-067
title: A typedef of an ANONYMOUS aggregate has no spelling this frontend can print
status: To Do
assignee: []
created_date: '2026-09-16 12:56'
labels:
  - frontend
  - compound-types
dependencies:
  - TASK-058
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`typedef struct { int a; } T;' is refused by task-058. `typedef struct P { int a; } T;' -- the same declaration with a tag -- is accepted, and the difference is entirely about what symbolic.c PRINTS.

types.c's outtype() names an aggregate from its tag symbol. When the tag is one lcc generated -- its name starts with a digit, which is how an anonymous aggregate is spelled -- it first calls sym.c's findtype(), which searches the identifiers table for a TYPEDEF whose type is that same Type, and prints the typedef's name if it finds one. Measured: `typedef struct { int a; } T; int f(T *t){...}' prints `pointer to T', and the same file without the typedef prints `pointer to struct defined at 1'.

So the spelling of an anonymous aggregate depends on the symbol table at PRINT time, and on a search whose result changes as declarations are added. poc/07-parser/types.nix's outtype is a pure function of the type, which is what lets every layer import types.nix without the state; the anonymous tag's whole rendered spelling is settled once, in parse.nix's `aggName', when the tag symbol is minted.

Refusing the anonymous typedef is what makes findtype's non-null path unreachable, so that settling it early is sound. The work here is to decide whether outtype gains the state or whether the rendered name is revised when a typedef claims it -- and the second is a cache, with a cache's failure mode.

The refusal is in poc/07-parser/parse.nix's `installTypedef' and names this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 typedef struct { int a; } T; parses, and a listing that mentions T prints `T' where lcc prints `T'
- [ ] #2 An anonymous aggregate with NO typedef still prints `struct defined at LINE', and a case holds both spellings against rcc-rv32
<!-- AC:END -->
