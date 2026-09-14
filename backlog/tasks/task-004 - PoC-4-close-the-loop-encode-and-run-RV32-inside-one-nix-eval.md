---
id: TASK-004
title: 'PoC-4: close the loop, encode and run RV32 inside one nix eval'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 20:58'
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
<!-- SECTION:NOTES:END -->
