---
id: TASK-025
title: A call whose result is discarded has no rule
status: To Do
assignee: []
created_date: '2026-09-15 02:03'
updated_date: '2026-09-15 04:40'
labels:
  - poc
  - matcher
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`wr(1, out, 11);' as a statement -- an int-returning function called for its effect -- does not compile. lcc emits a listed CALLI4 that nothing uses as a kid, so burg.nix reduces it to `stmt' through the chain rule `stmt: reg', which passes dst = null down to a rule whose template says `call %0\nmv %c,a0\n'. The result is:

    error: burg: template `call %0
    mv %c,a0
    ' uses %c outside an instruction

A refusal, not a miscompile, and the diagnostic points at the template rather than at the C -- a reader would have to know burg.nix to see that the problem is a discarded return value.

The fix is one or two rows in poc/03-matcher/rules.nix:

    { nt = "stmt"; op = "CALLI4"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\n"; }
    { nt = "stmt"; op = "CALLI4"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\n"; }

which is exactly the claim the rule table makes about itself -- adding an instruction means adding a row -- so it is also a small test of that claim. CALLP4 and CALLD4 want the same treatment if they can reach a statement position.

Found by TASK-004: poc/05-loop/hello.c checks write()'s return value instead, which is better C but was not a free choice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A C statement that calls an int-returning function and discards the result compiles, assembles and runs
- [ ] #2 The call still clobbers the caller-saved registers: the new rule's template is matched by rules.nix's callMarkers
- [ ] #3 A case in poc/03-matcher's corpus covers it, taken from real lcc output rather than hand-written IR
- [ ] #4 If a discarded result still cannot be compiled in some position, the diagnostic names the C-level cause rather than the template
<!-- AC:END -->
