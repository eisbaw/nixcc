---
id: TASK-027
title: 'Slice 1: parse declarations and integer expressions to DAG'
status: To Do
assignee: []
created_date: '2026-09-15 04:40'
updated_date: '2026-09-15 18:56'
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
<!-- SECTION:NOTES:END -->
