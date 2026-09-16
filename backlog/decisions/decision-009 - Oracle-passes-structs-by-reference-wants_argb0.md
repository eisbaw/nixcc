---
id: decision-009
title: 'Oracle passes structs by reference: wants_argb=0'
date: '2026-09-16 08:20'
status: accepted
---
## Context

Compound types are the next language surface, and a struct passed BY VALUE is a
different problem from a struct reached through a pointer. lcc's `Interface`
record decides which the frontend hands to the backend, via `wants_argb`.

`symbolicIR` ships `wants_argb = 1`. With that, a by-value struct parameter stays
a struct and produces `ARGB`, plus a PARAM symbol with `flags=computed`.
`poc/03-matcher/emit.nix`'s `frameOf` throws on it -- its `fourByte` guard
accepts `pointer to .*` and a short list of 4-byte scalars and nothing else --
which would make task-019 (frame layout for types the selector does not handle)
a hard prerequisite of every struct slice.

`null.c` and `bytecode.c`, the real backends in lcc's own tree, both ship
`wants_argb = 0`. Unlike `-mulops_calls=` (decision-004), the `-wants_argb=`
override is not broken: its `strncmp` length is correct.

## Decision

The `rcc-rv32` wrapper gains `-wants_argb=0` alongside `-little_endian=1`.

With it, lcc lowers by-value structs in the FRONTEND: the parameter becomes
`type=pointer to struct P flags=structarg`, which passes `fourByte`'s
`pointer to .*` arm unchanged, and the call site becomes a temporary plus
`ASGNB` plus an ordinary `ARGP4`. `ARGB` disappears from the IR entirely.

Measured before deciding, not assumed. Across all 62 `.c` files under `poc/`,
`wants_argb=0` and `wants_argb=1` produce BYTE-IDENTICAL output -- the flag only
bites where a struct is passed by value, and nothing in the corpus does that yet.
Verified independently by the orchestrator: 62 identical, 0 differing.

## Consequences

task-019 is NOT on the critical path for compound types. That is the point of
taking this decision before the slice rather than during it.

The divergence worth writing down: this makes the compiler pass **every** struct
by reference, which is **not** the standard RV32 ABI -- that passes structs of
at most two XLEN words in `a0`/`a1`. It is safe today because the compiler is
whole-program, emits no relocations and links nothing external (task-022). It
stops being safe the moment we interoperate with code compiled by anything else,
and that is the kind of divergence that bites later rather than now.

This is not a patch in decision-004's sense. `-little_endian=1` corrects an
oracle that describes the wrong machine; `-wants_argb=0` selects between two
lowerings lcc supports deliberately, and picks the one every real lcc backend
picks.
