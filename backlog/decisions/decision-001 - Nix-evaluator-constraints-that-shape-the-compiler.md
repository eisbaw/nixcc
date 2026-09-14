---
id: decision-001
title: Nix evaluator constraints that shape the compiler
date: '2026-09-14 18:44'
status: accepted
---
## Context

Every constraint below was measured on this machine with Nix 2.31.2, not taken
from documentation. They are recorded here because they are the reason the
compiler is shaped the way it is, and because the PoC tasks that discovered
them will be archived once closed.

- **No shift operators.** `bitAnd`, `bitOr`, `bitXor` exist; there is no shift
  and no `bitNot`.
- **Strings cannot hold a NUL byte.** `builtins.fromJSON` of a string with an
  escaped NUL errors: "cannot be represented as Nix string because it contains
  null bytes".
- **Integers are 64-bit signed and overflow throws.** `9223372036854775807 + 1`
  raises "integer overflow" rather than wrapping.
- **Division truncates toward zero.** `(0-7) / 2 == -3`, matching C.
- **Recursion depth is capped by the `max-call-depth` setting, default 10000.**
  A recursion that only nests reaches 9990 and fails at 10100. A function doing
  real work per level consumes 2-3 depth units per iteration and so fails
  earlier. The cap can be raised, but only by passing `--option max-call-depth`
  AND raising `ulimit -s` far beyond its default: with a 16 MB stack n=50000
  dies; with a 1 GB stack n=200000 succeeds and n=1000000 still dies.
- **Accumulator shape dominates performance, not fold-vs-recursion.** Nix lists
  have no O(1) cons, and `++` copies. Measured at n=25000/50000/100000/200000:
  `acc ++ [x]` takes 0.54/1.71/7.01/30.44 s, `[x] ++ acc` takes
  0.74/1.72/6.72/30.15 s -- both quadratic. `concatLists` of per-step singletons
  takes 0.04/0.05/0.05/0.08 s and `map` over `genList` 0.04/0.04/0.04/0.05 s --
  both linear. A 380x gap at n=200000.

## Decision

Shifts are multiply/divide against a precomputed power-of-two table. Compiler
output is a byte list rather than an ELF string. The target is RV32 (see
decision-003). No traversal may have depth proportional to input length, so long
traversals are folds -- but recursive descent whose depth tracks expression
nesting (well under 100 for real C) is fine. **No fold may accumulate a list
with `++`**: build per-step lists and `concatLists` once, or drive by index with
`genList`/`map`.

## Consequences

The recursion limit is a *setting*, not a hard wall -- but it is one we cannot
demand of someone who just runs `nix eval`, which is the whole point of the
project. That is the argument to use, not "recursion overflows the stack".

The accumulator finding is the one that could silently sink the project: a lexer
written the obvious way would be quadratic and would produce a throughput number
that reads as "Nix is too slow for this", when the real answer is one line of
accumulator shape.
