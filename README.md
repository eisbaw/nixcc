# nixcc

A C compiler for RISC-V, written in the Nix expression language.

The goal is that `nix eval` alone can compile and run a C program — no gcc, no
assembler, no linker, no emulator binary. C source in, program output out,
inside a single evaluation.

Status: **early, but the loop is closed end to end.** `just poc-loop` reads a
`.c` file, compiles it, assembles it and executes it on a pure-Nix RV32I machine
inside a single `nix eval`, in a sandbox that binds nix's own runtime closure,
this project's own sources and nothing else — no assembler, linker or objcopy
exists there to be reached, by name or by absolute path, and the stage checks
that from inside before it runs anything. The sandbox has no network and
cannot reach the nix daemon, so it cannot build its way to a toolchain either.
The program prints

    1..10 = 55

in 714 emulated instructions. The digits are summed and converted to ASCII by
the compiled C, which stores them into a global `char` array a byte at a time;
the message leaves the machine through the `write` syscall and the program
stops through `exit`. What is checked is what it PRINTED, byte for byte — the
program discards `write`'s answer, the way C usually does.

The front half is closed too, for the integer subset. `just poc-parser`
compiles C from `.c` — lexer, parser, DAG builder and IR listing, all in Nix —
and diffs the result against lcc's own frontend byte for byte: node numbers,
`#n` back-references, reference counts, storage classes, frame offsets and
every line lcc prints on stderr. Seven of those programs are then assembled
and executed in the same evaluation, printing `55`, `21 55`, `22 57`,
`3 21 15`, `1431655683 3 242`, `deabcd419d` and `ab-cd10`. `pointers.c`
searches a buffer with a pointer and tests the result against zero -- the
commonest form in C and, until task-054, one that compiled to correct IR and
could not be lowered. `strings.c` copies a string literal with a NUL in the
middle of it, which is the byte a Nix string cannot hold
(`backlog/decisions/decision-001`) and the reason a decoded literal is a byte
list from the lexer to the `.data`.

**`poc/05-loop`'s `hello.c` compiles from `.c` too, as of TASK-028.** It needs
a subscript, a pointer parameter and a `char` array, and that was the last
arrow leaving the evaluator: `just poc-loop` now lexes, parses, selects,
assembles and executes it in one `nix eval` with a `PATH` holding nothing but
`nix`. `hello.sym` is still there and still regenerated from lcc -- as the
ORACLE the listing is diffed against, not as the input.

What compiles from `.c` today is `char`, `short`, `int`, `long` and `unsigned`
locals, parameters and pointers; arrays and subscripting; string literals,
including wide ones; the integer and bitwise operators, assignment,
`if`/`while`/`for`/`do`, calls and `return`. Outside that: file-scope variables
and their initialisers, local statics, `struct`, `union`, `enum`, `switch`,
`goto` and floating point, each refused by name with the task that owns it
rather than guessed at.

## Why lcc and not tcc

The port source is [lcc](https://github.com/drh/lcc) (Fraser & Hanson), not
Bellard's tcc. tcc is here only as a test corpus — the flake pins it for its
`tests2` cases, not for its compiler.

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

The closed loop has no oracle at all beyond the program's own output, so it
carries a second table: ten deliberately malformed programs that must each
halt with their own reported fault — an illegal instruction, a misaligned jump,
a store past the end of RAM, a syscall the machine does not implement, a loop
that never stops — each paired with a control that must still run to a clean
exit with its output pinned. Without that table, "the demo exited 0" is
consistent with an emulator that exits 0 for everything.

All of them are mutation-tested: deliberately corrupting the code under test
must make them fail, and deliberately breaking the *harness* must make them
fail too, with a different message. An earlier version reported `PASS` while
comparing nothing.

## Usage

    nix develop          # or: just shell

    just e2e             # build oracles, run every PoC
    just poc-encoder     # differential-test the RV32I encoder against GNU as
    just poc-lexer       # token tables, round-trip, throughput, mutation test
    just poc-matcher     # rule table, labelling, cost duels, emitted code run
    just poc-assembler   # layout, labels, byte-for-byte diff against GNU as
    just poc-loop        # compile, assemble and RUN a C program in one nix eval
    just poc-constants   # C89 constant lexemes -> values, diffed against lcc
    just poc-parser      # C -> lcc's IR, diffed node for node; seven programs run
    just ir foo.c        # dump lcc's reference IR for a C file
    just lint            # statix, deadnix, shellcheck
    just sources         # print the pinned lcc / tinycc / nix-riscv paths

`nix flake check` runs everything that is a pure evaluation: the encoder
differential test, the lexer's token and round-trip checks, the matcher's
rule, labelling and emitted-code checks, the assembler's layout, label
addresses and `lui`/`addi` expansions, and the closed loop — which compiles,
assembles and executes the demo, and the fault programs beside it, during flake
evaluation, and the parser — which compiles every corpus listing and runs the
seven programs it compiles from `.c`. Anything that times or mutates a
subprocess — the throughput ladders, the differential against GNU as, the
memory measurements, the mutation tests — lives in `just poc`.

## Layout

    poc/01-encoder/   RV32I instruction encoder in pure Nix, + its oracles
    poc/02-lexer/     C89 lexer in pure Nix, + its tables and throughput ladder
    poc/03-matcher/   lburg-style instruction selector, + real lcc DAGs to run it on
    poc/04-assembler/ items -> bytes: layout, labels, pseudo-instructions
    poc/05-loop/      the whole chain in one nix eval, and the faults beside it
    poc/06-constants/ C89 constant lexemes -> values and unit lists, diffed
                      against lcc form by form
    poc/07-parser/    C -> DAG in Nix: lcc's frontend middle-end ported file by
                      file, diffed against lcc's own listing byte for byte
    poc/lib/          what the timing ladders share: how they measure, and the
                      contention guard that says when a reading means nothing
    backlog/          tasks (managed with the backlog CLI, not edited by hand)
    flake.nix         dev shell, the rcc oracle, and the checks output

## License

The Nix code here is ours. Note that **lcc's license is non-OSI** and has
redistribution restrictions; this matters before publishing anything derived
from its source. tcc is LGPL.
