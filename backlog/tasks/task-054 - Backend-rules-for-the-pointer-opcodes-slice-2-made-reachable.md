---
id: TASK-054
title: Backend rules for the pointer opcodes slice 2 made reachable
status: Done
assignee: []
created_date: '2026-09-16 01:02'
updated_date: '2026-09-16 03:34'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
poc/07-parser now emits CNSTP4, CVUP4, CVPU4, SUBP4 and RETP4 for ordinary C -- a null pointer constant, a cast between a pointer and an integer, a pointer difference, and a function returning a pointer. poc/03-matcher/rules.nix has a row for none of them, so such a program compiles to IR that diffs clean against lcc and is then refused at instruction selection, loudly and by name.

What makes this worth its own task rather than a footnote: 'p == 0' is not an exotic form. It is how every C program written before nullptr tests a pointer, and the frontend reaches it through int -> unsigned -> pointer with a fold at each step (see poc/07-parser/c/ptrs.c's 'nulls').

The rows are cheap -- a pointer is four bytes and so is an unsigned int on this target, so CVUP4 and CVPU4 are register moves at most and CNSTP4 is the CNSTU4 template. SUBP4 is 'sub'. What is NOT cheap is the lesson task-051 paid for: a rule the corpus never SELECTS is asserted by nothing. Each row needs a case in poc/03-matcher/ir/ that makes the matcher choose it, and an execution answer that moves if the wrong instruction is emitted.

poc/07-parser/cases.nix's opcode list names all five and says they are unreachable in the backend; that comment is where this task is referenced from.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every opcode poc/07-parser's corpus emits has a rule in poc/03-matcher/rules.nix, or a named reason why not
- [x] #2 Each new row is SELECTED by a case in poc/03-matcher/ir/, not merely named in a table
- [x] #3 A C program that compares a pointer against zero compiles from .c and runs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PLAN (implementer).

SIX ROWS, not five: CNSTP4 needs two, for the same reason CNSTU4 does. lcc's
sym.c prints a pointer constant with %p, which writes the `0x' only when the
value is not null, so the null pointer constant arrives as `0' and everything
else arrives as hex -- and emit.nix's `constValue' parses decimal only, so the
range predicate can never match a non-null one.

  reg_zerop       CNSTP4 in [0,0] -> the zero register, at cost 0
  reg_cnstp_wide  every other CNSTP4 -> `li %c,%a', hex and all
  reg_cvpu4_4     CVPU4 at source width 4 -> `mv'
  reg_cvup4_4     CVUP4 at source width 4 -> `mv'
  reg_subp        SUBP4 -> `sub'  (pointer minus INTEGER, which is not the
                  SUBU4 a pointer DIFFERENCE lowers to)
  stmt_retp       RETP4 -> `mv a0,%0' + `j %E'

CALLP4 still gets no row, deliberately. Nothing in poc/07-parser's corpus
emits it, and run.sh's mutation "a call rule is added to the table and
forgotten everywhere else" adds a CALLP4 row PRECISELY because there is none.

THE CORPUS CASE. poc/03-matcher/ir/ptr.c, with drivers/ptr.s and drivers/ptr.c.
Task-053's census is what forces each of the six to be SELECTED there rather
than only named, and it now also forces `stmt_argp', which has had a row since
task-025 and no case that ever chose it.

What makes the answer move, which a file of pointer expressions does not get
for free:

  * the three null tests DISAGREE -- z == 0 true, p == 0 false, q != 0 true --
    and they add 1000, 2000 and 300. A null comparison that is always false
    discriminates nothing.
  * p - q is 2, not 0. A pointer difference of zero is the pointer version of
    ir/unsig.c's divisor of 7.
  * tag[] holds eight different bytes, so a pointer off by one element reads a
    different number rather than the same one twice.
  * TWO INDEPENDENT ANSWERS ADDED: a global `hold' carries the whole integer
    computation and the RETURNED pointer carries only `n + 4', so a defect in
    the arithmetic cannot cancel against a defect in the return.

RETP4's executed witness is this case and not a program under
poc/07-parser/run/: calling a pointer-returning function is CALLP4, which has
no rule, so only a hand-written assembly caller can reach it. The run/ program
covers criterion #3 -- a pointer compared against zero, compiled from .c and
run -- plus the difference and both casts.

WHERE THE HOST ORACLE CONSTRAINS THE C. drivers/*.c are compiled by the host
gcc as an independent oracle and the host is 64-bit, so a pointer cast to
`unsigned' and back is truncated and segfaults there. Measured, not guessed --
the first version of ir/ptr.c did exactly that. So the CVUP4 pointer is never
dereferenced: it is built from a small unsigned and read back as an int.

DONE. What landed, and what it measures.

SIX ROWS, not five: CNSTP4 needs two. lcc's sym.c prints a pointer constant
with %p, and that is lcc's OWN %p -- output.c's vfprint, not the C library's --
which writes the 0x only when the pointer is not null. So the null pointer
constant arrives as `0' and every other one arrives as hex, which emit.nix's
decimal-only constValue cannot read. Checked two levels down in lcc's source
and against ir/ptr.sym, which holds `CNSTP4 0' and `CNSTP4 0x186a0'.

  reg_zerop       CNSTP4 in [0,0] -> the zero register, at cost 0
  reg_cnstp_wide  every other CNSTP4 -> `li %c,%a', hex and all
  reg_cvpu4_4     CVPU4 at source width 4 -> `mv'
  reg_cvup4_4     CVUP4 at source width 4 -> `mv'
  reg_subp        SUBP4 -> `sub'
  stmt_retp       RETP4 -> `mv a0,%0' + `j %E'

Every opcode poc/07-parser's corpus emits now has a row: checked by evaluating
the two tables against each other rather than by reading them. 113 rules,
106 of which the corpus REDUCES, 7 declared -- stmt_argp left that list, which
is what taking a row out of it looks like.

THE CORPUS CASE. poc/03-matcher/ir/ptr.c with drivers/ptr.s and drivers/ptr.c,
returning 103398 in 117 instructions, host compiler agreeing. It reaches all
six rows and stmt_argp, which has had a row since task-025 and no case that
ever selected it.

WHAT MAKES THE ANSWER MOVE, which is the part a file of pointer expressions
does not get for free:

  * the three null tests DISAGREE -- z == 0 true, p == 0 false, q != 0 true --
    and add 1000, 2000 and 300;
  * p - q is 2, not 0;
  * tag[] holds eight different bytes, so a pointer off by one element reads a
    different number;
  * `hold' carries the whole integer computation and the RETURNED pointer
    carries only `n + 4', so a defect in the arithmetic cannot cancel against
    a defect in the return.

THE ONE THING REVIEW FOUND THAT THE FIRST VERSION GOT WRONG, and it is the
lesson this task was supposed to be about. reg_cvup4_4 was SELECTED and
asserted by nothing at all. Its template is `mv %c,%0', a one-kid node is
reduced at the same DEPTH as its kid, so with a single use the destination and
the source are the same register: replacing the template with `mv %c,%c' left
ptr.s BYTE-IDENTICAL, check.nix passed clean, and run/pointers.c printed the
same string with the same step count. The row was pinned by nothing but its
mnemonic in `lowerings' -- exactly the state task-051's five U-typed rows were
in, one task after the census that exists to catch it.

Fixed by casting the same value back to a pointer TWICE, so lcc shares the
node, the matcher HOLDS it in a common-subexpression register, and the move
finally has a destination different from its source. Measured after: with
reg_cvup4_4 alone reduced to `mv %c,%c' the program returns 101392 against
103398. The offset is 1000 rather than 4 so that the value the rule carries is
not one a stale register is likely to hold already.

The same review found that reg_zerop has a wrong-but-plausible edit that
leaves the answer intact -- `zero' -> `x0' assembles to the same word -- and
that widening its range to [0 1] changes nothing a corpus can see. The second
is not a gap: constValue cannot read a hex spelling, so no non-null pointer
constant can ever match a range, and the same edit to reg_zerou WOULD be wrong
because lcc prints an unsigned 1 in decimal. That asymmetry is now written in
rules.nix beside the row.

FOUR NEW MUTATIONS, 58 -> 62, each detected with its own distinct failure:

  matcher: a pointer minus an integer becomes an addition   (lowerings)
  matcher: the null pointer constant is materialised
           instead of read out of x0                        (selections)
  matcher: a returned pointer is left in the wrong register (emitted)
  matcher: the pointer conversions keep whatever was in
           the destination                                  (EXECUTION only)

The last carries its own control, in front of its claim: check.nix must PASS
it for it to demonstrate anything, and it does -- measured, 4294929692 for
reg_cvpu4_4 alone and 101392 for reg_cvup4_4 alone, both against 103398.

poc/07-parser/run/pointers.c is criterion #3: a pointer compared against zero,
compiled from .c and run, printing deabcd419d. It searches a buffer with a
pointer, so the null test is taken once and not taken once -- a null test that
always answers the same way discriminates nothing. Its expected output is a
second implementation in Nix over the same argument, and the `miss' digit is
DERIVED from the same alphabet rather than written as 1. One new mutation there
(57 total) stops that walk and the expectation stops describing anything.

RETP4 IS NOT REACHED FROM run/, and cannot be: calling a pointer-returning
function is CALLP4, which rules.nix deliberately has no row for -- run.sh's
mutation "a call rule is added to the table and forgotten everywhere else"
adds one precisely because there is none. So RETP4's executed witness is
ir/ptr.c, whose caller is hand-written assembly. Filed as task-057.

WHERE THE HOST ORACLE CONSTRAINS THE C, because it is the one place the test
is shaped by something other than the target. drivers/*.c are compiled by the
host gcc as an independent answer and the host is 64-bit, so `(unsigned) p'
truncates a pointer and casting back produces a different address. Measured,
not guessed -- the first version of ir/ptr.c segfaulted the oracle. So `u' is
a pointer DIFFERENCE, small on any target, and the pointer built back out of
it is only ever read as an integer. run.sh's `-w' hides the two warnings that
would have named that, and cannot drop them, because the casts are the thing
under test; what makes them safe is that discipline, and what enforces it is
that the oracle is RUN. Both are written down now rather than left to be
rediscovered.

ONE FLOOR REMOVED, and it is a judgement worth overruling if you disagree.
task-053 added `minReduced', a floor on how many rows the corpus reduces. With
minFunctions and minNodes now at the actual, the erosion it was aimed at is
refused three guards earlier and no edit can reach its arm of the chain -- a
check nothing can make fail. What stands in its place is arithmetic: the
census asserts rules reduced plus rows declared equals rows in the table, and
every declared row must name a rule genuinely not reduced and carry a reason,
so the count can only fall by adding a visible, checked row. My first written
reason for the removal was wrong ("it cannot be made to fail" -- it can, if it
is raised to the actual), review caught that, and the real one is in check.nix
beside minWhy.

FLOORS RAISED to the new actuals: minFunctions 15, minNodes 758,
minSelections 95, minRules 113, minRequiredOps 76, minLowerings 49,
minAssertions 160. poc/07-parser/oracle.py's declared counts 58 -> 59
functions, 1540 -> 1781 node lines, 1315 -> 1519 back-references; each delta
is exactly what rcc-rv32 prints for run/pointers.c alone, counted with
oracle.py's own regexes.

GATE: nix develop --command just e2e, green. 7 PoCs; matcher mutation count
53 -> 62 across both tasks, parser 56 -> 57.
<!-- SECTION:NOTES:END -->
