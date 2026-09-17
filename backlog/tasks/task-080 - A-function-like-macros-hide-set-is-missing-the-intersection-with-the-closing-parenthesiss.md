---
id: TASK-080
title: >-
  A function-like macro's hide set is missing the intersection with the closing
  parenthesis's
status: To Do
assignee: []
created_date: '2026-09-17 09:12'
updated_date: '2026-09-17 10:35'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by cross-model review of task-013.02, and measured against gcc rather than reasoned about.

C89 6.8.3.4 gives the replacement list of a FUNCTION-LIKE macro the hide set

    (HS(macro name) INTERSECT HS(closing parenthesis)) UNION {macro name}

and poc/08-cpp computes only `HS(macro name) UNION {macro name}'. The intersection is not decoration: it is the one mechanism by which a name STOPS being hidden when an invocation reaches out of the frame it was born in and into the source, and dropping it makes this preprocessor hide more than the standard does.

MEASURED. With

    #define f(a) a*g
    #define g(a) f(a)
    int z = f(2)(9);

gcc -std=c89 -E -P gives `int z = 2*9*g;' and poc/08-cpp gives `int z = 2*f(9);'. `g' came out of f's replacement list so it carries the paint {f}; its own closing parenthesis came from the SOURCE with an empty hide set, so the standard un-hides f and expands one more level. We stop early.

WHICH DIRECTION THIS IS. Under-expansion, not a wrong value: a name is left standing and the frontend then refuses it as an undeclared identifier, so it is loud rather than silent. That is why it is filed rather than fixed inside task-013.02 -- the fix changes what `gather' returns, and shipping it beside a rewrite of the whole expander is how the previous two adjacency miscompiles got in.

PINNED, NOT IGNORED. poc/08-cpp/cases.nix carries this exact source with OUR answer and a comment naming this task, so the divergence is visible in the table and has to CHANGE when this lands rather than quietly starting to fail. The gcc differential corpus deliberately does NOT carry it, because that corpus is meant to be green.

WHAT THE FIX LOOKS LIKE. `gather' discards the closing parenthesis: its `)' branch emits `out = [ ]' and keeps only the cursor. It would have to return that token's hide set alongside `st' and `args', and `advance' would then compute `h' as the intersection rather than the union. poc/08-cpp/cpp/bluepaint.c is where the corpus case belongs, and its header currently claims to test over-hiding while carrying no case that does -- fix that with it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The replacement of a function-like macro carries (HS(name) intersect HS(rparen)) union {name}, as C89 6.8.3.4 says
- [ ] #2 f(2)(9) with '#define f(a) a*g' and '#define g(a) f(a)' gives what gcc gives
- [ ] #3 cases.nix's pinned case for the divergence changes with the fix, and poc/08-cpp/cpp/bluepaint.c gains a case that discriminates over-hiding
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CORRECTION, and it matters because the wrong half of it was used to justify FILING this rather than fixing it. The original text said:

  "WHICH DIRECTION THIS IS. Under-expansion, not a wrong value: a name is left standing and the frontend then refuses it as an undeclared identifier, so it is loud rather than silent."

That is false in general. A cross-model review found a sibling defect -- the pasted token's hide set, fixed in task-013.02 -- whose only symptom was a `#if' taking the other arm:

  #define AB 1+A
  #define CAT(a,b) a##b
  #define EXP(a,b) CAT(a,b)
  #if EXP(AB,B) == 2

Over-hiding left `AB' standing, C89 6.8.1 makes a leftover identifier ZERO, and the arithmetic simply came out different. There is no frontend inside a `#if' to refuse anything. So hiding too much is silent wherever the leftover identifier lands somewhere an identifier is legal -- a `#if', or a place where the program happens to declare that name.

This task's own divergence should therefore be treated as potentially silent rather than certainly loud, and the `#if' shape is the one to write the corpus case against when it is fixed.
<!-- SECTION:NOTES:END -->
