---
id: decision-006
title: Defer float support to a later wave
date: '2026-09-14 20:04'
status: accepted
---
## Context

Float is the part of a C frontend most likely to be wrong, and it is the part
our oracle cannot check: `symbolic.c`'s `defconst` prints floats with `%g` --
six significant digits -- and pointer constants with `%p`, i.e. host addresses.
See decision-004.

RV32I also has no F or D extension, so floats would need a softfloat runtime
layered on top of the soft mul/div work that RV32I already forces
(decision-003).

## Decision

Defer float support to a later wave. The compiler is integer-only for now, and
the frontend must REJECT float declarations with a clear diagnostic rather than
silently miscompiling them.

## Consequences

Every remaining path keeps an oracle behind it, so the verified-everything
property stays intact. That property is worth more at this stage than language
coverage.

The explicit rejection matters: a frontend that quietly accepts `double` and
emits wrong code is worse than one that refuses it, and this is exactly the
surface where that would go unnoticed.

Revisit once the integer compiler works end to end. If float comes into scope
later it will need a different verification strategy -- differential execution
against the emulator rather than IR diffing -- because the lcc oracle cannot
serve.
