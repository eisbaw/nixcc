---
id: TASK-004
title: 'PoC-4: close the loop, encode and run RV32 inside one nix eval'
status: Done
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-15 02:45'
labels:
  - poc
  - integration
  - demo
dependencies:
  - TASK-001
  - TASK-006
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Feed bytes produced by our Nix encoder (task-001) straight into nix-riscv's RV32I emulator and get program stdout back, all inside a single nix eval with no external toolchain in the path.

This is the project's headline demo and it also sidesteps a hard Nix limit: Nix strings cannot contain NUL, so an ELF can never be a Nix string. Emitting a byte list and executing it in-Nix means no binary ever has to leave the evaluator.

nix-riscv exposes load/step/run/report and implements the write() and exit() syscalls, so the emulator side already exists; this task is about the join.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A program assembled by our Nix encoder runs on nix-riscv's emulator and prints a known string via the write syscall
- [ ] #2 The program exits with status 0 through the exit syscall and the emulator reports halted cleanly
- [ ] #3 Instruction bytes come from our encoder, not from a pre-built image in nix-riscv/images
- [ ] #4 The whole thing runs as a single 'nix eval' with no assembler, linker or emulator binary involved
- [ ] #5 A negative test exists: a deliberately malformed program halts with a reported fault rather than hanging or silently succeeding
- [ ] #6 Runnable as 'just poc-loop'
- [ ] #7 At least one backward and one forward branch is resolved from a symbol table, not hand-computed: without a label layer the human is acting as the linker, which proves nothing about the layer we need
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Write poc/05-loop/: a C program (hello.c) whose IR comes from rcc-rv32 (just ir), compiled by 03-matcher/emit.nix, assembled by 04-assembler/asm.nix, run in nix-riscv rv32.nix -- all in ONE nix eval.
2. The demo prints a string through the write syscall (sys 64) from a .data buffer whose digits the compiled C computes, then exits 0 through sys 93.
3. Driver and message data are built as asm.nix ITEMS in Nix (no assembly text); the libcall runtime is reused from 03-matcher/runtime.s via parse.nix. Record the remaining text intermediate (emit.nix -> .s -> parse.nix) as a finding for task-005 rather than papering over it.
4. check.nix: pure pins on the demo's stdout bytes, exit code, reason, and on at least one forward and one backward branch resolved from the symbol table (direction computed from symbols, not asserted by hand).
5. must-fail.nix + messages.sh: malformed programs that must halt with a REPORTED fault (illegal-instruction, access faults, misaligned, unsupported-syscall, budget), each checked on its exact rv32 reason string, each paired with a control that must still run clean.
6. run.sh: stages -- pure checks, must-fail, messages, single-eval demo with a PATH that has no binutils in it (asserted), memory/time measurement, mutation test over BOTH the demo and the harness.
7. Justfile recipe poc-loop, flake check, full 'just e2e' gate before commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-003: poc/03-matcher already runs a large part of this loop, just not inside a single nix eval. It takes real lcc DAG output, selects instructions, emits RV32 assembly, and then goes OUT to riscv32-none-elf-as / ld / objcopy before coming back in to nix-riscv's rv32.nix, which executes the bytes and reports the exit code. Three functions do this in poc/03-matcher/run.sh and all three agree with the host compiler.

So what task-004 has to replace is exactly the two external steps: assembling (task-006) and linking/laying out. The emulator side is already proven and is three lines -- cpu.run limit (cpu.load { bytes; base = 65536; entry = 65536; }) -- and syscall 93 carries the return value out as exitCode, which is what made the matcher's execution test cheap.

forward-carried from task-006: the assembler you were blocked on is
poc/04-assembler, and the loop you need is already closed once in its run.sh.

  (import poc/04-assembler/asm.nix { }).assemble { items; textBase ? 0x10000; }
      -> { bytes; symbols; text; data; textBase; dataBase; placements; words; }

`bytes' is the flat image the Nix emulator loads at `textBase'. run.sh stage 4
concatenates poc/03-matcher/drivers/NAME.s, the matcher's emitted function and
poc/03-matcher/runtime.s into ONE item list, assembles it, and runs it in
nix-riscv's rv32.nix with base = entry = 65536 -- no binutils anywhere. All
seven matcher functions return what poc/03-matcher/cases.nix expects. Copy that
path rather than rebuilding it.

Two things to decide rather than inherit:

  * TEXT OR ITEMS. poc/04-assembler/parse.nix turns .s text into items so the
    matcher's existing output can be assembled today, but assembly text is an
    intermediate a single-eval compiler should not have. If task-004 is the
    place to make emit.nix produce ITEMS directly, asm.nix takes them and
    parse.nix drops out of the path. Read asm.nix's `measure' for the whole
    item vocabulary and cases.nix's `handBuilt' for a worked example -- it is
    16 items, including a .data section and a symbol-valued .word.
  * ARGUMENT ORDER OF THE UNITS. The symbol table is one attrset over the
    whole item list, so the driver, the runtime and the function can be
    concatenated in any order; only the ADDRESSES move. Whatever order you
    pick, _start must be the first thing in .text if you want entry = textBase.

What it will refuse: a branch beyond +-4 KiB (task-021), a symbol nothing in
the unit defines, anything but .text and .data, .align beyond 2^4 (task-022).
Each throw names the task. None of these bite on a demo-sized program.

IMPLEMENTATION (task-004)

poc/05-loop/ closes the loop. `just poc-loop', and `nix flake check' gets the
pure half of it as checks.loop.

WHAT THE DEMO IS. poc/05-loop/hello.c sums 1..10, converts the total to two
decimal digits, writes them into a .data buffer and asks write() for eleven
bytes of it. It prints

    1..10 = 55

and exits 0 -- the 0 comes from hello() checking that write() reported all
eleven bytes, so the exit status is not a constant. 711 RV32I instructions.

THE CHAIN, all inside one `nix eval':

    hello.sym --03-matcher/emit.nix--> assembly text
              --04-assembler/parse.nix--> items
              --04-assembler/asm.nix--> 648 bytes
              --nix-riscv/rv32.nix--> stdout bytes + exit code

The driver (entry point, the write() stub, the vector, the message) is built as
ITEMS in Nix by driver.nix -- no assembly text anywhere in it. The
multiply/divide runtime is poc/03-matcher/runtime.s, read through parse.nix
rather than hand-translated a second time.

FILE BY FILE
  items.nix      item constructors + an ASCII table, shared by the demo and the
                 fault programs so both go through the same assembler
  driver.nix     the demo's own items and what it is expected to print
  demo.nix       the chain, and runItems for the fault programs
  cases.nix      the demo's pins, 8 fault programs, 11 controls
  check.nix      the pure verdict (this is what checks.loop forces)
  provenance.sh  regenerates hello.sym from hello.c with lcc and diffs it
  closed-loop.sh ONE nix eval with a PATH that has no binutils reachable
  measure.py     what it costs in memory
  run.sh         the five stages and a 17-case mutation test

MEASURED
  demo:            711 instructions, 648-byte image, 193 items
  check.nix:       0.16 s CPU, 74 MB peak RSS (all 19 programs, demo included)
  closed loop:     0.06-0.10 s CPU and 30 MB net of the evaluator's 36 MB
                   baseline, i.e. AT MOST 43.5 kB of peak RSS per emulated
                   instruction -- at most, because the same figure carries
                   selecting and assembling too. Ceiling set at 70 kB/step.
  just e2e:        5m21, 5 PoCs, lint clean

THE NEGATIVE TEST (criterion 5), which is the part worth reading

Eight malformed programs, each pinned to the exact `reason' nix-riscv reports
for it, and none of them may report `exit':

  illegal-instruction              a .word 0 in .text
  instruction-access-fault         a jump to the first address past RAM
  instruction-address-misaligned   a jump to base+2
  load-address-misaligned          lw from base+1
  load-access-fault                lw from past RAM
  store-access-fault               sw to past RAM
  unsupported-syscall              ecall with a7 = 1234
  budget                           `1: j 1b' under a 50-step limit

The last one is the failure mode the criterion actually names: a program that
never stops must be REPORTED, not hung. cases.requiredReasons names all eight,
so a table that lost one and gained a duplicate is a HARNESS FAULT rather than
a pass.

Eleven controls sit beside them and must still run to a pinned exit status --
the same jump to a multiple of four, the LAST word of RAM beside the first word
past it, a .word that decodes to a real instruction, the same loop under the
same budget with a counter in it. Three of them drive write() from items rather
than from C, which is the only way to reach its -EBADF and -EFAULT returns; one
of those pins the stdout bytes as well.

CRITERION 7, done as a measurement rather than an assertion. For every branch
and jump in the whole image, the distance the SYMBOL TABLE implies is compared
against the immediate decoded back out of the assembled word. 19 agree; 5
forward and 1 backward of them are inside the compiled function. A hand-
computed offset would have to be wrong in both places identically to pass.

THREE THINGS THE MATCHER REFUSED, found while writing hello.c. Each is a
refusal rather than a miscompile, and each is now a task:

  * task-023  `msg[2]' on an `extern int msg[]' folds to ADDRGP4 `msg+8'. The
              matcher passes the symbol through verbatim and the assembler
              then refuses it: nothing defines a symbol spelled `msg+8'. The
              demo passes its buffer as a PARAMETER to get around it, which is
              why hello() takes three arguments and not two.
  * task-024  there is no rule for a byte load or store, so a C program cannot
              touch a string. The demo builds its message a WORD at a time --
              four ASCII codes packed little-endian and stored with `sw' --
              which is why the prefix is exactly eight characters and why the
              digits are shifted into place.
  * task-025  `wr(1, out, 11);' as a STATEMENT does not compile: the discarded
              CALLI4 reduces to `stmt' with dst = null and the template dies
              with "uses %c outside an instruction". Two rows in rules.nix fix
              it. The demo checks write()'s return value instead, which is
              better C but was not a free choice.

ALSO FILED
  * task-026  emit.nix should produce ITEMS, not assembly text. This is the
              last seam inside the evaluation: the matcher serialises to .s and
              parse.nix immediately reads it back. poc/05-loop has both paths
              side by side -- the driver is items, the compiled function is
              text -- which is what makes the comparison concrete.

REVIEW ROUND, and what it changed. Two reviewers ran against the first draft
and between them found the failure this project has shipped four times, one
level up from where it was looked for:

  * ELEVEN GUARDS in check.nix could be DELETED without the mutation stage
    noticing, and FOUR TABLES could be EMPTIED while it still returned
    success -- requiredReasons, the demo's address table, the compiled-branch
    floor, and a control's stdout pin. Proved by deleting them and re-running
    the full suite, which reported 17 mutations detected either way.
  * "THE EMULATOR RAN OUR BYTES" was checked for 4 bytes of 648. A byte
    tampered with at offset 400 -- inside a real instruction -- passed, and so
    did a byte appended to the image.
  * The control stdout pin was `if r ? stdoutBytes', which went vacuous for
    eight of eleven controls; a control that spuriously wrote four bytes
    passed.
  * TWO DEAD GUARDS: a "produced no output at all" check that a byte-list
    comparison five guards earlier had already made unreachable, and a
    fragment-equality `continue' in run.sh's distinctness loop that would turn
    "two mutations produce the same alarm" from a failure into a silent skip.
  * The expected output was WRITTEN BESIDE the vector rather than derived from
    it. Changing the vector made the program's correct answer read as a
    compiler bug, with a failure message that still said 1..10.
  * A missing unit reported "fewer items than expected" from check.nix
    instead of the assembler's own "nothing in this unit defines `__divsi3'",
    because an item-count floor fired before the image was ever forced.

Fixed, each with a mutation aimed at it: byte-for-byte RAM comparison plus the
memory-entry count; floors on every table; the stdout pin unconditional; the
dead guards gone; prefix and digits derived from the vector with a layout
guard; the item floor moved below the image checks. 17 mutations became 31.

Also: the "no toolchain" PATH was `dirname $(command -v nix)', which on this
machine is /run/current-system/sw/bin -- 1566 binaries including a host `as'.
It is now a directory holding one symlink, to nix.

Two things the reviewers were right about that were NOT fixed here, with the
reason:
  * items.nix's constructors are a second declaration of a format asm.nix's
    `measure' already declares, and belong beside it. Moving them reshapes the
    assembler's public surface, which is task-026's job; items.nix says so in
    its header.
  * the guarded-PATH stage proves less than it reads: a `nix eval' of a pure
    expression could only reach a PATH binary through import-from-derivation,
    so the property is close to true by construction. The comment now says
    that, and says what it does rule out -- a harness that shells out, which
    has happened here before.

PER-CRITERION STATUS, all seven met.

#1 write syscall prints a known string. "1..10 = 55\n", 11 bytes, through
   syscall 64. The digits are computed by compiled C from a vector summed by
   compiled C -- the `vector one shorter' mutation makes the program print 45,
   which is only possible if the arithmetic is real. Pinned as a BYTE LIST,
   which is the NUL-safe form decision-001 forces, with the printable string
   beside it.
#2 exit(0) through the exit syscall, halted cleanly. reason == "exit",
   exitCode == 0, and the 0 is load-bearing: hello() returns it only when
   write() reported all eleven bytes.
#3 bytes from our encoder, not a pre-built image. asm.nix -> encode.nix, and
   check.nix compares EVERY byte of the loaded machine's RAM against the
   image, plus the number of RAM entries against its length.
#4 one `nix eval', no assembler/linker/emulator binary. closed-loop.sh runs it
   under a PATH holding one symlink to nix and refuses if the cross toolchain
   is reachable. See the review note for how much that proves.
#5 negative test. 10 malformed programs, each on its own rv32 `reason',
   including the one that would otherwise hang; 12 controls that must still
   run with status and stdout pinned.
#6 `just poc-loop', at poc/05-loop/run.sh, picked up by `just poc'.
#7 forward and backward from the symbol table. 19 branch offsets in the image
   cross-checked against the immediate decoded back out of the assembled word;
   5 forward and 1 backward inside the compiled function.

GATE, actual: nix develop --command just e2e -> "5 PoC(s) passed", 5m38,
lint clean. Commit b1f34af.

Two earlier runs of the same gate on the same tree did not pass, and neither
was this change:
  * one exited 3 -- a ladder rendered NO VERDICT on a busy machine, which
    task-020 documents as roughly one run in three here;
  * one exited 1 with poc/02-lexer's ladder reporting SUPERLINEAR at 13.89x
    input for 21.14x CPU, measured against 2.64 cores of other work, under the
    3.50 the guard needs to render a verdict at all. poc/02-lexer references
    nothing this change touched. That is the known hole poc/lib/contention.py
    records: the threshold was measured, but iowait counts as idle and this
    machine is carrying an unrelated runaway process.

WHAT THE DEMO DOES NOT PROVE, which is what task-005 has to decide against:
the entry point of that single eval is hello.sym, lcc's IR listing, NOT
hello.c. The preprocessor, the parser and the DAG builder do not exist; the
lexer does. Everything DOWNSTREAM of the IR is Nix with no external toolchain
in it. `just poc-loop' regenerates hello.sym from hello.c with lcc and diffs
it on every run, so the C file is the source of truth -- but lcc, not Nix, is
what reads it today.
<!-- SECTION:NOTES:END -->
