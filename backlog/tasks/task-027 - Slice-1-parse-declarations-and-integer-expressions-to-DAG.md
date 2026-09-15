---
id: TASK-027
title: 'Slice 1: parse declarations and integer expressions to DAG'
status: In Progress
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-15 21:54'
labels:
  - frontend
  - parser
  - slice
dependencies:
  - TASK-002
  - TASK-011
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
First vertical slice per decision-007. Build the parser and DAG builder in Nix for the subset the backend already compiles: int locals and parameters, the integer binary and unary operators, assignment, calls, return.

This is the slice that turns hello.c rather than hello.sym into the entry point of the closed loop, for programs in this subset. That is the project's headline claim moving from "from the IR down" to "from the C down".

Binding constraints: decision-001 (loop shape, accumulator, substring, deepSeq, overflow throws); memory is ~4kB/token and ~8.5kB/DAG node, so do not hold tokens, AST, DAG and labels live at once without measuring. Read the forward-carried notes on this task and on task-005 before starting -- especially that token values are NOT computed by the lexer (task-011) and that lcc has no compound-assignment tokens.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Parser consumes the task-002 lexer's tokens; no second lexer
- [ ] #2 DAG output diffs node-for-node against 'just ir' (rcc-rv32, never raw rcc -target=symbolic) for a corpus of at least 10 C functions in the subset
- [ ] #3 The diff compares node numbering and #n back-references, not just opcodes, since a renumbering bug is exactly what an opcode-only diff misses
- [ ] #4 At least 3 programs in this subset compile from .c and RUN end to end in one nix eval, replacing .sym as the entry point
- [ ] #5 Memory measured and recorded per source line, with tokens/AST/DAG live simultaneously
- [ ] #6 Harness mutation-tested: breaking the parser and breaking the harness each fail distinctly
- [ ] #7 The slice's oracle compares rcc's stderr, not only its IR, so a constant that is clamped or an escape that is diagnosed cannot be dropped silently by the parser
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Port lcc's frontend middle-end to Nix, mirroring lcc/src structure: types.nix (type system + ttob/btot/opname), sym.nix (scoped symbol tables, genlabel/genident/constant, exact-rational ref counts), simp.nix (simp.c constant folding, predicative overflow guards), tree.nix (tree.c root1 + expr.c/enode.c tree constructors), dag.nix (dag.c listnodes/node/newnode/list/reset/killnodes + symbolic.c visit numbering), parse.nix (recursive descent over poc/02-lexer tokens, state-threaded, interleaved with dag construction exactly as lcc interleaves), listing.nix (symbolic.c's emit/emitSymbol text rendering).
2. Diff the rendered listing against 'just ir' (rcc-rv32) for a corpus of >=10 functions in the int subset, byte-for-byte including node numbers, #n back-references, count=, and syms.
3. Feed our own forest attrset (same shape poc/03-matcher/parse.nix produces) into poc/03-matcher/emit.nix + poc/04-assembler, and run >=3 programs on nix-riscv from .c with no lcc in the path.
4. Oracle compares rcc's stderr (warnings) as well as its IR, so a clamped constant or diagnosed escape cannot be silently dropped.
5. Measure peak RSS per source line with tokens, trees, DAG and code list live.
6. poc/07-parser/run.sh harness: mutation-tested with a declared count checked for equality, must-fail suite with controls, oracle in its own script with a mutation aimed at it.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from the task-023/024/025 batch (commits 5f954f6, 7de656d, 7875e71, bce67ae).

WHAT IS NOW SAFE TO EMIT that was not. The backend takes a global at a constant offset (`ADDRGP4 msg+8'), byte and halfword loads and stores with their conversions, the word forms lcc emits for unsigned int, and a CALLI4 whose result nothing consumes. So a parser in the int subset can emit what lcc emits without hitting a refusal, which was the risk decision-007 was written about.

WHAT STILL REFUSES, so do not emit it and expect it to work: CALLP4 and CALLD4 in any position (task-036) -- CALLP4 is reachable the moment anything returns a pointer; a symbol expression over a compiler-generated NUMERIC base, which is what every string-literal subscript produces (task-032, and it blocks task-028 more than it blocks this); CVUU4 and CVIU4 below width 4; hex, spaced or multi-term symbol expressions (task-030). Every one refuses loudly naming the opcode or the symbol, so you will know.

THE ORACLE DIFF IS HARDER THAN IT LOOKS, and criterion 3 is right to insist. Three things about lcc's listing cost time in this batch:
  * A conversion's DESTINATION width is in the opcode and its SOURCE width is the node's first symbol. CVII4 with a 1 and CVII4 with a 2 are the same opcode and different instructions. If your DAG builder does not write that symbol, the backend cannot pick a rule.
  * lcc types a character constant by its DESTINATION: `buf[0] = '\n'' is CNSTI1, not CNSTI4.
  * A discarded call is a LISTED root that nothing references. The distinction between that and a used one is not in the node, it is in whether anything has it as a kid -- poc/03-matcher/parse.nix computes `usedAsKid' per forest, and poc/05-loop/check.nix now uses exactly that to assert hello.c still discards one.

HARNESS LESSONS, all of them paid for.
  * builtins.tryEval does NOT catch `attribute missing'. Measured: `builtins.tryEval (builtins.getAttr "nope" {})' aborts rather than returning success=false. A must-fail suite cannot classify that error class -- it kills the run. Any guard whose failure mode is a missing attribute needs messages.sh or a check.nix pin instead.
  * A hand-written list of things-that-must-be-true catches a row DELETED from it and never a row added to the code and forgotten. Both reviewers proved that against the same check on the same day. Derive the population where you can.
  * A must-contain pin is worthless if the thing it names is emitted either way. `call wr' passed on the very program it claimed to forbid. Test a pin against the state it is supposed to reject, not only against the state you are in.
  * Never pin register names from poc/03-matcher: they come from the evaluation-depth pool and move when the C's expression shapes move, so they will fail on unchanged source and blame it.
  * `nix flake check' reads the GIT tree. A new file must be git-added before the gate sees it.

MACHINE. The contention guard refused or misfired four times in one day's work, in three distinct ways, on an untouched poc/02-lexer -- see task-035, which now carries all three symptoms. If your gate goes red on a timing ladder, read that task before believing the number.

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

FORWARD-CARRIED from task-011 (commit 35844a3). The constant evaluator exists: poc/06-constants/const.nix, used as `import ../06-constants/const.nix'.

THE SURFACE YOU CALL. `evalToken tok' takes a poc/02-lexer token and dispatches on `kind'. Under it: `evalICON lexeme' returns { value; type; warnings; } where `type' is one of "int", "long", "unsigned int", "unsigned long" (integer constants) or "unsigned short" (a wide character constant, widechar being unsignedshort); `evalSCON lexeme' returns { units; width; warnings; }; `evalFCON' THROWS, naming decision-006 and task-015. A token of any other kind throws too, rather than guessing. The lexer's `explode' is now exported for this, so there is still one definition of it.

TWO REPRESENTATION DECISIONS YOU INHERIT, both deliberate.

`units' is ONE literal's decoded content with NO TERMINATOR, and `width' is bytes per unit (1 narrow, 2 wide). THE PARSER concatenates the unit lists of adjacent string literals and appends ONE 0. That is C's phase 6 and it is where lcc's scon() does it too -- it joins first and terminates once. A per-literal NUL would decode `"ab" "cd"' as a,b,0,c,d,0 instead of a,b,c,d,0. Nothing downstream has been written yet, so if this split is wrong for the DAG builder, say so now rather than working around it.

A constant's VALUE for an unsigned type is its unsigned magnitude (0..4294967295), not a wrapped signed Nix integer. Signed types carry the signed value. Conversion to whatever the expression context wants is yours, not the evaluator's.

`warnings' is a LIST OF STRINGS the evaluator recorded and did not print. lcc's text, verbatim, so it can be diffed. Deciding what to do with them -- print them, count them, gate on them -- is the parser's call; today nothing consumes them outside the tests, and a parser that drops them on the floor would be a silent regression the oracle cannot see.

WHAT THE EVALUATOR DOES NOT DO, so you do not go looking. It does not fold expressions, does not promote, does not convert, and does not join adjacent string literals. It evaluates exactly one lexeme.

TWO TRAPS ALREADY PAID FOR, do not re-pay them. Integer overflow THROWS in Nix, so `accumulate' compares before the multiply against the target ceiling; any arithmetic you add over constant values needs the same discipline, and 4294967295 * something is not safe by inspection. And builtins.tryEval does NOT catch an attribute-missing error (task-037), so every lookup in const.nix carries `or (throw ...)' -- a parser table written as a bare `${}' lookup will escape every must-fail suite you write.

ONE LIMIT: a literal containing a byte above 127 throws (task-046). \xNN and \NNN reach every byte and lcc's own sources are ASCII, so nothing in the subset is blocked, but a corpus with UTF-8 in a string literal will stop you.

HOW TO DIFF A CONSTANT'S SIGNEDNESS against the oracle, since criterion #2 here is a node-for-node diff and you will hit the same problem: an initializer CONVERTS the constant and shows the declared type, so `unsigned long u = 1;' tells you nothing. `int f(int x) { return x < FORM; }' keeps it -- CVIU4 + CNSTU4 + GEU4 against CNSTI4 + GEI4. poc/06-constants/oracle.nix explains it at length. And int against long is NOT observable in this IR at all: both are 4-byte signed and both print CNSTI4.

REVIEW ROUND on task-011 added three things this task should know, and one acceptance criterion (#7).

WHY #7 EXISTS. `evalICON'/`evalSCON' return a `warnings' list that nothing prints -- deliberately, because const.nix has no output channel and no source coordinates. Review's point was that a paragraph in these notes is not a gate: a parser that writes `(evalICON t.text).value' and drops the rest compiles a silently-clamped constant, and none of this task's other six criteria would go red. Criterion #7 is that gate. poc/06-constants/oracle.py already does exactly this for constants and is the worked example -- it parses `LINE: warning: TEXT' off rcc's stderr, attributes each to the form on that line, and compares the text.

FLOAT'S REFUSAL HAS NO SOURCE POSITION, and that is this task's problem to solve rather than task-011's. `evalFCON' THROWS, and a Nix throw cannot be caught and re-thrown with file:line -- tryEval discards the message, which is why poc/06-constants has a messages.sh at all. So as things stand the one diagnostic decision-006 cares most about reaches the user without a position. If that matters (task-012 is about source coordinates), the parser should do the throwing at the site that knows where the token was, and const.nix should hand over the reason rather than raise it. Settle it before wiring float rejection in, not after.

THE NUL RULE EXISTS TWICE ONCE YOU WRITE IT. poc/06-constants/oracle.nix's `answerFor' does `r.units ++ [ 0 ]' -- the one-literal special case of the real rule, and the only copy that is currently diffed against lcc. When this task implements the general rule (join adjacent, then append one 0), there will be two, and only the parser's will be on the critical path. Mixed-width joins have no rule at all yet: task-047.

PROGRESS (implementation landed, review pending). Commits d64d382 (the slice) and 88d91cd (two filed tasks).

WHAT RUNS. `just poc-parser'. 22 translation units and 35 functions compiled by a Nix frontend and diffed against rcc-rv32 BYTE FOR BYTE -- 958 numbered node lines, 820 `#n' back-references, and all 8 lines lcc prints on stderr. Three programs (poc/07-parser/run/{sumto,gcd,primes}.c) compile from .c and RUN on nix-riscv inside one nix eval, printing 55, 21 55 and 22 57; re-run at four different arguments and checked against a second implementation of each algorithm written in Nix in cases.nix.

BEYOND THE HARNESS, as private evidence: 460 randomly generated programs in the subset (seeded generator, expressions to depth 4, boundary constants, all ten binary operators, compound assignment, ++/--, ?:, &&/||, if/while/for/do, calls) diffed clean on BOTH the listing and stderr. Plus ~75 hand-written adversarial cases. Zero differences. Pointer LOCALS, `&', unary `*', function pointers through a typedef, `static' functions and `const'/`volatile' all turned out to work and are diffed too -- only pointer ARITHMETIC and subscripting are refused.

MEASURED, not estimated: 176 kB of peak RSS per source line with tokens, trees, dag nodes and symbols all live, flat from 104 to 1664 lines. It was NOT flat at first: flat attrsets for the symbol/tree/node tables were quadratic (62/101/224/574 MB at 104/208/416/832 lines) and poc/07-parser/store.nix chunks them; the listing accumulated a line at a time and was worth another 75 MB. Scale: 8000 statements in one function and 2000 functions in one file both compile; ONE expression caps at about 1300 operands (task-052).

REVIEW ROUND. Two reviewers (mped-architect, qa-test-runner) read the committed slice. Both found real defects; all of them are fixed and each is now mutation-covered. What they found, and what changed:

ONE MISCOMPILE. `-1 << 31' folded where lcc leaves it alone. simp.c guards the shift fold with `muli(l, 1<<r, ...)' where the literal 1 is an `int', so at a count of 31 the multiplier is INT_MIN and SIGN-EXTENDS; passing the mathematical 2^31 lands in a different arm of muli. One cell of a 5x5x10 table. The random generator's probability of reaching it is about 1e-6 per node and three extra seeds did not. The answer was not more seeds: poc/07-parser/fuzz.py now also generates an EXHAUSTIVE boundary cross-product -- every pair from {INT_MIN,-1,0,1,INT_MAX} and {0u,1u,2^31,2^32-1} crossed with all ten binary operators and all six comparisons, plus every shift count from -1 to 32 -- and the mutation that reintroduces the bug is caught there and nowhere else.

TWO PLACES THE FRONTEND ACCEPTED WHAT lcc REJECTS, both now refused with lcc's own wording: `short float' (decl.c's type-combination check, which this port omitted -- we were giving the declaration a DIFFERENT TYPE and compiling it), and a function defined twice, too many arguments for a prototype, a parameter with no name in a definition, an empty declaration, and an array size that is not positive once cast to int.

DECISION-006 WAS BEING VIOLATED, and the oracle could not see it. Float and double DECLARATIONS were accepted; only the conversions were refused. `int f(void){ double x; double y; x = y; return 1; }' compiled -- byte-identically to lcc, because lcc accepts it, so the IR diff is structurally blind. decision-006 says in as many words that the frontend must reject float declarations. It now does, in specifier(), and the must-fail case for it is that exact program.

FOUR DIAGNOSTICS lcc PRINTS THAT WE DID NOT, on programs both frontends compile identically: inconsistent linkage, a local extern that does not match, a register declaration ignored, and an implicit declaration that does not match. All four are criterion #7 failures that no IR diff can reach. poc/07-parser/c/linkage.c is the corpus case. Getting the last one right needed types.c's eqtype() ported properly -- `int f()' and `int f(int)' are COMPATIBLE, and structural equality invents a warning lcc does not print, which is a criterion #7 failure pointing the other way.

MEMORY. A finished function's trees and dag nodes were never released where lcc frees its FUNC arena: 38% of peak RSS for one line, output verified byte-identical. sym.reachable built and filtered a full index of the code list on every code() call where lcc walks back from the tail: the largest single term on a 1600-statement function. And the ladder itself measured the wrong shape -- 8/32/128 FUNCTIONS of ten lines hides the cost of one LARGE function, which is 2.3x per line. Both shapes are now measured, and memory.py states the wall in source lines rather than leaving it to be inferred.

HARNESS. oracle.py's floors carried 69-76% slack, against poc/lib/mutant.sh's own argument that a floor can be spent downward in silence; they are declared counts checked for equality now, and four of the five had no mutation aimed at them. must-fail.nix's "every reject paired with a control" was a comment, not code (17 rejects, 14 controls, one unpaired); the pairing is one table now and every `expect' fragment is asserted distinct. Criterion #4's "three programs RUN" was asserted nowhere -- deleting one left every stage green. The corpus and the run programs are derived from their directories rather than listed. messages.sh matched against nix's whole trace including echoed source. 42 mutations now, up from 26.
<!-- SECTION:NOTES:END -->
