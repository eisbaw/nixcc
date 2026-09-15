---
id: TASK-005
title: 'Re-plan: choose the frontend strategy from PoC evidence'
status: Done
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-15 04:41'
labels:
  - planning
  - wave-boundary
dependencies:
  - TASK-002
  - TASK-003
  - TASK-004
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wave boundary. The PoCs exist to answer questions that change the plan, so the plan is not written until they have answered.

The open decision is whether to port lcc's full C89 frontend before anything runs (the chosen milestone), or to grow the compiler feature by feature. The risk with full-frontend-first is that nothing runs until a great deal works; the mitigation already in place is that lcc's own rcc -target=symbolic dumps numbered DAG nodes, so our frontend is diffable against real lcc node by node with no backend written at all.

PoC-2 throughput is the main input. If Nix is fast enough, full-frontend-first is safe. If not, say so plainly and file the alternative instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Compile-time estimate for a 1000-line C file recorded, derived from PoC-2 measurements
- [x] #2 Explicit go/no-go on the full-C89-frontend-first strategy, with the evidence that decided it
- [x] #3 If go: the frontend port is filed as tasks decomposed along lcc's module boundaries (lex, decl, expr, stmt, types, dag, simp, gen)
- [ ] #4 If no-go: the alternative strategy is filed as tasks instead, and the reason full-frontend-first was rejected is written down
- [x] #5 Differential harness against 'rcc -target=symbolic' is filed or built, since it gates every frontend task
- [x] #6 Decision recorded in backlog as a decision entry, not only in a task note
- [x] #7 Go/no-go weighs all four inputs, not throughput alone: oracle fidelity, accumulator linearity, the plan for lcc/cpp, and the plan for gen.c/dag.c/simp.c which are rewrites rather than ports
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: the lexer PoC answered its kill question with a yes, and the evidence is in task-002's notes -- 47000 tokens/s, linear from 31 kB to 431 kB, a 1143-line file in 0.25 s and 82 MB. Throughput is not the constraint on the frontend strategy.

Memory is. Peak RSS runs about 4 kB per token: 82 MB at 1143 lines, 501 MB at 16720, 976 MB for a 2.2 MB input. A strategy that keeps tokens, an AST and a DAG live at once multiplies that, and an attempt to localise the cost failed -- it is the evaluator's per-value overhead, not one fixable field. Cost the frontend in live values, not in seconds.

Two things the lexer deliberately does NOT do, both of which land on whatever this task chooses:
- No constant VALUES, only classified lexemes (task-011). lcc computes them inside gettok; in Nix, integer overflow throws rather than wrapping and strings cannot hold NUL, so neither lcc's overflow detection nor its string decoding transliterates.
- No column numbers, and no 'file' (task-012). lcc threads a full Coordinate through every error, every DAG node and the symbolic IR the oracle emits, so a line-only token will not survive contact with the oracle diff.

One shape decision is already made and is hard to reverse later: the token set is lcc's, which has NO compound-assignment tokens -- '<<=' is LSHIFT then '=', and lcc's parser disambiguates by peeking at the raw next character. Tokens record their preceding trivia so a parser can make the same peek via ws == "". A frontend strategy that wants '<<=' as one token has to change the lexer, not work around it.

forward-carried from task-003: the lburg kill-risk resolved in favour of lcc. Declarative bottom-up matching works well in Nix -- the DP label table is a self-referential listToAttrs that laziness resolves in dependency order, measured linear at ~24000 DAG nodes/s over an 8x ladder of real lcc output. The rule table is 44 rows of pure data and the matcher that consumes it knows nothing about RISC-V. decision-002's argument stands.

The number that should shape this re-plan is memory, not speed: 9.9-16.7 kB of peak RSS per DAG node for parse+label, roughly 2.5x the lexer's 4 kB/token, so ~220 MB for a 20000-node listing. A frontend that holds an AST and a DAG and a label table live at once is where that multiplies.

forward-carried from task-003, correcting the memory figure in the earlier note: 8.4-8.7 kB of peak RSS per DAG node NET of the nix evaluator's own ~36 MB, flat across an 8x ladder. The 9.9-16.7 range quoted before was gross, and the apparent improvement with size was just that constant amortising. Roughly twice the lexer's 4 kB per token.

forward-carried from task-020: the two timing ladders now render THREE outcomes, not two. Exit 0 is a verdict that the implementation is linear, exit 1 a verdict that it is not, exit 3 'the machine was too busy for this measurement to mean anything' -- printed as NO VERDICT with the per-point contention that caused it. A re-plan reading these must not count a NO VERDICT as either; it is an absent measurement, and the fix for it is a re-run on a quiet machine rather than a decision.

What the ladders actually say as of 2a6707e, measured ten times running against 2.10 to 3.45 cores of other work: the lexer is linear across a 13.9x span (31 kB to 431 kB, every adjacent step within 1.35x and end-to-end within 1.5x, ~44000 tokens/s, 501 MB peak at the top), and the matcher's labeller is linear across 8.1x (5050 to 40653 DAG nodes, ~21000 nodes/s, 9.3-9.6 kB per node net of the evaluator's own 36 MB). Both verdicts are now only rendered on a machine measured quiet enough to give them, which is the difference from the numbers task-003 closed with.

Practical cost to budget for: on a machine that idles around 2 cores and bursts past 4 -- which this one does when other projects are running -- roughly one gate run in three refuses rather than reports. Six consecutive runs earlier the same evening went four green and two NO VERDICT. Re-running is the answer; raising the threshold is not, and the module says why (the distortion is already 1.19 of a 1.35 tolerance at 4.1 cores, and 1.36 at 6.4).

Two things a re-plan may want to schedule. First, 'just e2e' went from about 2 minutes to 4m17, nearly all of it the four cases that prove the guard refuses in both directions, each of which runs a real ladder. Extracting a pure judge(rows, quiet, tolerances) from the ladders would make those cases synthetic and near-instant; it is a refactor of both ladders rather than a fix, so it was left. Second, there is still no Python linter in the dev shell -- statix, deadnix and shellcheck cover Nix and shell, and nothing covers the four .py files that now decide whether this architecture is linear.

Known hole, recorded in poc/lib/contention.py rather than hidden: iowait counts as idle, so a machine saturating the memory bus through writeback reads quiet and gets a verdict it should not.

forward-carried from task-004: THE LOOP IS CLOSED FROM lcc IR DOWNWARD, AND
ONLY FROM THERE. `just poc-loop' compiles poc/05-loop/hello.c, assembles it and
RUNS it on nix-riscv's RV32I machine inside a single `nix eval' whose PATH
holds exactly one binary -- nix itself -- and the program prints `1..10 = 55'
through the write syscall and exits 0 through the exit syscall. 711
instructions, 648-byte image.

The entry point of that eval is hello.sym, lcc's IR listing, NOT hello.c. That
is the gap this re-plan has to cost, and it is now the only one: everything
from the IR to the program's output is Nix, with no external toolchain
anywhere in it. What is missing between .c and .sym is the preprocessor
(task-013), the parser and the DAG builder -- the lexer already exists.

WHAT THE DEMO COSTS, which is the number this re-plan should weigh:
  0.06-0.10 s CPU and 30 MB net of the evaluator's own 36 MB, for compiling
  one function, assembling 648 bytes and executing 711 instructions. That is
  AT MOST 43.5 kB of peak RSS per emulated instruction -- at most, because the
  same figure also carries the selection and the assembly. Compare 4 kB/token
  lexing, 8.5 kB/DAG node matching, 8.6 kB/item assembling.

  Execution is therefore by far the most expensive stage per unit, and it is
  the stage whose unit count is the RUNTIME of the compiled program, not its
  size. A test suite that runs its cases in-Nix pays per executed instruction.
  poc/05-loop's own 19 programs together cost 0.16 s CPU and 74 MB, so this is
  affordable at PoC scale and is not obviously affordable for tinycc's 139
  cases if any of them loop much.

THE DECISION TASK-006 LEFT HERE, now with evidence. emit.nix still produces
assembly TEXT which parse.nix immediately reads back into items. poc/05-loop
has both paths side by side: its driver and all nineteen fault programs are
built as items in Nix and handed straight to asm.nix, and the compiled
function goes through text. Filed as task-026 with what has to be decided --
keeping rules.nix declarative is the constraint, not the mechanics. It was NOT
done here: it is a change to poc/03-matcher's rule table shape, and task-004's
job was to show the loop closes.

THREE MATCHER GAPS FOUND BY WRITING ONE SMALL C PROGRAM, all refusals rather
than miscompiles, all now tasks: a global at a constant offset (task-023), any
byte-sized load or store, i.e. char (task-024), and a call whose int result is
discarded (task-025). hello.c had to be written around all three. That ratio
-- three gaps in forty lines of ordinary C -- is itself evidence about how
much of C89 the rule table currently covers, and worth weighing against the
frontend work: a frontend that parses all of C89 in front of a back end that
cannot store a char does not compile more programs.

forward-carried from task-004's review round: the HARNESS BAR moved, and a
re-plan that schedules new PoCs should budget for it.

Two reviewers ran against task-004's first draft and found that eleven guards
in its check.nix could be deleted, and four of its tables emptied, while the
mutation stage still reported every mutation detected. The suite was not
wrong; it was under-aimed. Mutation-testing the CODE is not the same as
mutating every GUARD, and this project's recurring failure has now appeared at
both levels.

What that cost, and what it is worth budgeting: 17 mutations became 31, and
the rule that produced them is cheap to state -- a guard with no mutation
aimed at it is a guard nobody has seen fail, and a table with no floor is a
table that can be emptied. Both are mechanical to check once someone thinks to.

Two smaller findings with wider reach:
  * A pin written BESIDE the fact it describes rather than derived FROM it
    turns a correct program into a false failure, with a message that still
    quotes the stale value. task-004's demo now derives its expected output
    from its input vector.
  * A floor evaluated before the thing it guards can pre-empt a better
    diagnostic. An item-count floor fired before the image was forced, so a
    demo missing a whole unit reported "fewer items than expected" instead of
    the assembler's own "nothing in this unit defines `__divsi3'". Order
    floors by what they can PRE-EMPT, not only by what they protect.

ORCHESTRATOR, closing the wave boundary.

AC#1, the compile-time estimate for a 1000-line C file. This is an EXTRAPOLATION from measured per-stage costs, not a measurement, and the assumption it rests on is stated because it is the one that could be wrong: that all four stages hold their values live simultaneously. If they can be streamed, the memory figure drops; nothing has yet demonstrated they can.

Measured inputs: lexer 4 kB/token at 47000 tokens/s (1143 lines = 10222 tokens, 82 MB, 0.29 s); matcher 8.5 kB/DAG node at ~21000 nodes/s; assembler 8.5 kB/item at ~20000 items/s. All net of the evaluator's own 36 MB.

For 1000 lines: roughly 9000 tokens, somewhere near 5000-10000 DAG nodes, and 10000-20000 assembler items. Time is not the problem -- the measured stages sum to around 2 seconds, with the parser unmeasured because it does not exist. Memory lands somewhere around 250-400 MB with everything live. Both are comfortably inside the 10 s / 2 GB thresholds task-002 pre-committed to.

The honest caveat: the parser and DAG builder are the two stages with no measurement at all, and they are exactly the stages that hold the most structure live. The estimate should be re-derived after slice 1 rather than trusted.

AC#2, the go/no-go. Full-frontend-first is REJECTED, and the evidence that decided it was not available when the milestone was chosen. Writing forty lines of ordinary C for the closed-loop demo hit three backend refusals: a global at a constant offset, any byte load or store, and a discarded call result. A complete C89 frontend would emit IR the rule table refuses today. The decision is recorded as decision-007 and the user chose it after seeing the evidence.

AC#4 is not applicable and is left unchecked rather than ticked: it covers the no-go branch, and this was a no-go on the strategy, not on the project. The tasks filed are slices, not an alternative strategy.

Gate tier: this was orchestrator planning work, not an implementer cycle. Nothing was gated because nothing was implemented.

One thing this re-plan should NOT paper over: task-020's forward-carried note is right that a NO VERDICT is an absent measurement rather than a result. Two of the runs behind these numbers were NO VERDICT, and one was a genuine SUPERLINEAR on 02-lexer at 2.64 cores of foreign load -- under the guard's 3.50 threshold, so it rendered a verdict it arguably should not have. That is the iowait hole the module records. The linearity claims here are sound but not unqualified.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Wave boundary closed. Full-frontend-first rejected on measured evidence; frontend and backend now grow together in vertical slices, each ending with real C compiling and running. Recorded as decision-007, filed as tasks 027-029 with the three backend gaps (023-025) promoted ahead of them because without char there is no string handling worth the name.
<!-- SECTION:FINAL_SUMMARY:END -->
