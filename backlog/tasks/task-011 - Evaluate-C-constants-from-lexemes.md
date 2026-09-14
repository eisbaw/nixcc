---
id: TASK-011
title: Evaluate C constants from lexemes
status: To Do
assignee: []
created_date: '2026-09-14 19:21'
labels:
  - frontend
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The lexer (poc/02-lexer) classifies ICON/FCON/SCON and keeps the lexeme, but computes no VALUE. lcc does this inside gettok, in icon(), fcon(), scon() and backslash(): it decodes escape sequences, picks the type from the suffix and the magnitude, and diagnoses overflow. Someone has to do it before there is anything to constant-fold or to emit.

Two Nix-specific traps make this more than transcription:

1. Integer overflow THROWS in Nix rather than wrapping (decision-001), which is exactly the case lcc detects by letting it happen and looking at the result. Detection has to be done by comparison BEFORE the multiply, not after.

2. Nix strings cannot hold a NUL byte (decision-001), so a decoded string literal cannot be represented as a Nix string at all once it contains a \\0 escape. String constants have to become byte lists, which is the same representation the emitter needs anyway.

Also open: lcc accepts multi-character constants like 'ab' with a warning and uses the first character; our lexer accepts them and says nothing yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Integer constants are evaluated for decimal, octal and hexadecimal forms with u/U/l/L suffixes, and the type is chosen as C89 chooses it
- [ ] #2 Overflow is detected and reported, not thrown by the evaluator and not silently wrapped
- [ ] #3 Character constants are evaluated including simple, octal and hex escapes
- [ ] #4 String constants are decoded to byte lists, so an embedded NUL is representable
- [ ] #5 Floating constants are evaluated, or the task is split and float is deferred to task-009
- [ ] #6 Behaviour is diffed against lcc's rcc for every constant form, not just asserted
<!-- AC:END -->
