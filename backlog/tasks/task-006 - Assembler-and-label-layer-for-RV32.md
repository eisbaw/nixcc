---
id: TASK-006
title: Assembler and label layer for RV32
status: To Do
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-14 21:51'
labels:
  - backend
  - assembler
dependencies:
  - TASK-001
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The encoder takes resolved byte offsets: e.jal "ra" 4. A code generator does not have those -- it has `beq a0, a1, .L3`. The missing layer is an assembler: items (insn / label / data / align), a fold assigning addresses, and a resolve pass.

This is where the real bugs live -- PC-relative base off-by-one, forward references, wrong section -- and it sits between the encoder (task-001) and any code generator. Filed as a blocker on task-004 so that PoC-4 cannot paper over it by hand-computing a twelve-instruction program.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Items are data: insn, label, data bytes, align
- [ ] #2 Address assignment is a linear fold, no ++ accumulation (decision-001)
- [ ] #3 Forward and backward references both resolve from one symbol table
- [ ] #4 PC-relative base is tested explicitly: branch and jal offsets are relative to the branch instruction's own address, and an off-by-one-instruction bug is caught by a test
- [ ] #5 Branch out of range (beyond +-4 KiB) either relaxes to jal or throws with a clear message; whichever is chosen is tested
- [ ] #6 lui/addi constant materialisation is one tested helper, not re-derived per call site, with cases at 0x7ff, 0x800, 0xfffff800, -1 and 0x80000000
- [ ] #7 Differential test: assembled output matches riscv32-none-elf-as for a program using labels
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: an assembler is the same shape as a lexer, so reuse the shape.

Label resolution is a sequential pass that emits one value per instruction -- exactly what builtins.foldl' cannot do. Use builtins.genericClosure: it is an iterative worklist in the evaluator, measured linear at constant stack depth (0.07/0.11/0.18/0.35/0.49 s at 25000..400000 steps). Two traps in it: keys must be unique because duplicates are SILENTLY DROPPED, and it forces only 'key', so the operator must deepSeq the item it returns or the field chain grows as deep as the loop and dies with 'stack overflow (possible infinite recursion)' -- measured at 100000 steps, and not as a slowdown first.

Two-pass assembly (measure, then place) is the natural fit: pass one is a genericClosure over instructions carrying a running address, pass two is a plain map now that every label's address is known. No list is ever appended to.

builtins.substring COPIES ITS HAYSTACK -- cost proportional to the string being sliced, not to the slice. Never parse assembly text by repeatedly slicing the source: 20000 four-byte slices cost 0.11 s at 278 kB and 0.84 s at 2.2 MB. Explode to a character list with builtins.split "(.)" (one evaluator call, 10x faster than genList+substring) and cut with concatStringsSep. Better still, do not have assembly text at all: emit instruction records and let the encoder consume them.

The output is a byte list, not a string -- Nix strings cannot hold NUL (decision-001), so an ELF can never be one.

Harness lessons from poc/02-lexer, which are the reason its suite catches things: order the guards so a HARNESS FAULT can never pre-empt a real diagnosis; assert the fields nothing else looks at (addresses and label offsets are this task's equivalent of line numbers, which went unverified in the lexer until a reviewer noticed a lexer answering 'line 1' to everything would pass every test); check what errors SAY and not only that they threw, which needs a shell loop because builtins.tryEval never returns the message; mutation-test the measurement code, not only the code under test; and measure performance in CPU time rather than wall clock, because a wall-clock linearity assertion fails on a busy machine from a change that never happened.

forward-carried from task-003: poc/03-matcher emits assembly TEXT and hands it to riscv32-none-elf-as. When this task replaces that assembler, poc/03-matcher/ir/*.s is the first real corpus to feed it, and poc/03-matcher/run.sh already assembles, links and executes those three functions, so a Nix assembler can be diffed against binutils on exactly the same input.

What the matcher's templates actually need from an assembler, which is more than the encoder (poc/01-encoder) provides today:
  * PSEUDO-INSTRUCTIONS. The rule templates emit 'li', 'la', 'mv', 'call', 'j', 'ret', 'beqz'/'bnez'/'bgez'/'neg' (the last four only in runtime.s). 'li' and 'la' expand to lui+addi when the value does not fit 12 bits, and 'call' to auipc+jalr when the target is far. Either the assembler expands them or the rule table stops using them -- and the rule table is the wrong place, because expansion depends on the value, not the pattern.
  * LOCAL LABELS and forward references: '.Lf_2' is branched to before it is defined, so this needs two passes or a fixpoint over label addresses, which is where branch-range relaxation also lives.
  * DIRECTIVES the emitter produces: .text, .data, .align, .globl, .type, .size, .word.
  * RELOCATIONS against symbols the function does not define -- 'la s1,g' and 'call h'. For a single-eval compiler these can be resolved at layout time rather than emitted as relocations, but something has to resolve them.

Also: nix-riscv's rv32.nix takes { bytes; base; entry; } and 'run limit', and reports exitCode, regs and stdoutBytes. Syscall 93 is exit and 64 is write. poc/03-matcher/run.sh shows the whole path; it currently goes through objcopy only because there is no Nix linker yet.

forward-carried from task-003: the emitted assembly also uses the pseudo-instruction 'la' for a global's address and 'call' for a direct call, both of which GNU as expands depending on the value and the distance. Those two, plus 'li', are the ones an in-Nix assembler cannot treat as single instructions.

forward-carried from task-003, and this one is a trap rather than a fact: poc/03-matcher/emit.nix reads two fields out of the reduction state to build the prologue, and they are NOT interchangeable.

  st.cseHigh  / st.depthHigh   running maxima. These are what the save list and
                               the frame must be built from.
  st.nextCse                   an allocation cursor. It RESETS to zero at every
                               label, because the common-subexpression table
                               does. It is read by the register-exhaustion
                               check and by nothing else.

Reading the cursor where the maximum was meant produced a function that wrote a callee-saved register, held it across a call, and neither saved nor restored it -- assembly that assembles, runs, and quietly corrupts its caller. poc/03-matcher/ir/save.c is the regression pin; check.nix's savedCheck catches it by scanning the emitted prologue rather than the frame record, which is the only reason it can see it at all.

If this task grows emit.nix, or moves the prologue into an assembler layer, keep that distinction. The general form: any state threaded through a walk that resets at a control-flow boundary cannot also serve as a whole-function total.
<!-- SECTION:NOTES:END -->
