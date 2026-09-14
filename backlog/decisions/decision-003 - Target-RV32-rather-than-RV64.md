---
id: decision-003
title: Target RV32 rather than RV64
date: '2026-09-14 18:44'
status: accepted
---
## Context

Nix integers are 64-bit signed, which at first suggests RV64 maps onto them
one-to-one and is therefore the easier target.

## Decision

Target RV32. Nix integer overflow **throws** rather than wrapping
(decision-001), so an RV64 `add` of two large values would crash the evaluator,
forcing hi/lo 32-bit splitting on every arithmetic operation. RV32 values sit
inside 64-bit signed with headroom, so wraparound is a cheap
`bitAnd x 4294967295`.

## Consequences

This also aligns with nix-riscv, which is RV32I and supplies the execution
substrate for free.

The cost: RV32I has no M extension, so every C `*`, `/` and `%` becomes a
libcall to `__mulsi3`/`__divsi3`/`__modsi3`/`__udivsi3`, and a minimal RV32I
runtime library is a project deliverable. 64-bit `long long` needs multi-word
arithmetic.
