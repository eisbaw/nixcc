---
id: TASK-031
title: 'The execution drivers claim an ABI they do not set up: gp is never loaded'
status: To Do
assignee: []
created_date: '2026-09-15 05:33'
updated_date: '2026-09-15 16:14'
labels:
  - poc
  - matcher
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/03-matcher/drivers/*.s all begin `_start:' with the first instruction of the image and never load gp from __global_pointer$. Real crt0 does, wrapped in .option push/norelax/pop. A relaxing GNU ld is therefore entitled to rewrite `la rd,sym' into `addi rd,gp,off' whenever sym lands within 2 KB of __global_pointer$, and it does: ir/gsym.c's `la s1,tbl+4' became `addi s1,gp,-2044' and the store faulted in the emulator.

task-023 worked around it by passing -mno-relax and --no-relax in poc/03-matcher/run.sh's build_and_run, which is defensible -- the Nix assembler emits no relocations and never relaxes, and the Nix emulator sets no gp -- but it is the smaller lie, not the fix. The programs are the thing that is wrong.

Two consequences nothing currently tests. First, nixcc output linked by a relaxing GNU ld against startup code that does not set gp breaks exactly this way, and no check in the tree would see it. Second, the existing corpus got away with it only by luck: the `expr' case's `la s1,g' did not relax because g lands outside the 2 KB window.

Also here because it is the same three lines: `riscv32-none-elf-ld ... 2>/dev/null' in the same function swallows every linker diagnostic. This whole episode was found by a store faulting in an emulator rather than by a message, which is the argument against that redirect.

Found by the task-023 review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A shared startup loads gp from __global_pointer$ before calling the case under test, or the tree records in one place why these programs deliberately do not
- [ ] #2 The execution stage runs with linker relaxation ON again, or the reason it cannot is a measured one written down beside the flag
- [ ] #3 Linker diagnostics are visible; only the known-benign -z relro/-z now lines are filtered, and a real ld error still reaches the reader
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Citation update, not a change of scope: the -mno-relax / --no-relax flags and the 2>/dev/null on ld no longer live in a function called build_and_run in poc/03-matcher/run.sh. They moved to poc/03-matcher/build-and-run.sh under task-041, which took the function out of run.sh so that the mutation stage could reach it. The comment explaining them moved with them and still points here.
<!-- SECTION:NOTES:END -->
