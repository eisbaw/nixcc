# nix-tcc

A C compiler for RISC-V, written in the Nix expression language.

The goal is that `nix eval` alone can compile and run a C program — no gcc, no
assembler, no linker, no emulator binary. C source in, program output out,
inside a single evaluation.

Status: **early.** Three pieces work and are verified: an RV32I instruction
encoder, a C89 lexer, and an lburg-style instruction selector that turns lcc's
own DAG output into RV32 assembly. The parser and the DAG builder that would
join the last two do not exist yet. See `backlog/` for what is done.

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
- **Recursion depth is capped** by the `max-call-depth` setting, default 10000,
  and real work costs two or three depth units per level. It can be raised, but
  only with a flag *and* a much larger `ulimit -s` — and we cannot demand either
  of someone who just runs `nix eval`, which is the whole point. So no traversal
  may have depth proportional to input length. Loops live in the C++ evaluator:
  `builtins.foldl'` to reduce, `builtins.genericClosure` to iterate when each
  step must also emit a value.
- **Appending to a list is quadratic.** There is no O(1) cons and `++` copies:
  `acc ++ [x]` costs 30s at n=200000 where `concatLists` of per-step singletons
  costs 0.08s. This is the single finding most likely to sink a naive port.
- **`builtins.substring` copies its haystack**, so slicing one lexeme per token
  out of a source string is quadratic in file size — 22.7s against 2.1s on a
  2.2 MB file. Text is sliced out of an exploded character list instead.

## Verification

Nothing here is trusted because it looks right. Two oracles are pinned in the
flake so the checks are reproducible:

- **`rcc -target=symbolic`** — lcc's own frontend, which dumps numbered DAG
  nodes. This gives a node-by-node diff target for our frontend before any
  backend exists. Built at `-O0`, because lcc's arena allocator hands back
  under-aligned memory and `rcc` crashes on every input from `-O1` upwards;
  `-fno-strict-aliasing` does not help, which was measured rather than assumed.
- **`riscv32-none-elf-as`** — for the instruction encoder.

The instruction selector gets a third: its output is assembled, linked and
**executed** in [nix-riscv](https://github.com/eisbaw/nix-riscv), an RV32I
emulator that is itself pure Nix, while the host compiler builds the same C file
and runs it. The two answers have to agree with each other and with a number
written down in the test table, so two compilers agreeing on a wrong answer is
still a failure. Its DAGs are regenerated from their `.c` with lcc on every run
and diffed, so "these are real lcc DAGs, not ones invented to suit the rules"
is a property the suite re-proves rather than a claim in a comment.

The lexer has no external oracle, so it is pinned down three ways instead: a
table of hand-written token sequences, a byte-for-byte round-trip over all 34
lcc sources, and a must-fail suite with control cases.

All three are mutation-tested: deliberately corrupting the code under test must
make them fail, and deliberately breaking the *harness* must make them fail too,
with a different message. An earlier version reported `PASS` while comparing
nothing.

## Usage

    nix develop          # or: just shell

    just e2e             # build oracles, run every PoC
    just poc-encoder     # differential-test the RV32I encoder against GNU as
    just poc-lexer       # token tables, round-trip, throughput, mutation test
    just poc-matcher     # rule table, labelling, cost duels, emitted code run
    just ir foo.c        # dump lcc's reference IR for a C file
    just lint            # statix, deadnix, shellcheck
    just sources         # print the pinned lcc / tinycc / nix-riscv paths

`nix flake check` runs everything that is a pure evaluation: the encoder
differential test, the lexer's token and round-trip checks, and the matcher's
rule, labelling and emitted-code checks. Anything that times, executes or
mutates a subprocess — the throughput ladders, the emulator runs, the mutation
tests — lives in `just poc`.

## Layout

    poc/01-encoder/   RV32I instruction encoder in pure Nix, + its oracles
    poc/02-lexer/     C89 lexer in pure Nix, + its tables and throughput ladder
    poc/03-matcher/   lburg-style instruction selector, + real lcc DAGs to run it on
    poc/lib/          what the timing ladders share: the contention guard
    backlog/          tasks (managed with the backlog CLI, not edited by hand)
    flake.nix         dev shell, the rcc oracle, and the checks output

## License

The Nix code here is ours. Note that **lcc's license is non-OSI** and has
redistribution restrictions; this matters before publishing anything derived
from its source. tcc is LGPL.
