---
id: TASK-068
title: A function that returns a struct or union by value
status: To Do
assignee: []
created_date: '2026-09-16 12:57'
labels:
  - frontend
  - compound-types
  - backend
dependencies:
  - TASK-058
  - TASK-060
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-058 passes structs by value (decision-009 and wants_argb=0) and REFUSES returning one. The two are not symmetric and that is why.

symbolicIR ships wants_callb = 0, so decl.c's funcdefn allocates a hidden first parameter -- `retv = genident(AUTO, ptr(unqual(rty)), PARAM)' -- prepends it to both the caller and the callee vectors, and stmt.c's retcode assigns THROUGH it. enode.c's call() allocates a temporary for the result and calltree() builds `RIGHT(CALL+B(f, addrof(t3)), idtree(t3))'. enode.c's asgntree has a third path on top of that, for `x = f()' where f returns a struct: it rewrites the call to write straight into x.

That is a whole extra parameter convention, and CALL+B has no row in poc/03-matcher/rules.nix -- nor could it use one until task-060 gives the backend a block copy. task-057 records the same shape for CALLP4: the frontend can emit what the backend cannot lower, and the honest answer is to refuse at the frontend until both ends exist.

Both refusals are in poc/07-parser/parse.nix -- one in funcdefn for the definition, one in call() for the call -- and both name this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 struct P f(void) { ... } compiles, and the hidden return parameter appears in the listing exactly where rcc-rv32 puts it
- [ ] #2 x = f() where f returns a struct writes into x directly, as enode.c's asgntree does, rather than through a temporary
- [ ] #3 A program that returns a struct by value RUNS on the emulator, which needs task-060's block copy first
<!-- AC:END -->
