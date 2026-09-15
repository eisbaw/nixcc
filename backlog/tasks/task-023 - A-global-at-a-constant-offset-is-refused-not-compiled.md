---
id: TASK-023
title: 'A global at a constant offset is refused, not compiled'
status: Done
assignee: []
created_date: '2026-09-15 02:02'
updated_date: '2026-09-15 09:30'
labels:
  - poc
  - matcher
  - assembler
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
lcc folds `msg[2]' on an `extern int msg[]' into a single node `ADDRGP4 msg+8'. poc/03-matcher's ADDRGP4 rules take the node's symbol verbatim, so this emits `la a0,msg+8', and poc/04-assembler then refuses it: nothing in the unit defines a symbol spelled `msg+8'. A refusal rather than a miscompile, but indexing a global by a constant is ordinary C and the demo in poc/05-loop had to pass its buffer as a parameter to avoid it (see the comment in poc/05-loop/hello.c).

Two places could own the fix. The matcher could split the symbol at the `+' and emit `la' followed by `addi'. The assembler could accept `sym+N' as a symbol expression, which is what GNU as does and which also gets `.word sym+4' in .data. The assembler is the better home: it already resolves every symbol at layout time, and a symbol expression is an assembler concept.

Found by TASK-004.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A C program that reads and writes a global array at a constant index compiles, assembles and runs in the Nix emulator with the right value
- [x] #2 The offset is resolved from the symbol table at layout time, not hand-computed
- [x] #3 A must-fail case covers a symbol expression whose base is undefined, with a diagnostic that names the base rather than the whole expression
- [x] #4 poc/05-loop/hello.c can take its buffer as a global again, and the comment pointing at this task goes away
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan (implementer):
- Own the fix in poc/04-assembler/asm.nix, as the task's own analysis argues: `lookup' first tries an exact symbol-table hit and only then splits a trailing `+N'/`-N' off the operand. Exact-first keeps a label literally named `f-1' working and matches what GNU as does.
- One place, so `la sym+N', `call sym+N', a branch to `L+N' and `.word sym+N' all resolve through the same code path at layout time; nothing is hand-computed.
- poc/04-assembler/parse.nix: widen the `.word'/.half/.byte operand pattern so a symbol expression reaches the assembler instead of being rejected as "neither a number nor a symbol".
- Diagnostic: an undefined BASE is named as the base, not as the whole expression. must-fail case + control, message pinned by messages.sh.
- Differential: put a symbol expression in progs/ so GNU as assembles the same bytes; pin its addresses in cases.nix; add a mutation that breaks the offset and must be caught.

IMPLEMENTED in 5f954f6. Gate: `nix develop --command just e2e' exit 0 -- 5 PoCs passed, lint clean, both ladders PASS.

WHERE THE FIX LIVES. poc/04-assembler/asm.nix only; poc/03-matcher/rules.nix and emit.nix are unchanged, which is the evidence that the seam is where the task said it was. One `lookup' serves la, call, a branch target and .word, so `msg+8' resolves the same way on all four paths.

THE AMBIGUITY DECISION, which is not in the task and matters. An operand can be read as a whole symbol or as base+offset. The first draft tried the whole operand first and picked; review pointed out that when both readings answer and disagree -- labels `f' and `f-1' both defined -- that is the only silent wrong answer in an assembler that otherwise refuses everything, and that the precedence was written as a list mainly so a mutation could reverse it. It now REFUSES the ambiguity. Order stopped being semantics, the list went away, and so did the mutation that only existed to test it.

SPELLING ACCEPTED: base+N and base-N, N plain decimal. GNU as also takes sym+0x8, sym + 8, sym+4+4 and reads a leading zero as OCTAL. Each is refused by name rather than resolved differently -- filed as task-030, which also carries the duplicate integer parser (parse.nix's parseInt against asm.nix's decimalOf).

TWO BUGS FOUND BY REVIEW AND FIXED HERE.
1. branchOff/jumpOff built their diagnostic from `symbols.${sym}', which has no key for an expression, so an out-of-range `beq sym+8' died with `attribute missing'. poc/05-loop/check.nix had the identical expression and is about to reach it when hello.c takes its buffer back as a global.
2. MEASURED, and a carry-forward for every must-fail suite in this tree: builtins.tryEval does NOT catch `attribute missing'. `builtins.tryEval (builtins.getAttr "nope" {})' aborts the evaluation rather than returning success=false. So that error class escapes must-fail.nix entirely -- it is not reported as a wrongly-accepted case, it kills the run. Any guard whose failure mode is a missing attribute is untested by tryEval and needs messages.sh or a check.nix pin.

GOTCHAS.
- The linker relaxes `la rd,sym' to `addi rd,gp,off' when sym is within 2 KB of __global_pointer$, and none of poc/03-matcher/drivers/*.s loads gp. ir/gsym.c's `la s1,tbl+4' became `addi s1,gp,-2044' and the store faulted in the emulator. -mno-relax/--no-relax in run.sh is the smaller lie; task-031 is the fix. The existing corpus escaped only by luck -- expr's `la s1,g' lands outside the window.
- `nix flake check' reads the GIT tree, so a new file must be `git add'ed before the gate will see it. Cost one full e2e run.
- lcc folds a string literal's subscript into an expression over a NUMERIC base, `ADDRGP4 2+4'. emit.nix's isLabelName does not recognise it, so it reaches the assembler unmangled and is refused. Loud, not silent, but it is the spelling every string literal produces -- filed as task-032, and it blocks task-028.

MUTATION COVERAGE, honestly. poc/04-assembler is at 28 mutations. Seven are new and aimed at this change: displacement dropped, sign inverted, feature removed entirely, ambiguity resolved instead of refused, leading zero accepted, the base not named in the diagnostic, and the .word operand class narrowed back. What has NO aimed mutation is `symexprWords', the fourteen pinned encodings: every mutation that moves a word also moves an address in `symbolExpressions', which check.nix reports first and deliberately so. That table is carried by the byte-for-byte differential against GNU as and by the address pins. Said out loud in run.sh rather than papered over.
<!-- SECTION:NOTES:END -->
