---
id: decision-002
title: Port lcc rather than tcc
date: '2026-09-14 18:44'
status: accepted
---
## Context

The project is named for tcc, and tcc is the better-known compiler: it has an
existing RISC-V backend (riscv64), a clean LGPL licence, and a test corpus of
139 cases with expect files. lcc has no RISC-V backend at all, a non-OSI licence
with redistribution restrictions, and 18 test files.

## Decision

Port lcc. The deciding factor is architectural, not aesthetic. tcc is
single-pass: it emits machine-code bytes into a mutable buffer and backpatches
jump targets by writing back into code it has already emitted. That has no good
translation into a language without mutation. lcc goes source -> AST -> DAG ->
instruction selection; its frontend/backend seam is a closed set of 33 IR
operators; its instruction selector is a declarative rule table (lburg) rather
than hand-written emission code.

## Consequences

tcc still earns its keep as the **test corpus** -- the tests2 cases are not
compiler-specific and should be adopted regardless of which compiler we port.

Three caveats, all real:
- lcc is C89 only.
- The licence is non-OSI and must be checked before publishing anything derived
  from its source.
- Three modules are rewrites rather than ports: `gen.c` mutates node fields in
  place and splices spill nodes into a list while walking it; `dag.c` does CSE
  by hashing machine addresses and comparing child pointers, so everything must
  be interned to integer ids first; `simp.c`'s unsigned folding hits Nix's
  throwing overflow.

Two pieces of good news worth keeping: there is no `setjmp`/`longjmp` anywhere
in `src/`, so control flow is not the obstacle -- mutation is. And `string.c`'s
hash-consing exists only so names can be compared by pointer, which deletes
cleanly in Nix (attrset keys are already interned), taking `alloc.c`'s arena
with it.
