---
id: TASK-004
title: 'PoC-4: close the loop, encode and run RV32 inside one nix eval'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-15 01:41'
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
<!-- SECTION:NOTES:END -->
