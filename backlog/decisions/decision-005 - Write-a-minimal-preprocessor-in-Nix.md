---
id: decision-005
title: Write a minimal preprocessor in Nix
date: '2026-09-14 20:04'
status: accepted
---
## Context

`lcc/cpp/` is a separate ~2800-line program. The frontend in `src/` consumes
preprocessed input only: `input.c`'s `resynch()` parses `# n "file"`
linemarkers, and there is no `#include`, `#if` or macro expansion anywhere in
`src/`. Nobody had counted those lines into the port scope, and without them the
project's headline claim -- that Nix alone compiles C with no external toolchain
-- is simply false.

Three options were costed: port lcc/cpp faithfully (~30% increase in total
scope, and macro expansion is exactly the recursive, state-mutating code Nix
handles worst); accept preprocessed C only (fastest, but shrinks the claim);
or write a minimal preprocessor of our own.

## Decision

Write a minimal preprocessor in Nix, and file a follow-up task for what it
deliberately leaves out.

Scope it to what real C programs actually need: `#include` (both forms),
object-like and function-like `#define`, `#undef`, `#if`/`#ifdef`/`#ifndef`/
`#elif`/`#else`/`#endif` with constant-expression evaluation, and `#line`. Skip
lcc/cpp's compatibility baggage.

This keeps the no-external-toolchain claim true, which is the whole point of the
project, without paying for a faithful port of code whose shape suits Nix badly.

## Consequences

The minimal preprocessor is a real deliverable with its own tasks, not a
footnote. The follow-up task records what it does not cover, so the gap is
tracked rather than discovered later by a user whose program fails to compile.

The lexer already handles backslash-newline continuations (a forward-carried
note from task-002 flags a divergence worth checking here). Macro expansion
needs the same loop discipline as everything else: no input-proportional
recursion depth, and no `substring` per token against a whole-file haystack
(decision-001).

It also means preprocessing is on the critical path to compiling any C with
headers -- so the integer-only vertical slice should be provable on
preprocessed input first, with cpp landing alongside rather than blocking it.
