---
id: TASK-046
title: Give the constant evaluator a byte-to-code table beyond ASCII
status: To Do
assignee: []
created_date: '2026-09-15 18:04'
labels:
  - frontend
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/06-constants/const.nix builds its character-code table from builtins.fromJSON of \u00NN escapes, which yields exactly one byte only below U+0080. So a character or string literal containing a byte in 128..255 -- a UTF-8 string in C source, most obviously -- throws instead of evaluating.

The same trick cannot be extended: fromJSON of a non-ASCII code point yields the UTF-8 ENCODING, so the byte 0xe9 is reachable only as the pair 0xc3 0xa9, and the bytes that never appear in valid UTF-8 (0xc0, 0xc1, 0xf5..0xff) are not reachable at all. A checked-in 255-byte data file read with builtins.readFile would give the full table in one line, at the cost of a binary blob in the tree; that is the obvious fix and it is a decision rather than an oversight, which is why it is a task.

Nothing is unreachable today: \\xNN and \\NNN escapes name every byte value, and lcc's own sources are pure ASCII. The refusal is loud and names this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A literal containing any byte in 1..255 evaluates to the same units lcc's rcc produces for it
- [ ] #2 The table's construction is proved by a case that would fail if a byte were mapped to the wrong code
- [ ] #3 The must-fail case that currently expects a refusal is either removed or repointed at something that is still refused
<!-- AC:END -->
