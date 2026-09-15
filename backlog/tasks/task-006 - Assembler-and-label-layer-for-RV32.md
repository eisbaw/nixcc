---
id: TASK-006
title: Assembler and label layer for RV32
status: Done
assignee: []
created_date: '2026-09-14 18:47'
updated_date: '2026-09-15 01:41'
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
- [x] #1 Items are data: insn, label, data bytes, align
- [x] #2 Address assignment is a linear fold, no ++ accumulation (decision-001)
- [x] #3 Forward and backward references both resolve from one symbol table
- [x] #4 PC-relative base is tested explicitly: branch and jal offsets are relative to the branch instruction's own address, and an off-by-one-instruction bug is caught by a test
- [x] #5 Branch out of range (beyond +-4 KiB) either relaxes to jal or throws with a clear message; whichever is chosen is tested
- [x] #6 lui/addi constant materialisation is one tested helper, not re-derived per call site, with cases at 0x7ff, 0x800, 0xfffff800, -1 and 0x80000000
- [x] #7 Differential test: assembled output matches riscv32-none-elf-as for a program using labels
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. poc/04-assembler/asm.nix: items (insn/label/bytes/align/section/global) -> { bytes; symbols }. Pass 1 is a genericClosure assigning per-section offsets (deepSeq per step, no ++); pass 2 is a map that encodes now every label address is known.
2. One tested helper hiLo/materialise for lui+addi, shared by li, la and call; cases 0x7ff, 0x800, 0xfffff800, -1, 0x80000000.
3. PC-relative base = the branch's OWN address; pinned by self-branch (offset 0), +8 forward and -4 backward cases, by the GNU-as diff, and by a mutation that adds 4 to the base.
4. Branch out of range: THROW with the distance and the label named (same as GNU as), not relax -- relaxation is a layout fixpoint and is filed as a follow-up task. Boundary cases at +-4094/-4096 pass, +-4096/-4098 throw.
5. poc/04-assembler/parse.nix: assembly text -> items, so poc/03-matcher's real emitted .s is the corpus rather than a hand-made program.
6. run.sh: (a) differential vs riscv32-none-elf-as -mno-relax, linked at 0x10000, .text bytes compared byte-for-byte; (b) execution oracle -- driver+runtime+emitted function assembled BY US and run in the nix-riscv emulator, exit code vs the matcher's expectation; (c) must-fail suite with control cases; (d) messages.sh for diagnostic text; (e) mutation tests on assembler AND harness.
7. Justfile: poc-assembler recipe. Full 'nix develop --command just e2e' before commit.
<!-- SECTION:PLAN:END -->

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

IMPLEMENTATION (poc/04-assembler)

Shape, and the two things it is worth knowing before touching it:

  asm.nix     items -> { bytes; symbols; placements; words; ... }. Pass one is
              ONE builtins.genericClosure carrying the running per-section
              offset and emitting one placement per item; the operator deepSeqs
              the state it returns. Pass two is a plain map, because by then
              every label address is known -- which is why a forward reference
              and a backward one are the same code path, with no fixup list and
              no second symbol table. Nothing is ever appended to with ++.
  parse.nix   assembly TEXT -> items. A front end, not the assembler. It exists
              only because poc/03-matcher already emits .s text; a code
              generator should build items and skip it.

Operand types are NOT guessed from how a token looks. asm.nix's table declares
each mnemonic's operand SHAPE and parse.nix reads the same table, so `beq
a0,a1,.L3' is (reg, reg, label) because `beq' says so. A label named `a1' in a
branch target therefore resolves as a label, and cases.nix's hand-built item
list has exactly that case so a future shortcut ('strings that look like
registers are registers') fails a test rather than miscompiling.

DECISIONS TAKEN, with the reasons:

  * Branch out of range: THROW, not relax (AC #5). GNU as does the same, which
    is what keeps the differential exact. Relaxation is a layout fixpoint, and
    poc/03-matcher already paid once for an unasserted fixpoint. Filed as
    task-021 and the throw site names it.
  * No relocations. Every symbol resolves at layout time; one undefined symbol
    is a throw naming it. Filed as task-022, along with .bss/.rodata and
    .align beyond 2^4.
  * jal/jalr accept both their spellings (`jal target' and `jal rd,target');
    the operand table holds a list of shapes rather than one.

GOTCHAS, all of them measured rather than reasoned:

  * An unforced check is no check. `measure' sized an instruction as
    4 * spec.n args, and `n' for a fixed-length instruction IGNORES its
    argument -- so checkOps was never forced and `beq' with two operands
    reached the encoder and died on elemAt. It needs builtins.seq. The
    must-fail suite found this on its first run.
  * GNU as does NOT zero-fill alignment padding in a code section. Measured
    (.byte xN then .align 3, N = 1..7): zeros until the offset is even, then a
    2-byte c.nop if that lands the rest on a 4-byte boundary, then 4-byte
    nops. It emits c.nop even for -march=rv32i. It also pads the SECTION out
    to the widest alignment any .align in it asked for. Both are needed for a
    byte-for-byte match.
  * GNU ld's -Tdata reads a bare number as HEX. Passing 66048 put .data at
    0x66048 and made a 516-byte image come back as 344 kB.
  * An empty .data must contribute nothing to the image, not even the
    alignment gap -- four zero bytes after the last instruction that ld does
    not produce. The differential caught it.
  * The +0x800 correction can carry out of 20 bits: for 0xfffff800 the
    unmasked hi is 0x100000, outside lui's field. The mask is load-bearing,
    not hygiene, and hiLoCases pins it.
  * Reporting EVERY mismatch made two different bugs indistinguishable in the
    mutation test (a wrong PC base and a wrong auipc delta both make the `la'
    words wrong). Every verdict in check.nix now reports its first failure and
    a count of the rest.
  * Guard order matters twice over: hiLo/liParts are checked before any
    program-level encoding, because a broken split makes `call' and `la' wrong
    everywhere and reporting THAT sends the reader to the wrong file; and the
    corpus-shape checks (does progs/ still reach every mnemonic, does pcrel.s
    still have a forward and a backward reference) sit with the floors,
    because deleting one instruction moves every address after it and the
    report was a branch encoding rather than 'you deleted a case'.

One more, and it is the gate catching me rather than me catching it: the scale
ladder's smallest point was 250 blocks, which measured 0.132 s CPU against a
0.035 s evaluator start-up baseline. poc/lib's shared rule is that a point must
cost at least three times the baseline NET of it, and 0.097 s is under the
0.105 s that needs -- so `just e2e' refused the ladder as unmeasurable, exit 2,
after several standalone `just poc-assembler' runs had scraped past it. Sized
to 500/1000/2000/4000 blocks, which leaves about 7x. Anyone adding a ladder
here should size its smallest point against `nix eval' of an empty expression,
not against how long it feels.

Landed as ce02ad3, on a green gate: `nix develop --command just e2e' EXIT=0,
5m42, 4 PoCs passed, lint clean. What poc/04-assembler reported in that run:

  5 programs in progs/, 110 instruction words, 8664 bytes
  24 encodings pinned, 9 label addresses, 5 section layouts
  12 li expansions, 9 hiLo splits, every value the task names
  65 mnemonics implemented, all of them reached by progs/
  99 instruction placements agree with what they encoded to, 11 wider than a word
  16 hand-built items assembled with no assembly text involved
  24 reject cases, 17 control cases, 24 diagnostics checked for their text
  5 progs + 7 of poc/03-matcher's real functions identical to GNU as, 11584 bytes
  7 of those executed in the Nix RV32I emulator, each returning what
    poc/03-matcher/cases.nix expects (72, 119, 29, -2, 14, 55, 37)
  18 mutations, each with its own distinct failure
  ladder: 19355-20916 items/s, 8.4-8.5 kB/item net, 366 MB at 40004 items,
    linear over 8x

Per criterion:
  #1 items are data -- insn, label, bytes, align, plus section/global/zero and
     an explicit 'ignored' for the directives that carry no layout. cases.nix's
     handBuilt assembles 16 of them with no text anywhere.
  #2 address assignment is one genericClosure, deepSeq per step, nothing
     appended to; measured linear over 8x.
  #3 one listToAttrs symbol table answers both directions, and check.nix
     asserts pcrel.s really does reference one label before defining it and
     another after -- so the claim cannot go stale.
  #4 pinned at offset 0 (a branch to itself), +8 and -4, and at delta 0 for an
     auipc pair; the pc+4 mutation is caught with the self-branch's own note.
  #5 THROWS, naming the label, the distance and the remedy. -4096 and +4092
     assemble; -4100 and +4096 are refused; messages.sh holds the text.
  #6 hiLo/liParts are one helper used by li, la and call, with 0x7ff, 0x800,
     0xfffff800, -1 and 0x80000000 among 12 li and 9 hiLo cases, and a floor
     that fails if any of those five leaves the table.
  #7 differential against riscv32-none-elf-as on twelve label-using programs,
     whole images including padding.

HONEST LIMITS, none of them papered over:
  * A branch beyond +-4 KiB stops the compiler. task-021.
  * One translation unit. No relocations, no .bss, no .rodata, .align <= 2^4.
    task-022.
  * The range guards are about the MESSAGE; encode.beq's own `fits' is the
    safety net, and removing the guards is caught by messages.sh, not by
    must-fail.nix. Said plainly in asm.nix rather than claimed as a second
    line of defence.
  * The GNU-as differential passes ld our own dataBase with -Tdata, so a wrong
    .data base would be fed to both sides and agree. The emulator stage is
    what covers that.
  * 8.5 kB of peak RSS per item is the number to plan with: 366 MB for 40004
    items, and a byte list is four live Nix integers per instruction.
<!-- SECTION:NOTES:END -->
