---
id: TASK-002
title: 'PoC-2: fold-based C lexer and throughput measurement'
status: Done
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 20:03'
labels:
  - poc
  - frontend
  - perf
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a C89 lexer in Nix using only builtins.foldl' / genList / map, with no traversal whose depth grows with input length.

Why folds: recursion depth is capped by the max-call-depth setting, default 10000, and a function doing real work consumes 2-3 depth units per iteration. It CAN be raised -- but only with --option max-call-depth AND a ulimit -s far above default (16 MB dies at n=50000; 1 GB reaches 200000 and still dies at 1e6). We cannot demand either of someone who just runs `nix eval`, which is the point of the project. Recursive descent whose depth tracks expression nesting is fine; it is input-length-proportional depth that is banned. See decision-001.

The real performance question is NOT fold-vs-recursion, it is accumulator shape. Nix lists have no O(1) cons and ++ copies. Measured at n=200000: `acc ++ [x]` 30.44s, `[x] ++ acc` 30.15s (both quadratic), `concatLists` of singletons 0.08s, `map` over `genList` 0.05s. A lexer written the obvious way would be quadratic and would hand task-005 a "no-go" that is an artifact of the accumulator, not of Nix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Lexer recognises the C89 token classes: identifiers, keywords, integer/float/char/string literals, all punctuators, comments, and whitespace
- [x] #2 Lexes a multi-kilobyte real C source without stack overflow (use a preprocessed lcc or tinycc source file)
- [x] #3 Round-trip property test: concatenating token lexemes with recorded inter-token whitespace reproduces the input byte for byte
- [x] #4 Table of tricky cases with hand-written expected token sequences passes (e.g. 0x1f, 'a', '\\n', "a\"b", ->, ++, <<=, ..., /* */ containing //, a//comment at EOF)
- [x] #5 Runnable as 'just poc-lexer'
- [x] #6 Accumulator is linear by construction: per-step lists flattened once with concatLists, or index-driven genList/map. No ++ accumulation inside any fold
- [x] #7 Linearity is demonstrated, not asserted: doubling input size at most doubles wall time, measured across at least 4 sizes spanning 8x
- [x] #8 A 1000-line preprocessed C file lexes in under 10 seconds and under 2 GB peak RSS; if it does not, the number is reported honestly rather than the threshold moved
- [x] #9 Throughput recorded in task notes for at least 4 input sizes: tokens/sec and peak RSS
- [x] #10 No traversal has depth proportional to input length. The loop runs inside the C++ evaluator -- foldl', genList, map or genericClosure -- never hand-rolled recursion over the input
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Data design first: the string becomes a list of 1-char strings once, via builtins.split "(.)" (measured 14x faster than genList+substring: 0.13s vs 1.4s on 278kB). Length is asserted against stringLength so a regex surprise fails fast.

Loop shape. The outer token loop is builtins.genericClosure, not foldl'. Reason: a data-dependent sequential loop that must EMIT one output per step has no other linear, depth-free form in Nix -- foldl' cannot emit per step (its accumulator is scalar), ++ accumulation is quadratic (decision-001), and a self-referential genList has depth n. genericClosure is an iterative worklist in C++: measured linear (0.07/0.11/0.18/0.35/0.49 s at n=25k..400k) at constant stack depth. Every field carried in an item is forced inside the operator; without that the lazy field chain overflows the stack at n=100000 (measured).

Inner scanning uses one primitive, runUntil: a step function driven by foldl' over genList windows that DOUBLE in size, so the recursion depth is O(log run-length) (<=21 for a 1 MB token), never O(n). Identifier, number, trivia/comment skip and string/char scanning are all state machines fed to it -- one mechanism, not four.

Token set matches lcc exactly, which means NO compound-assignment tokens: lcc lexes '<<=' as LSHIFT then '=' and its parser peeks at the raw next char (expr.c: 'prec[t] == k1 && *cp != "="'). Each token records its preceding trivia, so the parser can reproduce that peek without duplicate state, and the trivia is what makes the byte-for-byte round-trip property possible.

Deliverables in poc/02-lexer/: lex.nix, cases.nix (tricky-case table), must-fail.nix (reject paths + control cases so a blanket-throw cannot pass), roundtrip over real lcc sources, bench over a >=8x size ladder built by concatenating lcc/src/*.c, run.sh, and a mutation test that breaks harness and lexer separately and shows distinct failures.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
<!-- SECTION:NOTES:BEGIN -->
RESULT: the architecture holds. 47000 tokens/s, linear from 31 kB to 431 kB, a 1143-line file in 0.24 s and 82 MB. The kill risk this PoC existed to find did not materialise -- but only because three separate shapes were got right, two of which are traps that look fine at PoC scale.

THROUGHPUT (idle machine, min of 3 runs, evaluator start-up subtracted; ladder is whole lcc/src/*.c files concatenated, never truncated, because a cut at an arbitrary line lands inside a block comment):

  lines    bytes   tokens   wall s  lex cpu s  tokens/s  peak RSS
   1143    31025    10222     0.24       0.21     48783     82 MB
   2306    62419    19354     0.42       0.39     49725    123 MB
   4564   119926    37994     0.85       0.82     46482    205 MB
   8613   223124    69087     1.43       1.40     49414    347 MB
  16720   430998   132366     2.73       2.84     46551    501 MB

Input grew 13.89x and CPU grew 13.57x. Every adjacent step is within 1.35x of its size ratio, and that is asserted in throughput.py rather than eyeballed.

Beyond the gated ladder, measured once by hand: 2.2 MB of concatenated lcc source lexes in 18.3 s at 976 MB, and the whole tinycc source tree (45 files, 2.16 MB, 367379 tokens) round-trips in 11.8 s at 516 MB. Throughput sags from 47000 to roughly 37000 tokens/s at the top -- a constant-factor GC effect, not a change of order.

THE THREE SHAPES, and the cost of getting each wrong:

1. genericClosure, not foldl', for the token loop. foldl' carries a scalar accumulator and cannot emit one value per step; `acc ++ [x]` is quadratic; a self-referential genList has depth n. genericClosure is an iterative worklist in the evaluator and is linear at constant depth (0.07/0.11/0.18/0.35/0.49 s at 25k..400k). This is a finding decision-001 did not have, and it is the piece that makes a lexer possible at all.

2. builtins.substring COPIES ITS HAYSTACK. Cutting a 2.2 MB file into 4-character lexemes: 22.68 s with substring, 2.13 s with concatStringsSep over an exploded character list. At 278 kB the two are 0.41 s and 0.31 s, so this trap is invisible at PoC scale and fatal at real scale -- exactly the shape of mistake that would have produced a false 'Nix is too slow' verdict. Now in decision-001.

3. deepSeq inside every loop. genericClosure forces only `key`; foldl' forces its accumulator only to weak head normal form. A field left lazy is a thunk chain as deep as the loop, and that is 'stack overflow (possible infinite recursion)', not a slowdown. Measured: a synthetic genericClosure carrying one lazy field dies at 100000 steps, and removing the deepSeq from runUntil makes a 1 MB block comment die. Both stay.

ALSO MEASURED, and used: builtins.split "(.)" explodes a string 10x faster than genList+substring (0.13 s vs 1.40 s on 278 kB), in one evaluator call.

REJECTED APPROACHES:
- foldl' over characters with a list accumulator. Quadratic, per decision-001.
- foldl' plus a nested-attrset linked list to get O(1) append. Flattening it back needs a walk as deep as the list.
- Block decomposition (sqrt-sized chunks, each folded, entry states chained through a lazy genList). Works and is pure foldl'/genList, but it is four moving parts where genericClosure is one.
- builtins.split with one big token regex. Tempting -- POSIX ERE is leftmost-longest, which IS maximal munch -- but it yields no positions, so no line numbers, and it teaches the rest of the project nothing about the loop shapes tasks 003 and 006 need.
- Per-character recursion for the inner scans. runUntil uses foldl' over windows that DOUBLE, so depth is O(log run-length): 20 levels for a 1 MB token. Verified on pathological input -- a 1 MB block comment, a 500 kB string literal and a 200 kB identifier all lex without overflow.

DELIBERATE DIVERGENCES, all in lex.nix's header:
- lcc has NO compound-assignment tokens. It lexes '<<=' as LSHIFT then '=' and its parser peeks at the raw next character (expr.c: prec[t] == k1 && *cp != '='). We match lcc; the recorded trivia lets a parser make the same peek via ws == "", with no second copy of the information.
- '//' comments, '#' and backslash-newline are accepted, because we lex RAW C89 and lcc is fed preprocessed input.
- Backslash-newline is spliced BETWEEN tokens only, not in phase 2. check.nix now asserts no continuation in the corpus joins two token characters, so this is a measured precondition rather than a hope.
- Adjacent string literals stay separate tokens; lcc's scon() merges them. Joining belongs in the parser.
- Trigraphs are not translated.

HARNESS. Mutation-tested as required: 10 mutations, each must fail, each must produce its own message and NONE of the other nine. Five break the lexer (punctuator table, dropped trivia, frozen line numbers, unvalidated numbers, detail-free diagnostics), five break the harness (emptied expect lists, empty corpus, emptied reject table, a benchmark that stops forcing tokens, a benchmark that lexes the wrong input). Two of those ten existed only because reviewers found the holes.

WHAT THE REVIEWERS CAUGHT, because none of it was caught by me:

- check.nix's 'the comparison is not elementwise' guard fired BEFORE the per-case diff, so deleting the punctuator table was reported as a HARNESS FAULT with no case named. The guards are now ordered so a harness verdict can never pre-empt a lexer verdict, which is a rule worth keeping in every later harness.
- NOTHING verified line numbers. A lexer answering 'line 1' to everything passed all 64 cases, the round-trip and all six mutations. Now: a 9-case LINE:KIND table, plus an invariant over all 34 real sources (EOI's line must equal the newline count plus one), plus a mutation that freezes the line counter.
- must-fail.nix checked only THAT something threw, never what it said -- so half of 'fail fast and verbosely' was untested. builtins.tryEval returns success and value but never the message, so the check could not live in Nix; messages.sh re-evaluates each of the 20 rejects and greps for a required fragment, two of which pin a line number in the diagnostic.
- throughput.py had zero mutation coverage while printing PASS, in a directory whose whole premise is that this project has shipped a PASS that measured nothing. Two mutations added.
- Numeric suffixes over-accepted: '1uuuu', '1lul' and '0xFFuuulll' all lexed. lcc's icon() takes at most one u and one l in either order and ppnumber() errors on the rest. Regex tightened; '1ll' is now correctly rejected as not-C89.
- bench.nix's comment claimed its deepSeq was what made the measurement honest. It is not -- lex's own operator already deepSeqs every item -- and the reviewer measured seq and deepSeq to be within noise. The comment was a claim dressed as a measurement, in the file least entitled to one. Corrected rather than deleted, because the force should not depend on knowing what another file guarantees.
- Dead weight removed: a HEX character class with no reader, a 'final' field duplicating kind == "EOI", three exports nothing imported.
- The linearity assertion was measuring WALL CLOCK and failed on this machine while two review agents ran -- 2.77x time for a 1.86x step, from a lexer that had not changed. It now measures CPU time, which is stable to within 1.10x of the size ratio across repeated idle runs. Under total saturation (14 busy loops on 14 cores) even CPU time inflates the 500 MB point more than the 82 MB one, so the load average is recorded and a superlinear verdict reached on a loaded machine is reported as a measurement failure rather than as a verdict on the lexer. LIMITATION, stated plainly: this check needs a machine that is not saturated, and the load average is a one-minute mean that lags a burst.

REMAINING LIMITS, none of them hidden:
- Peak RSS is roughly 4 kB per token and the reviewer's attempt to localise it failed: the exploded character list is 20 MB of the 222 MB at the 120 kB point, and the two obvious hypotheses (storing trivia text, reallocating the trivia state per blank byte) account for 2.6% and 1.8%. The cost is the evaluator's per-value overhead, and it is the budget to watch for tasks 003 and 006, not throughput.
- 'nix build .#rcc' is a store cache hit on an unchanged rcc, so the leg of the gate that runs lcc's own corpus does not re-execute every time. Correct Nix behaviour, but 'the gate ran the oracle corpus' is not true of a cached run.
- No column numbers (task-012). No constant VALUES, only classified lexemes (task-011). No phase-2 line splicing (task-008).

OPEN, and the only thing standing between this task and Done: acceptance criterion #2 says 'uses foldl'/genList/map only'. It does not -- the token loop is builtins.genericClosure. The criterion's own stated reason, 'no recursive function whose depth grows with input length', IS met and verified on pathological input. There is no way to write this lexer with foldl'/genList/map alone that is not either quadratic or linear in depth; the alternatives tried are under REJECTED APPROACHES above, and decision-001 now names genericClosure as the sanctioned primitive for a loop that must emit per step.

So this is a judgement call about the criterion, not about the code, and it is not mine to make: either amend #2 to say what it was a proxy for, or reject the deviation and take the block-decomposition design instead (four moving parts, same asymptotics, measurably more complexity). Everything else in this task is done, verified and committed in 9039cc8.

Landed in three commits: 9039cc8 (the lexer, its harness and the two evaluator constraints added to decision-001), 35138bd (this task's record and the notes forward-carried to 003, 005, 006 and 008), 2bb773e (the ladder's end-to-end tolerance, which was the product of four steps held to a single step's tolerance and would have gone red on a busy machine).

ORCHESTRATOR (task selection/review, not the implementer): resolving the AC#2 deviation.

The implementer built the token loop on builtins.genericClosure rather than foldl'/genList/map, correctly refused to retick the criterion itself, and left the task In Progress. That was the right call -- rewriting an AC to match what was built is the failure mode this discipline exists to prevent.

Amending it anyway, and here is why that is not AC-gaming. AC#2 had two clauses: a mechanism list ('uses foldl'/genList/map only') and a property ('no recursive function whose depth grows with input length'). The property is the real criterion; the mechanism list was my enumeration of the builtins I happened to know when I wrote it, and genericClosure was not among them.

Verified independently rather than taken on the implementer's word: builtins.genericClosure at n=500000 completes in 0.77s with max-call-depth at its default of 10000. If it grew Nix call depth it would die at 10000. Its loop is in the C++ evaluator exactly as foldl''s is, so the property holds. The AC now states the property and lists genericClosure as an accepted mechanism.

Also spot-checked the substring finding, since it is now a project-wide constraint that tasks 003 and 006 will be designed around. My first two attempts appeared to REFUTE it -- flat 0.03s regardless of haystack size -- but those tests were wrong: builtins.length does not force list elements, so the substrings were never evaluated. Forced, the effect is exactly as reported: 0.07/0.15/0.39/1.47/4.87s across 100k-1.6MB, a 16x size increase costing 70x time. The implementer's finding stands and my doubt was unfounded.

Gate tier: LIGHT (feature cycle, not an irreversible surface). Gate numbers in the report above are the IMPLEMENTER'S measurements, not independently re-run by me. Independently verified by the orchestrator: the genericClosure depth claim and the substring scaling claim only.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Kill-risk answered: the architecture is viable. 47000 tokens/s, linear across a 13.9x ladder, 1143 lines in 0.29s and 82MB against limits of 10s and 2GB.

Three shapes decide it, two of which measure fine at PoC scale and are fatal at real scale: genericClosure rather than foldl' for any loop that emits per step; never one substring per token against a whole-file haystack (superlinear in file size, invisible below ~300kB); deepSeq inside every loop or the symptom is stack overflow rather than slowness. Both new constraints are recorded in decision-001.

The real constraint on what follows is memory, not throughput: ~4kB peak RSS per token, 976MB on a 2.2MB source. Tasks 003 and 006 will hit that before they hit a speed limit.
<!-- SECTION:FINAL_SUMMARY:END -->

<!-- SECTION:NOTES:END -->
