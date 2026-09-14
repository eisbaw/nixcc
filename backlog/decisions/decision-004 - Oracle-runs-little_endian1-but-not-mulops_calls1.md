---
id: decision-004
title: Oracle runs little_endian=1 but not mulops_calls=1
date: '2026-09-14 18:44'
status: accepted
---
## Context

The frontend is verified by diffing our DAG output against lcc's own
`rcc -target=symbolic`, which prints numbered nodes with `#n` back-references.
But `symbolicIR` declares `little_endian = 0` and `mulops_calls = 0` -- a
big-endian machine with a hardware multiplier. RV32 is neither.

`main.c` also has an upstream bug: every IR override flag compares against its
literal's length except `-mulops_calls=`, which compares 18 bytes against a
14-character string and so can never match. It is a silent no-op.

## Decision

Fix the `strncmp` bug in the derivation so the flag is not a trap for later
work, but run the oracle with `-little_endian=1` only, through an `rcc-rv32`
wrapper.

`little_endian` matters and works: for `unsigned b:5` in a bitfield struct the
shift constant is 24 at 0 and 3 at 1. Diffing against the raw oracle would have
silently compared us against a different target.

`mulops_calls=1` is a dead end for this oracle. With the flag actually live,
`dag.c` does not rewrite MUL/DIV/MOD into CALL nodes -- it leaves the op alone
and promotes it to a forest *root* via `list(p)`. Neither `symbolic.c`'s
valid-forest switch nor `dagcheck.md` (whose only stmt roots are INDIR*, CALL*
and V) knows about that, so it asserts. Making it work needs patching both and
regenerating lburg output.

## Consequences

Patching an oracle until it agrees with you defeats the purpose of having one.
Each additional patch makes `rcc-rv32` less like real lcc.

So the mul/div/mod libcall promotion is a **known, precisely characterized
divergence**: with `mulops_calls=1` the MULI4/DIVI4/MODI4 node becomes a forest
root, and everything else is identical. Our frontend implements the promotion
and tests it on its own; oracle diffing runs with promotion off. This is filed
as a task so it cannot be forgotten.

The oracle has two further limits worth knowing: `defconst` prints floats with
`%g` (six significant digits) and pointer constants with `%p` (host addresses),
so float support -- the part of a frontend most likely to be wrong -- is not
testable against it.
