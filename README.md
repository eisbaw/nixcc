# nix-tcc

A C compiler for RISC-V, written in the Nix expression language.

The goal is that `nix eval` alone can compile and run a C program — no gcc, no
assembler, no linker, no emulator binary. C source in, program output out,
inside a single evaluation.

Status: **early.** The instruction encoder works and is verified. The compiler
does not exist yet. See `backlog/` for what is actually done.

## Why lcc and not tcc

The port source is [lcc](https://github.com/drh/lcc) (Fraser & Hanson), not
Bellard's tcc, despite the project name.

tcc is single-pass: it parses and emits machine-code bytes simultaneously into
a mutable buffer, then backpatches jump targets by writing back into code it has
already emitted. That has no good translation into a language without mutation.

lcc goes source → AST → DAG → instruction selection. Its frontend/backend seam
is a closed set of 33 IR operators, and its instruction selector is a
declarative rule table rather than hand-written emission code — an lburg rule is
`base: ADDI4(reg,acon) "%1(%0)"`, which is close to being Nix data already.

tcc still earns its keep as the **test corpus**: 139 cases with `.expect` files,
against lcc's 18.

## What Nix can and cannot do

Every constraint below was measured, not assumed, and each one shaped the design:

- **No shift operators.** `bitAnd`/`bitOr`/`bitXor` exist; shifts do not. Every
  shift is a multiply or divide against a precomputed power-of-two table.
- **Strings cannot contain NUL**, so an ELF can never be a Nix string. Output is
  a byte list fed directly to an in-Nix RISC-V emulator, which is also what lets
  the whole pipeline stay inside one `nix eval`.
- **Integers are 64-bit signed and overflow throws** rather than wrapping. This
  is why the target is RV32 and not RV64: 32-bit values have headroom, whereas
  RV64 would need hi/lo splitting on every arithmetic operation.
- **Deep recursion is fatal.** Explicit tail recursion overflows the evaluator
  stack by n=5000 and cannot be raised far enough to help. `builtins.foldl'`
  runs 1e6 iterations in 0.6s because its loop lives in the C++ evaluator, so
  every traversal in the compiler must be a fold.

## Verification

Nothing here is trusted because it looks right. Two oracles are pinned in the
flake so the checks are reproducible:

- **`rcc -target=symbolic`** — lcc's own frontend, which dumps numbered DAG
  nodes. This gives a node-by-node diff target for our frontend before any
  backend exists. Built at `-O0 -fno-strict-aliasing`, because lcc 4.2 predates
  strict aliasing and `rcc` segfaults at `-O1` under modern gcc.
- **`riscv32-none-elf-as`** — for the instruction encoder.

The encoder test is also mutation-tested: deliberately corrupting the encoder
must make it fail, and deliberately breaking the *harness* must make it fail
too. An earlier version reported `PASS` while comparing nothing.

## Usage

    nix develop          # or: just shell

    just e2e             # build oracles, run every PoC
    just poc-encoder     # differential-test the RV32I encoder against GNU as
    just ir foo.c        # dump lcc's reference IR for a C file
    just lint            # statix, deadnix, shellcheck
    just sources         # print the pinned lcc / tinycc / nix-riscv paths

`nix flake check` runs the encoder differential test in a sandbox.

## Layout

    poc/01-encoder/   RV32I instruction encoder in pure Nix, + its oracles
    backlog/          tasks (managed with the backlog CLI, not edited by hand)
    flake.nix         dev shell, the rcc oracle, and the checks output

## License

The Nix code here is ours. Note that **lcc's license is non-OSI** and has
redistribution restrictions; this matters before publishing anything derived
from its source. tcc is LGPL.
