---
id: TASK-028
title: 'Slice 2: char, byte loads and stores, and string literals'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-16 00:13'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-024
  - TASK-027
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Second vertical slice per decision-007. Depends on the backend gaining byte load/store rules (task-024), which is why that comes first.

This is the slice that makes string handling real. Note decision-001: Nix strings cannot hold NUL, so a decoded C string literal must be a byte list throughout -- this is also why the closed loop works at all.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 char declarations, byte loads and stores, and string literals parse and reach the DAG
- [ ] #2 String literals are byte lists end to end; a literal containing an embedded NUL survives compilation and execution
- [ ] #3 A C program using char arrays and string literals compiles from .c and runs, printing correct output
- [ ] #4 DAG diffs against rcc-rv32 for the extended corpus
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-024, which this depends on (commit 7de656d).

THE BACKEND IS READY FOR char, AND THE SHAPE MATTERS. poc/03-matcher/rules.nix has lb, lbu, lh, lhu, sb and sh, the conversions lcc wraps every narrow access in, and CNSTI1. poc/03-matcher/ir/chars.c is the worked example: it reads the same bytes signed and unsigned, stores back through every width, and returns 1649 with gcc agreeing.

WHAT WILL BITE YOU FIRST, and it is not char. lcc folds a string literal's subscript into a symbol expression over a COMPILER-GENERATED numeric base:

    int f(void) { return "abcdefgh"[4]; }
      ->  4. ADDRGP4 2+4

poc/03-matcher/emit.nix's `isLabelName' is `match "[0-9]+"', which does not recognise "2+4", so it passes the symbol through unmangled and poc/04-assembler refuses it -- the numeric label was renamed to .Lnum_<k>_<i> at layout time, so the base `2' is undefined. Loud, not silent, but it is the spelling EVERY string literal produces. Filed as task-032 and it is squarely in this slice's path. Do it first or you will hit it on your first literal.

STRING LITERALS AND NUL. decision-001 is why this slice exists in the shape it does: Nix strings cannot hold a NUL byte, so a decoded literal must be a byte list from the lexer all the way to .data. poc/05-loop/items.nix's `asciiBytes' is the existing converter and it THROWS on a character it has no code for rather than emitting a zero -- keep that property; a message that silently lost a character would still assemble, run, and print something plausible.

WHAT THE EXECUTION ORACLE CANNOT SEE, which changes how you test this slice. lcc promotes every narrow load, so an INDIRI1 always arrives under a CVII4 whose shift pair re-normalises the register: `lb' and `lbu' leave the same 32 bits and NO C program's answer distinguishes them today. Measured -- the whole rule table with the two exchanged still returns 1649. poc/03-matcher/cases.nix's `lowerings' table is the only thing checking it, against the table rather than a result, and it says so. Two consequences for you: do not write a test whose premise is that the load's sign is observable, and do not delete that table when it looks redundant. It stops being the only witness when task-033 fuses the load and the conversion.

COST OF THE UNFUSED FORM: ir/chars.c compiles to 91 body instructions, of which 23 are extension shifts and masks and 4 are `mv sN,sN' self-moves. Roughly 30% of a char-heavy function is currently waste. task-033 has the measurement and the two ways out, including the trap in the cheaper one (a zero-cost fragment producing the register nonterminal hands its users the register its KID was reduced into, and burg.nix now refuses such a rule outright).

NOT COVERED by the rule table, so expect a refusal: CVUU4 at any width, CVIU4 below width 4. Both are one row each when a case produces them; the conversion block in rules.nix says explicitly that it is a trace of what has been seen and not a specification.

CARRIED FROM THE task-035 / task-034 BATCH, for whoever writes this slice's harness. Four things changed under you, and one of them changes what a number means.

1. A HARNESS IS NOW SANDBOXED, AND IT SETS ITS OWN $work. Source poc/lib/sandbox.sh as the FIRST statement of any new run.sh, before the cd:

       set -euo pipefail
       # shellcheck source-path=SCRIPTDIR source=../lib/sandbox.sh
       . "$(dirname "$(readlink -f "$0")")/../lib/sandbox.sh"
       cd "$(dirname "$0")"

   It re-execs the script inside bubblewrap with a tmpfs over /tmp and leaves $work pointing into it. Do NOT write mktemp -d, a cleanup function or an EXIT trap: there is nothing to delete, and `just no-deletes' fails the lint if you add one. On a failure the scratch is gone; NIXCC_SCRATCH=/some/dir keeps it, and `just poc' says so when a PoC exits non-zero.

2. MUTATIONS GO THROUGH poc/lib/mutant.sh. mutate() hands it the PoC directory, the mutation directory, the sed snippet and the command, and it runs all three inside a nested tmpfs. Copy the mutate() from any existing harness rather than writing a new one. Two things to know: a mutation that changes the INVOCATION rather than the tree must pass "no" as a fifth argument, or it is reported as a pattern that no longer matches; and a shell FUNCTION defined in your run.sh is not in scope inside the mutation's namespace. If a mutation needs one, put it in its own script and call it from inside the mutated tree -- poc/04-assembler/gnu-diff.sh is the worked example, and it is also why: exporting the function instead means the child runs the parent's copy, so that function becomes the one piece of the path a mutation cannot reach.

3. IF YOUR SLICE GETS A LINEARITY LADDER, the numbers mean something different now. Use contention.ladder(nix, poc, paths, repeats), which measures the start-up baseline and every point together, round-robin. A step's cost ratio comes from contention.step_ratio(ladder, base, a, z, what) -- the median of the per-round ratios -- and NOT from dividing two rows of the printed table, which are per-point minima. That is deliberate and decision-008 records why: a CPU second is not a stable unit on this machine (P-cores, E-cores and LP-E cores differ by up to 2.2x for identical work, and the P-cores lose 35% of their clock once warm), so any ladder that walks its points in size order measures its largest one last on the hottest machine, every time. Four gate runs and five diagnoses were lost to that.

4. ANY THROUGHPUT FIGURE QUOTED IN A TASK NOTE OLDER THAN decision-008 WAS MEASURED WITH THE OLD ORDER and is biased against the top of the ladder. Re-measure before building on one. That specifically includes decision-001's closing paragraph -- "2.2 MB costs 976 MB and takes 18.3 s where the small-file rate predicts 14.5" -- which is the figure two investigations in task-035 reached for as an explanation and which may itself carry the same confound.

AND THE THING THAT WILL COST YOU TIME IF NOBODY TELLS YOU: on this machine roughly one gate run in three is currently lost to the contention self-test, which differences two readings taken seconds apart and declares itself broken when the background load moves between them. That is task-039. It is not your slice failing. Read the message: "SELF-TEST FAILED: N busy cores read as M" or "only X of this machine's 14 cores are free" both mean re-run, not debug.

CARRIED FORWARD from the task-039/040/041 batch. This slice writes a new harness against plumbing that moved under it, so read this before copying an existing run.sh.

1. COPY THE DECLARED COUNT AS WELL AS mutate(). The plan below says to copy mutate() from an existing harness. That is still right, but mutate() is not the whole of what a mutation stage now needs: after the distinctness loop every harness declares how many mutations it has and checks EQUALITY, not a floor --

     declared=36
     [ "${#names[@]}" -eq "$declared" ] || { ...; exit 1; }

   A floor at the exact count only catches mutations going missing, and the drift that actually happens here is mutations being ADDED while the number is left behind: that is how poc/05-loop ended up declaring 34 while 36 ran. poc/lib/mutant.sh's header has the reasoning. Copying mutate() and forgetting this is the specific failure task-044 exists to make impossible; until 044 lands, nothing will remind you.

2. AN ORACLE THAT INTERLEAVES WITH THE HARNESS BELONGS IN ITS OWN SCRIPT. A shell function defined in run.sh is out of scope inside the mount namespace each mutation runs in, so anything a mutation must be able to REACH has to be a file under the PoC directory, called from the mutated tree. poc/03-matcher/build-and-run.sh and poc/04-assembler/gnu-diff.sh are the two worked examples. Take the output directory as an argument rather than writing under the tree: during a mutation the tree is a tmpfs and either would do, but the main stage passes the real PoC directory and must not write into it.

   And aim a mutation at the script itself. Both examples now have one. Without it, "the mutated copy is what runs" is argued rather than shown, and that was true of build-and-run.sh for the whole of task-041 until review said so.

3. A RUN SNIPPET THAT CHECKS A CONTROL MUST PUT IT IN FRONT AND EXIT 9. mutate() treats any unreserved non-zero status as "detected", so a snippet whose control has gone would otherwise be recorded as the strongest result the harness has for its weakest reason. poc/03-matcher/run.sh's mutate() has a 9) arm that names it; copy that arm if your snippet has a control. Keep the underlying tool's own stderr and print it -- "check.nix caught it" and "check.nix is broken" are different things and nothing else can tell them apart.

4. THE CONTENTION SELF-TEST HAS THREE OUTCOMES NOW, NOT TWO. poc/lib/selftest.py can exit 3 -- the machine would not hold still long enough for its probe to mean anything. Do not call it directly. Source poc/lib/selftest.sh and use nixcc_selftest and nixcc_selftest_verdict, which is where the policy lives: exit 3 is carried to the harness's LAST line, where it downgrades a ladder PASS and nothing else. It must not downgrade a ladder FAIL -- `just poc' reports a refusal with the words "Every other check in them passed", which a downgraded FAIL would make false.

5. TIMING NUMBERS. Everything decision-008 says still holds and nothing in this batch touched it. What this batch adds is that the SELF-TEST's own readings are bracketed and retaken, so a number it prints is the last of up to three attempts. If you quote one, quote the line and not the figure.

6. STILL OPEN AND RELEVANT TO YOU: task-042 (a machine with fewer than six free cores makes the self-test a HARNESS FAULT, exit 2, red -- so a busy machine can still redden a gate for a reason that is not a defect), task-043 (the guard stage's copies are single-use directories rather than tmpfs), task-044 (mutate() copied four times), task-045 (`just poc' and the guard stages still print counts nobody asserts).

FORWARD-CARRIED from task-011 (commit 35844a3). String literals now have a decoded form: `(import ../06-constants/const.nix).evalSCON lexeme' returns { units; width; warnings; }.

THE PART THAT BEARS DIRECTLY ON THIS SLICE. `units' is a list of integers and NOT a Nix string, because a Nix string cannot hold a NUL byte (decision-001) and `"a\0b"' is a perfectly good C literal. It is also the form the emitter wants. `width' is bytes per unit: 1 for a narrow literal, 2 for a wide one (widechar is unsignedshort on this target), so a wide literal is not a byte list and laying it out needs the endianness the assembler already has.

THERE IS NO TERMINATING NUL IN `units'. Adjacent literals are joined by the PARSER, which then appends ONE 0 -- lcc's scon() does the same thing in the same order. So the array type's length is (joined units) + 1, and an emitter that terminates each literal separately will lay out `char s[] = "ab" "cd";' as six bytes instead of five.

Verified against lcc's defstring for 17 string forms including an embedded NUL, escapes above 127, and wide literals; see poc/06-constants/oracle.py.

A literal containing a source byte above 127 currently throws (task-046). \xNN and \NNN reach every byte, so it constrains the corpus rather than the feature.

Mixed-width joins -- `"ab" L"cd"' -- have no rule yet and no case: task-047. Everything else about the join is settled in task-011's notes.

FORWARD-CARRIED from task-027 (slice 1), commits d64d382 and 9330404. The frontend exists: poc/07-parser/ is lcc's frontend middle-end ported file by file, and its listing diffs against rcc-rv32 BYTE FOR BYTE over 24 translation units, 41 functions and 843 generated programs. Read this before adding anything.

WHAT ALREADY WORKS THAT SLICE 2 IS NOMINALLY ABOUT. `char' and `short' locals, parameters and conversions compile and diff clean TODAY, and so do pointer LOCALS, unary `&', unary `*', function pointers through a typedef, `static' functions, `const' and `volatile' (including the newnode-not-node rule that keeps two volatile loads two nodes), and array TYPES. Slice 1 refuses only: subscripting, pointer ARITHMETIC (simp.c's ADD+P/SUB+P, where addrtree lives), string literals, structs/unions/enums, float, switch/goto/labels, globals and local statics. So slice 2 is smaller than it looks -- it is the STRING LITERAL and the SUBSCRIPT, not `char'.

WHERE TO PUT WHAT.
  * String literals: poc/07-parser/parse.nix's `primary', the SCON arm, which currently refuses naming task-028. task-011's evalSCON gives you { units; width; warnings; }; the PARSER joins adjacent literals and appends ONE 0, and poc/06-constants/oracle.nix's `answerFor' holds the one-literal special case of that rule -- when you write the general one there will be two copies and only yours will be on the critical path. Mixed-width joins have no rule anywhere: task-047.
  * Subscripting: `postfix''s `[' arm. lcc's is four lines and calls (*optree['+'])(ADD, pointer(p), pointer(q)) -- the work is all in enode.c's addtree, which poc/07-parser/trees.nix refuses for the pointer case.
  * Pointer arithmetic: simp.nix's "ADD+P" and "SUB+P", both of which throw today naming this task. simp.c's addrtree is the interesting one; it allocates a generated symbol and emits an Address code item, which listing.nix's gencode does not handle (it throws on an unknown code kind, deliberately, so you will see it).

TWO THINGS THAT WILL BITE.
  * task-051: the backend has no rule for BANDI4, BORI4, BXORI4, NEGI4, BCOMI4 or ANY unsigned arithmetic. The frontend emits all of them correctly. A string program using `&' or `|' will compile to correct IR and be refused at instruction selection.
  * task-046: poc/06-constants throws on a literal byte above 127, so a corpus with UTF-8 in a string literal stops you.

HOW TO ADD A CASE. poc/07-parser/cases.nix DERIVES its corpus from the c/ directory and requires an entry in `notes' for every file; poc/07-parser/oracle.py declares the function, node-line, back-reference and diagnostic counts and checks them for EQUALITY, so adding a file means updating five numbers. That friction is deliberate -- it is where you look at what the new case brought.

CARRIED FROM TASK-051 (the bitwise, unary and unsigned rule gap).

The rule table is no longer the thing that stops a program running. poc/03-matcher/rules.nix now covers the bitwise and unary opcodes and the whole U-typed family, __udivsi3/__umodsi3 exist in runtime.s, and five programs compile from .c and execute. If this slice's C is refused, the refusal is about the FRONTEND or about a genuinely absent row -- it is no longer the backend having no rules for ordinary integer C.

WHAT TO EXPECT TO ADD ANYWAY. The table covers what the corpus emits and nothing more, and that is a trace rather than a specification. Absent today and a loud refusal naming the opcode: CVUU4, CVIU4 below width 4, CALLP4, CALLD4, and a NEGU4 that lcc never emits (its ops.h gives NEG only the I and F kinds, so -u arrives as BCOMU4 then ADDU4 of 1 -- checked against rcc-rv32, not inferred). Add rows; do not assume the absence is deliberate design.

THE LESSON THAT COST THE MOST, and it applies to any rule this slice adds. A rule the corpus never SELECTS is asserted by nothing, however many tables name it. cases.nix's lowerings and libcalls tables check the template of a NAMED rule and never that the matcher chooses it, so five U-typed rows shipped that could be changed to the wrong instruction with the whole suite green -- reg_rshu_reg among them, where sra for srl is the exact defect the slice existed to prevent. Two reviews found it; I had not. Walk the label tables and subtract the rules that fired from the rules that exist. task-053 is that check, unwritten.

AND THE ONE THAT COST THE SECOND MOST: a test case's ARGUMENTS are part of the test. ir/unsig.c with a divisor of 7 returned the same number whether the unsigned divide called __udivsi3 or __divsi3, because a later mask carried the difference away; ir/udiv.c combined its two halves with + and the two errors cancelled exactly modulo 2^32. Both found by running the mutation and watching the exit code not move. Run your mutations before believing your corpus discriminates.

For slice 2 specifically: the narrow load and store rules (task-024) are in and executed, and the signed/unsigned load pair is still INVISIBLE to any executed answer because lcc promotes every narrow access -- cases.nix's lowerings table is what tells lb from lbu, and task-033 is what would make it observable.

For slice 3: ADDRGP4 sym+N is taken verbatim by the rule table and resolved by poc/04-assembler at layout time (task-023), so the matcher's only job there is not to lose the displacement. ir/gsym.c pins that.
<!-- SECTION:NOTES:END -->
