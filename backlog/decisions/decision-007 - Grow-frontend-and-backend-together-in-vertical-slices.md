---
id: decision-007
title: Grow frontend and backend together in vertical slices
date: '2026-09-15 04:39'
status: accepted
---
## Context

The original milestone, chosen before any PoC ran, was to port lcc's full C89
frontend before anything else. The concern then was that nothing would run until
a great deal worked. Five PoCs later the evidence has moved, and in a direction
nobody predicted.

What is proven: the loop is closed from lcc's IR downward. `just poc-loop`
compiles `poc/05-loop/hello.c`, assembles it and runs it on nix-riscv inside one
`nix eval` whose PATH holds exactly one binary -- nix itself. It prints
`1..10 = 55` through the write syscall and exits 0 through the exit syscall, in
711 instructions and a 648-byte image. Independently re-verified by the
orchestrator. The only gap between `.c` and a running program is the
preprocessor, the parser and the DAG builder; the lexer already exists.

What changed the decision: writing forty lines of ordinary C for that demo hit
three separate BACKEND refusals -- a global at a constant offset (lcc folds
`msg[2]` into `ADDRGP4 msg+8`, task-023), any byte load or store and therefore
`char` (task-024), and a call whose int result is discarded (task-025).
`hello.c` had to be written around all three. That is direct evidence that the
rule table is thin, and it was not available when the milestone was chosen.

Measurements that bound the design. Throughput is a non-issue: 47000 tokens/s,
a 1143-line file lexed in 0.29 s. Memory is the constraint and it is roughly
linear per live value -- 4 kB per token, 8.5 kB per DAG node, 8.5 kB per
assembler item, each net of the evaluator's own 36 MB. A stage that holds
tokens, an AST, a DAG and a label table live at once multiplies those.

## Decision

Grow the frontend and the backend together in vertical slices. Each slice adds
a C language feature AND the backend rules that consume it, and every slice ends
with real C compiling and running end to end.

Reject full-frontend-first. It is now measurably the wrong order: a complete C89
frontend would emit `ADDRGP4` with offsets, byte loads and discarded call
results that the rule table refuses today, so the frontend would be finished and
unusable, with the mismatch discovered at integration rather than immediately.

Reject backend-first as well. It keeps the loop closed but defers the entire
"Nix parses C" claim, which is the project's point.

## Consequences

The oracle keeps its role but stops being the only gate. Frontend slices still
diff against `rcc-rv32` node by node (decision-004), and each slice additionally
has to compile and RUN, which catches the class of defect an IR diff cannot see.

Backend gaps block real C, so tasks 023, 024 and 025 come before parser work:
without `char` there is no string handling worth the name.

The slice boundary is the unit of honesty. A slice is not done because the
parser accepts the syntax; it is done when a C program using the feature runs
and produces the right answer.

Two lexer decisions already constrain the parser and are hard to reverse. Token
values are not computed, only classified (task-011) -- in Nix, integer overflow
throws and strings cannot hold NUL, so neither lcc's overflow detection nor its
string decoding transliterates. And the token set is lcc's, which has no
compound-assignment tokens: `<<=` is LSHIFT then `=`, disambiguated by peeking
at the preceding trivia. A parser wanting `<<=` as one token must change the
lexer, not work around it.
