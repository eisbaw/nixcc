---
id: TASK-003
title: 'PoC-3: lburg-style bottom-up tree matcher for RV32'
status: Done
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 21:53'
labels:
  - poc
  - backend
  - codegen
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement instruction selection as lcc does it: rules as declarative data, matched bottom-up over the DAG with dynamic programming, then reduced to emit instructions.

Kill-risk: this is the single thing that made us pick lcc over tcc. An lburg rule is (nonterminal, tree pattern, cost, template), e.g. `base: ADDI4(reg,acon) "%1(%0)"`. If declarative tree matching does not work well in Nix, the choice of lcc was wrong and we should reconsider before porting 10k lines against it.

Does not need the full rule set. A handful of rules that prove labeling, cost-driven choice, and reduction is enough.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Rules are data (nonterminal, pattern, cost, template), not hand-written emission code
- [x] #2 Bottom-up labeling assigns each DAG node a cost and winning rule per nonterminal
- [x] #3 Reduction walks the labels and emits RV32 assembly
- [x] #4 Covers at least CNSTI4, ADDRLP4, ADDRGP4, INDIRI4, ASGNI4, ADDI4, SUBI4, LSHI4, CALLI4, RETI4 and one conditional branch
- [x] #5 At least one test where two rules match the same subtree and the cheaper one demonstrably wins
- [x] #6 Emitted assembly for a hand-built DAG assembles cleanly with riscv32-none-elf-as
- [x] #7 The hand-built DAG is taken from real lcc output ('just ir') for a small C function, not invented
- [x] #8 Runnable as 'just poc-matcher'
- [x] #9 Covers MULI4 and DIVI4 as libcalls, not patterns: RV32I has no multiplier, so these lower to __mulsi3/__divsi3 calls (see decision-003)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Get real lcc IR via rcc-rv32 for a small C function covering the required opcodes.
2. Write poc/03-matcher/rules.nix: lburg rules as pure data (nonterminal, op, kids, cost, template).
3. Write poc/03-matcher/match.nix: bottom-up labeller (DP over DAG) + reducer emitting RV32 asm.
4. Write poc/03-matcher/dag.nix: the real-lcc-derived DAG, plus a parser from 'rcc-rv32' symbolic output so the DAG is provably not invented.
5. Harness poc/03-matcher/run.sh: check.nix table, must-fail.nix with controls, messages.sh, GNU as differential assembly, mutation test of both matcher and harness.
6. Justfile poc-matcher recipe; wire into flake checks; full 'just e2e' gate before each commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forward-carried from task-002: the loop shape is settled, use it rather than rediscovering it.

A pass that walks a sequence and EMITS one value per step is builtins.genericClosure, not foldl'. foldl' carries a scalar accumulator and cannot emit; acc ++ [x] is quadratic (decision-001); a self-referential genList has depth n. genericClosure is an iterative worklist in the evaluator, measured linear at constant stack depth: 0.07/0.11/0.18/0.35/0.49 s at 25000/50000/100000/200000/400000 steps. Its keys must be unique -- it silently DROPS duplicates -- and it forces only 'key', so the operator must deepSeq the item it returns or the unforced field chain grows as deep as the loop and dies with 'stack overflow (possible infinite recursion)'. Not slowly: at 100000 steps.

A bottom-up tree matcher is mostly recursive descent over an expression tree, whose depth tracks nesting rather than input length, so it is fine. But the labeller walking a whole function's DAG in one pass is exactly the emit-per-step shape above, and lburg's own cost tables are attrsets, which have the same O(size) copy cost as lists: build a rule table once, never by repeated //.

builtins.substring COPIES ITS HAYSTACK. Any pass that cuts text out of a long string once per node is quadratic in the file: 22.68 s against 2.13 s on a 2.2 MB file. Slice out of an exploded character list with concatStringsSep instead; builtins.split "(.)" explodes a string 10x faster than genList+substring.

Cost to expect: the lexer runs at 47000 tokens/s and about 4 kB of peak RSS per token -- 82 MB for 1143 lines, 501 MB for 16720. Memory, not asymptotics, is the budget that will bite a pass that keeps a labelled tree live.

Harness lessons, all earned the hard way: order the guards so a HARNESS FAULT can never pre-empt a real diagnosis; assert the fields nothing else looks at (a lexer reporting 'line 1' for everything passed every test in poc/02-lexer until a reviewer noticed); check what errors SAY, not only that they threw, which needs a shell loop because builtins.tryEval never gives you the message; and mutation-test the measurement code too, not just the code under test.

Implementation landed at poc/03-matcher. Architecture: parse.nix (lcc symbolic listing -> DAG forests), rules.nix (the machine description AS DATA: 44 rules, 5 nonterminals, 28 opcodes, 4 chain rules), burg.nix (generic labeller + reducer, knows nothing about RISC-V), emit.nix (RV32 frame layout and operand naming). Swapping rules.nix aims it at a different machine.

VERDICT ON THE KILL RISK: declarative tree matching is a GOOD fit for Nix, better than expected. The label table -- the dynamic-programming core -- is a SELF-REFERENTIAL builtins.listToAttrs whose entries refer to the entries for their own kids. Nix's laziness resolves it in dependency order for free: no fold, no // accumulator copying the table per node (decision-001's trap), O(1) lookup, and the thunk chain is only as deep as the expression nests. Measured linear over an 8x ladder of real lcc DAGs at ~24000 nodes/s.

Forests need NO sequential loop at all. lcc restarts node numbering at every emit(), so forests share nothing and the walk over a function is a plain map; only the roots WITHIN one forest thread state, and that is a self-referential genList of single-digit depth. The genericClosure shape task-002 carried forward was not needed here.

MEMORY, the number that will constrain the real code generator: 9.9 to 16.7 kB of peak RSS per DAG node for parse+label (16.7 at 5050 nodes where the evaluator's own footprint dominates, 9.9 at 40653). That is ~2.5x the lexer's 4 kB/token. 219 MB for a 20000-node listing, 394 MB for 40000.

Things that cost time and should not be rediscovered:

* The oracle's listing interleaves LABEL definitions with node lines inside one forest -- 58 forests across lcc's own tst/ corpus do. An emitter driven by 'roots, then labels' emits branches to the wrong side of a label. parse.nix keeps a positional emitOrder instead.
* lcc's node list is already a valid bottom-up order, and a node's position in it coincides with its FIRST use: symbolic.c's visit() appends during the post-order walk of the first root that references it. That is what makes 'materialise a common subexpression at first use' correct rather than a guess.
* Recomputing a count>1 node instead of holding it is NOT merely worse code. A forest spans several statements (one here covers six), and MULI4/DIVI4 become calls on RV32I, so a reloaded INDIR can cross a call the front end deliberately pinned between its uses.
* A listed node (printed with ') that something else also references is a value pinned at that point -- usually a call whose result the next root consumes. Reducing it as a statement loses the result; reducing it again at the use site duplicates the call. burg.nix reduces it to reg at its own position and throws if it is ever reached as a kid first.
* mips.md's convention that a template containing a newline is an INSTRUCTION and one without is a FRAGMENT carries over exactly, and is the whole mechanism by which an addressing mode folds into its parent. Worth keeping when the table grows.
* The Justfile's 'ir' recipe was calling raw 'rcc -target=symbolic', not the rcc-rv32 wrapper -- so it was dumping big-endian IR, against decision-004. Fixed here.

Harness, and one real fault it caught in itself:

messages.sh originally compared the expected fragment against EVERYTHING nix printed on stderr. Nix prints the source around each trace frame, and must-fail.nix's own 'expect = "..."' lines are in that source -- so the check passed for any diagnostic at all. A mutation caught it. It now compares only the text from the last 'error:' onwards. poc/02-lexer/messages.sh has the same shape and is NOT currently fooled, because its eval expression puts the trace inside lex.nix rather than inside the rejects list, but it is fragile for the same reason and worth hardening when that file is next touched.

A second one: 'present' fragments were matched as substrings, so 'mv a1,s11' satisfied an expectation of 'mv a1,s1' and the 'every argument goes in a0' mutation went undetected. 'present' now matches whole lines; 'absent' stays a substring match, which is what each actually means.

Guard ordering, per the forward-carried lesson: floors first (an empty table cannot produce a verdict), then the matcher's own verdicts, then the corpus assumptions. Within the matcher's verdicts, WHAT it emitted is reported before WHY it chose that -- a cost duel is an explanation, and explaining code that is already wrong is the less useful half.

atMostOnce was dropped from cases.nix during review of the mutation suite: no mutation could make it, and only it, fail, so it was a check that could not fail. An exact instruction count per case replaced it and IS mutation-proven.

Review round found two wrong-code paths that the suite did not catch, both now fixed and both now covered:

1. The common-subexpression table was carried across a mid-forest LABEL. lcc puts labels inside a forest -- 56 of the 4800 forests in its own tst/ corpus -- and in 35 of those a node is referenced from both sides of one. Holding a value in a register across a branch target assumes every path reaching it ran the code that filled the register, which this emitter has no analysis to know. It now clears the table at a label and recomputes; ir/cond.c (r = a + (a ? b : a)) is the smallest C that reproduces it, and cases.nix asserts that the first instruction after the join is the RELOAD.

2. parse.nix's fieldOf returned the first WORD of a field, not the field. lcc prints 'type=long long int', which read as 'long' -- on emit.nix's list of four-byte types. The guard whose entire job is refusing what this PoC cannot lay out did not fire, and an eight-byte parameter got a four-byte slot. fieldOf now runs to the next 'k=' word and the width test compares the whole type string.

Also from review, none of them behaviour-visible but all of them real:
* subtreeCalls recursed over a DAG as if it were a tree -- exponential in the sharing, invisible at PoC scale. Now memoised with the same self-referential listToAttrs the label table uses.
* 'is this rule a call' was a hardcoded opcode list inside the supposedly target-free matcher, and it had ALREADY drifted (it named MULU4/DIVU4/CALLP4, for which no rule exists). It is now derived from the rule templates via table.callMarkers, so on a target with a hardware multiplier MULI4 stops being a call with nothing else to edit.
* burg.nix spelled 'reg' and 'stmt' while rules.nix declared start = "stmt" and nothing read it. Both now come from the table.
* emit.nix reduced the whole function twice, to size the frame and then to emit against it, with an unasserted fixpoint between the passes. The saved-register area is now a fixed slot per register, so the layout no longer depends on the reduction and one pass suffices.
* The per-node chain-closure fixpoint re-check was a table property paying a per-node price; cost >= 0 is validated once instead.

Harness holes review found, all now closed:

* checks.matcher in the flake is a contract on the emitted TEXT, not on what the code computes. A rule template can be changed to compute the wrong thing and pass every assertion in it -- 'mv a1,%0' instead of 'mv a1,%1' in the divide libcall divides x by itself and check.nix reports a clean pass. run.sh now carries that exact mutation as a stage-3-only case: it ASSERTS check.nix passes it and then requires the emulator to disagree, so 'the emulator runs the code' is a pinned claim rather than a stated one. The flake comment says plainly that 'just poc-matcher' is the stronger gate.
* requiredOps, libcalls and forbiddenMnemonics had no floor and no mutation: emptying all three left the summary printing '0 required opcodes matched' and passing. Floors and a mutation added.
* MODI4 was asserted in cases.libcalls and appeared in none of the DAGs, so its rule had never been matched, reduced, assembled or run. ir/mod.c exercises it end to end, with rem(-7,3) = -2 chosen so a __modsi3 that floored instead of truncating returns a different number rather than the same one by luck.
* scale.py subtracted the evaluator's baseline CPU and not its baseline RSS, so the headline kB/node was ~44% nix's own 36 MB and the smallest ladder point always looked worst. Net of the baseline the figure is flat at 8.4-8.7 kB per DAG node, and the ceiling was re-derived from that.
* A mutation whose sed no longer matches silently becomes a no-op. One did, when a binding was renamed.  now diffs the mutated copy against the original and calls an unchanged copy a harness fault.
* An earlier draft of the mutated-source list lost its quotes through , so every check-routed mutation would have evaluated a broken expression. The 'each mutation must produce its own fragment' cross-check is what caught it -- the value of that rule is not theoretical.

Two corrections to the notes above, where backticks were eaten by the shell before the text reached this file:

* "...renamed. now diffs the mutated copy..." should read "the mutate helper in run.sh now diffs the mutated copy against the original".
* "...lost its quotes through , so every check-routed mutation..." should read "lost its quotes through the shell eval, so every check-routed mutation...".

And one correction to the measurement recorded earlier in these notes. The 9.9-16.7 kB of peak RSS per DAG node was the GROSS figure, which includes the ~36 MB the nix evaluator occupies before it reads anything -- that constant is 44% of the smallest ladder point and 9% of the largest, which is why the number appeared to fall as the input grew. Net of the baseline, measured the way the CPU figure already was, it is flat: 8.4 to 8.7 kB per DAG node across an 8x ladder. That is the number to plan the real code generator against, and it is about twice the lexer's 4 kB per token rather than 2.5x.

Second review round found that the label fix from the first round had introduced a NEW silent wrong-code path, and it is the one worth remembering.

burg.nix's reduction state carried nextCse, the count of common-subexpression registers held. emit.nix read that same field back after the whole function to decide which callee-saved registers the prologue saves. That worked only while nextCse was monotone. Clearing the table at a label made it a CURSOR that resets, and emit.nix went on treating it as a HIGH-WATER MARK -- so a function holding more registers before a label than after it saved too few. 'int hold(int a, int b) { return a + (a ? b*b : a); }' wrote s10, held it across 'call __mulsi3', and neither saved nor restored it: correct-looking assembly that corrupts its caller's register and its own operand.

The two are now separate fields, and the distinction is the thing to carry forward:
  st.nextCse  the allocation cursor. How many are held RIGHT NOW. Resets to 0
              at a label, with the table. Read by the exhaustion check only.
  st.cseHigh  a running maximum, bumped where the cursor is and never reset.
              The ONLY field emit.nix may read to size or populate the save
              list, alongside st.depthHigh which was already a maximum.
Anything later that reads reduction state to decide what the prologue does must
take a maximum, not a final value.

ir/save.c pins it. check.nix's saved-register cross-check reads the EMITTED prologue rather than the frame record, which is what makes it able to see this at all, but it only reaches it on a function shaped like that one -- the other six cases claim at most one register before any label. Reverting the fix and re-running check.nix gives 'matcher: save uses callee-saved register(s) s10 that its prologue never saves'.

Landed as d8064dd. Full gate green at commit time: encoder 126 instructions vs GNU as, lexer 71 token cases and 34 sources round-tripped with 10 mutations, matcher 7 functions / 178 DAG nodes / 30 rejects / 15 controls / 7 cases executed in the emulator with the host compiler agreeing / 22 mutations, lint clean, 3 PoCs passed.

Scale ladder rendered a verdict on the third attempt: the first two were refused by the contention guard with the machine at load 16-20 on 14 cores from unrelated processes (a report job at 274%, Renode, a browser). At load 7.3 it read linear across 8.05x input for 6.66x CPU, every adjacent step inside 1.45x. That the gate needs a quiet machine to render this verdict at all is filed as task-020.
<!-- SECTION:NOTES:END -->
