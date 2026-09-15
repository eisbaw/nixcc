---
id: TASK-037
title: builtins.tryEval cannot catch an attribute-missing error
status: To Do
assignee: []
created_date: '2026-09-15 09:43'
labels:
  - harness
  - verification
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by task-024/025 review and verified independently: builtins.tryEval catches throw and assert, returning success = false, but an "attribute missing" error propagates straight through it.

  { throwCaught = false; assertCaught = false; missingAttr = <error: attribute 'nope' missing>; }

Consequence: that failure class escapes every must-fail suite in this repository. A reject case that hits a missing attribute crashes the suite instead of being counted, and a control case that hits one takes the whole evaluation down rather than being reported as a failed control.

It fails loudly rather than silently, so this is a robustness gap and not a false-pass -- which is why it is filed rather than treated as a gate-breaker. But every must-fail suite in the tree currently has a blind spot, and the suites are this project's main defence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A shared helper wraps the tryEval pattern so a missing attribute is reported as a failed case rather than crashing the suite
- [ ] #2 Every must-fail suite in poc/ uses it: 01-encoder, 02-lexer, 03-matcher, 04-assembler, 05-loop
- [ ] #3 A mutation proves the helper bites: introduce a typo'd attribute access in a reject case and show the suite reports it rather than dying
<!-- AC:END -->
