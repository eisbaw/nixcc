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
- **`builtins.substring` copies its haystack.** Its cost is proportional to the
  length of the string being sliced, not to the slice. 20000 four-byte slices
  cost 0.11/0.15/0.30/0.84 s as the source grows 278 kB/556 kB/1.1 MB/2.2 MB.
  So one slice per token is quadratic in file size: cutting a 2.2 MB file into
  four-character pieces takes 22.68 s with `substring` against 2.13 s with
  `concatStringsSep` over a list of characters. At 278 kB the two are 0.41 s and
  0.31 s -- the trap is invisible at PoC scale and fatal at real scale.
- **`builtins.split "(.)"` is the way to explode a string.** One evaluator call
  for the whole string: 0.13 s on 278 kB against 1.40 s for
  `genList (i: substring i 1 s)`, which pays the copy above on every character.
- **`builtins.genericClosure` is the only loop that can emit.** `foldl'` carries
  a scalar accumulator and cannot produce one output per step; `++` accumulation
  is quadratic; a self-referential `genList` has depth n. genericClosure is an
  iterative worklist in the evaluator, and is linear at constant stack depth:
  0.07/0.11/0.18/0.35/0.49 s at n=25000/50000/100000/200000/400000.
  **It forces only `key`.** Every other field of an item stays a thunk, and the
  chain is as deep as the loop: forcing such a field at n=100000 is not slow, it
  is "error: stack overflow (possible infinite recursion)". `deepSeq` the item
  inside the operator.

## Decision

Shifts are multiply/divide against a precomputed power-of-two table. Compiler
output is a byte list rather than an ELF string. The target is RV32 (see
decision-003). No traversal may have depth proportional to input length, so long
traversals are folds -- but recursive descent whose depth tracks expression
nesting (well under 100 for real C) is fine. **No fold may accumulate a list
with `++`**: build per-step lists and `concatLists` once, or drive by index with
`genList`/`map`. A sequential pass that must emit one value per step -- a lexer,
a peephole pass, an assembler -- is a `genericClosure` whose operator `deepSeq`s
the item it returns. Text is sliced out of an exploded character list, never out
of a large string.

## Consequences

The recursion limit is a *setting*, not a hard wall -- but it is one we cannot
demand of someone who just runs `nix eval`, which is the whole point of the
project. That is the argument to use, not "recursion overflows the stack".

The accumulator finding is the one that could silently sink the project: a lexer
written the obvious way would be quadratic and would produce a throughput number
that reads as "Nix is too slow for this", when the real answer is one line of
accumulator shape.

`substring` is the same trap wearing a different hat, and a nastier one: the
accumulator problem shows up as soon as you measure, while the `substring`
problem is 1.3x at 278 kB and 11x at 2.2 MB. Any Nix pass that slices text must
be benchmarked at a size where the quadratic term can be seen, or it is not
benchmarked at all.

With the three shapes above -- genericClosure to drive, concatLists to gather,
character lists to slice -- the lexer measures 47000 tokens/s and stays linear
from 31 kB to 431 kB (task-002). Raw throughput is not what threatens this
project. What does is the constant: 31 kB of C costs 85 MB of peak RSS, 431 kB
costs 507 MB and 2.2 MB costs 976 MB, and that last one takes 18.3 s where the
small-file rate predicts 14.5. The evaluator's own overhead per live value is
the budget to watch in every later stage, not asymptotics.
