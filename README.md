# nixcc

A C compiler for RISC-V, written in the Nix expression language.

`nix eval` alone compiles C and runs it. No gcc, no assembler, no linker, no
emulator binary — the lexer, parser, type checker, DAG builder, instruction
selector, assembler and the RV32I machine are all Nix expressions.

## Example

`example.c` — sums the squares from 1 to n:

```c
extern int wc(int ch);          /* writes one character to stdout */

struct acc { int sum; int n; };

int show(int v)
{
    if (v >= 10) show(v / 10);
    wc(v % 10 + 48);
    return 0;
}

int run(int n)
{
    struct acc a;
    int i;

    a.sum = 0;
    a.n = n;
    for (i = 1; i <= a.n; i++)
        a.sum = a.sum + i * i;

    show(a.sum);
    wc(10);
    return 0;
}
```

```console
$ nix develop
$ just run example.c 7
140
$ just run example.c 10
385
```

Your program defines `int run(int)`. `extern int wc(int)` writes one character —
the syscall ABI is target knowledge, so the driver supplies it as three
instructions of assembly. Everything else is compiled from the C.

## Running it

```console
just run FILE ARG   # compile a C file and run it
just e2e            # build the oracles and run every proof-of-concept
just ir FILE        # dump lcc's reference IR for a C file
just --list         # everything else
```

Needs Nix with flakes. `nix develop` gives you the shell; `nix flake check`
runs the differential tests in a sandbox.

## What works

`int`, `char`, `short`, `long`, `unsigned`, pointers, arrays, `struct`, `union`,
`enum`, `typedef`, function pointers, the full integer and bitwise operator set,
`if`/`while`/`for`/`do`, calls and recursion, string literals, `sizeof`.

The preprocessor does `#define` and `#undef` — object-like and function-like,
with the `#` stringify and `##` paste operators — the whole conditional family
— `#ifdef`, `#ifndef`, `#if` with constant-expression evaluation including
`defined()`, `#elif`, `#else`, `#endif` — `#line`, and backslash-newline
continuation. `#if` arithmetic is C89's, evaluated in `long`, which is 32 bits
on this target; gcc's is 64-bit, so the two differ on expressions that
overflow. A macro invocation has to fit on one logical line: an argument list
that opens on one line and closes on the next is refused, and so is a
function-like macro name at the end of a line whose successor begins with `(`.

**Not yet**: `#include`. Also absent: floating point, `switch`, `goto`,
varargs, bitfields, file-scope initialisers. Every one of these is *refused
with a diagnostic naming the reason and the task that will implement it*,
never silently miscompiled.

## How it is verified

The frontend's IR is diffed byte-for-byte against lcc's own — 34 translation
units, 73 functions, 2211 node lines — and the compiled programs are executed
and their answers checked. The preprocessor's output is diffed against `gcc -E`
as token streams over 48 translation units, and its linemarkers are checked by
feeding them to lcc's own frontend and reading back where it says its
diagnostics came from. Every test harness is mutation-tested: breaking the
compiler *and* breaking the harness must each fail.

`git log --notes=verification` carries what was checked for each change,
including what was skipped.

## Why lcc, not tcc

tcc is single-pass and backpatches machine code in a mutable buffer, which has
no good translation into a language without mutation. lcc goes source → AST →
DAG → instruction selection, and its instruction selector is a declarative rule
table. See `backlog/decisions/` — nine records covering the measured Nix
constraints, the oracle's limits, and the ABI divergences.

## Layout

```
poc/01-encoder    RV32I instruction encoder
poc/02-lexer      C89 lexer
poc/03-matcher    lburg-style instruction selection
poc/04-assembler  labels, sections, bytes
poc/05-loop       the end-to-end demo
poc/06-constants  C constant evaluation
poc/07-parser     the C frontend: parse, types, DAG
poc/08-cpp        the C preprocessor
backlog/          tasks and decision records
```

## License

The Nix code here is ours. lcc is fetched at build time as an oracle and is not
redistributed; its licence is non-OSI and has redistribution restrictions.
