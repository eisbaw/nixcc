---
id: TASK-022
title: 'Sections beyond .text and .data, and symbols the unit does not define'
status: To Do
assignee: []
created_date: '2026-09-15 01:12'
labels:
  - backend
  - assembler
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/04-assembler lays out exactly two sections, .text and .data, in that order, and resolves every symbol at layout time. Anything else is refused by name: '.rodata' throws, and so does a reference to a symbol nothing in the item list defines.

That is the right shape for a single-eval compiler -- one translation unit, no relocations, no linker -- and it is what makes 'nix eval alone compiles and runs C' possible. It becomes wrong in three places:

  * .bss. Zero-initialised data currently has to be .zero bytes in .data, which puts every zero in the image.
  * .rodata. String literals and jump tables want a read-only section.
  * Separate compilation. If nixcc ever compiles translation units independently, unresolved symbols have to survive as relocations rather than throw.

Also here: alignment is computed on SECTION OFFSETS with section bases 16-aligned, so '.align 5' and beyond is refused. Widening that means aligning the bases themselves.

The refusal sites are 'measure' and 'lookup' in poc/04-assembler/asm.nix and they name this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The section list is data rather than a two-way if, and .bss and .rodata are laid out with their own bases
- [ ] #2 .align beyond 2^4 is honoured, which means section bases are aligned to the widest alignment any item in them asks for
- [ ] #3 A decision is recorded on whether unresolved symbols stay a throw (one translation unit) or become relocations (separate compilation), with the reason
- [ ] #4 The differential against GNU as covers a program with all four sections, linked at addresses the test chooses
<!-- AC:END -->
