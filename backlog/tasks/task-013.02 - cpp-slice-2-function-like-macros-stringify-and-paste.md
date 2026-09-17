---
id: TASK-013.02
title: 'cpp slice 2: function-like macros, stringify and paste'
status: Done
assignee: []
created_date: '2026-09-16 17:27'
updated_date: '2026-09-17 11:35'
labels:
  - frontend
  - preprocessor
  - slice
dependencies:
  - TASK-070
parent_task_id: TASK-013
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The hard part of macro expansion, split out deliberately. Across the entire backlog before this, `#` stringify and `##` paste had two passing mentions and appeared in no acceptance criterion -- while task-013 named only "nested and recursive invocations".

Scope: parameters, argument substitution, the # stringify operator, the ## paste operator, and the blue-paint rule (a macro must not re-expand inside its own expansion).

The corner cases are where the defects live: paste producing a token that is then NOT re-examined for further macro names, stringify preserving internal whitespace as a single space, an empty argument, an argument containing a comma inside parentheses, and paste at the edges of a replacement list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Function-like macros expand with correct argument substitution, including empty arguments and commas inside parentheses
- [x] #2 The # operator stringifies, collapsing internal whitespace to one space and escaping quotes and backslashes
- [x] #3 A macro does not re-expand inside its own expansion, direct or indirect
- [x] #4 Differential against gcc -E on a corpus built to hit the corner cases above, comparing token streams
- [x] #5 Harness mutation-tested
- [x] #6 The ## result IS re-examined for further macro names, per C89 3.8.3.3 -- the criterion originally said the opposite and was simply wrong about the language
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Replace the recursive expandTok with a genericClosure worklist (task-071's shape): a cursor over the logical line plus a stack of expansion frames, each token carrying its own hide set. Advance-then-push so a linear macro chain keeps the frame stack at depth 1.
2. defineIn learns parameters: m = { name; params; body; line; }, params = null for object-like. Parameter list validated (identifiers, no duplicates); redefinition sameness compares parameters too.
3. Compile the replacement list into a PLAN at define time: a list of paste-chains over elements (literal token / parameter / stringified parameter). # must be followed by a parameter; ## may not sit at either end. Object-like bodies get the same plan machinery, so object-like ## works too; a bare # in an object-like body stays refused, naming a new task.
4. Invocation: the ( is tested on the RAW next token (gcc: '#define LP (' then 'F LP 3 )' is NOT a call). Arguments gathered by a genericClosure that counts parens and splits top-level commas; empty argument and comma-inside-parens fall out of that. Argument count checked against the parameter count.
5. Arguments are macro-expanded before substitution EXCEPT where they are operands of # or ##, which take the raw tokens. Laziness makes computing both free when only one is used.
6. Factor the lexing primitive under staysApart: one lexJoin that lexes two lexemes written side by side, with staysApart and the new pasteJoin as two predicates over its ONE answer. A paste whose result is not exactly one token is refused.
7. Blue paint: the replacement frame's hide set is the invocation token's hide set plus the macro's own name, applied to body AND argument tokens; a pasted token inherits it, which is what makes '#define SELF CAT(SE,LF)' terminate.
8. The nesting cap becomes a cap on the HIDE SET SIZE, which is nesting rather than input length, so the existing must-fail case for task-071 keeps its meaning.
9. Corpus: four new differential files (function-like, stringify, paste, blue paint) plus a third run/ program that is preprocessed, compiled and RUN. cases.nix gains the cases gcc cannot oracle; must-fail gains the new refusals with controls; run.sh gains a mutation per new mechanism.

KNOWN DIVERGENCE TO REPORT, not to paper over: criterion #3 says a pasted result is NOT re-examined for further macro names. Measured, gcc -E expands 'CAT(X,Y)' to 42 given '#define XY 42', lcc/cpp/macro.c backs the row up over the inserted tokens after doconcat, and C89 3.8.3.3 says the resulting token IS available for further macro replacement. Criterion #5 is a differential against gcc, so the two criteria cannot both hold. Implementing the standard's rule and flagging #3.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FORWARD-CARRIED from task-013.01 (slice 1), commits a063490 and 81ec8bb.

WHAT YOU INHERIT. poc/08-cpp/cpp.nix preprocesses a token stream: lexer.lex once, group by logical line off the lexer's `bol' flag, one genericClosure step per line, and `tokensOf' hands poc/07-parser a token list through compile.nix's `runToks'. Object-like expansion, the conditional stack, the #if evaluator, #line and `render' are all there and mutation-tested (36 mutations). Your job fits inside `expandTok' and `defineIn'; everything else should not need to move.

THE THREE REFUSALS THAT ARE YOURS, and each names task-013.02 today so nothing goes unfiled: a #define whose name is followed by `(' with no space (defineIn's function-like check), a `#' in a replacement list (stringify), and two adjacent `#' with no space between them (paste -- poc/02-lexer has no `##' punctuator, deliberately, so it arrives as two tokens and `defineIn' tells them apart by `ws == ""'). must-fail.nix pins all three with controls; they have to CHANGE with your work rather than quietly start failing.

EXPANSION IS RECURSIVE AND THE CAP IS LOAD-BEARING. expandTok recurses once per nesting level carrying a hide set, and MAX_NEST = 200 stops it before Nix's max-call-depth does. Measured with the cap lifted: a chain of 3000 expands, 6000 dies with "stack overflow; max-call-depth exceeded". task-071 is the task, and it says the fix is a genericClosure worklist -- which is what the standard's rescanning wants anyway (push the replacement list back onto the FRONT of the input, carrying the hide set per token). You have to touch this code for parameters regardless, so slice 2 is the natural place to do it rather than deepening the recursion.

TWO COSTS TO WATCH THAT ARE ALREADY MEASURED. `map (fromBody t)' runs once per ENCLOSING level, so a token nested d deep is rewritten d times: one invocation costs O(depth x expansion), which is fine for a three-token body and is not fine once an argument substitution makes an expansion large. And the macro table is one attrset updated with `//' -- 3 MB above lexing at 500 macros, 37 MB at 2000, 138 MB at 4000 (task-072). poc/08-cpp/memory.py carries both axes; add your numbers to it rather than beside it.

THE TOKEN SHAPE, because you will manufacture more tokens than slice 1 does. There is ONE `mkTok' and it exists because there were two synthesis sites that each remembered a different subset of poc/02-lexer's fields, and one never set `nextLine' at all. Stringify produces an SCON token whose TEXT you build; poc/07-parser's SCON arm concatenates adjacent literals and appends exactly one 0, so a stringified literal joins its neighbours by that rule and no other. Paste produces a token whose text is two lexemes joined, and the result must NOT be re-examined for macro names -- but it DOES have to be a legal token, and poc/08-cpp already has the way to ask: `staysApart' lexes two lexemes joined and looks at what comes back. Reuse it rather than writing a second answer.

WHAT THE DIFFERENTIAL WILL AND WILL NOT COVER. oracle.py runs `gcc -std=c89 -E -P -ffreestanding' and compares token streams over 43 units. Two things it cannot see, both learned here: whitespace inside a token run -- `a <<= 2' and `a << = 2' lex to the same four tokens, so only cases.nix's exact rendered text holds that -- and anything where gcc's own answer differs from C89's, which for #if is the width (gcc computes in intmax_t, we compute in C89's 32-bit long). Stringify collapses internal whitespace to one space, which is a WHITESPACE property inside one token's text, so the differential WILL see it; the adjacency rule above is the one it will not.

AND THE PRACTICAL ONE. `gcc -std=c89' rejects `//' outright, so any corpus file using one has no oracle and belongs in cases.nix instead. One file already moved for that reason.

LANDED. poc/08-cpp now does function-like macros, the # stringify operator and the ## paste operator, on top of a rewritten expander.

THE EXPANDER IS A WORKLIST NOW, which is what task-071 asked for and what function-like macros needed anyway. A cursor over the logical line plus a stack of frames, one genericClosure step per token produced. The cursor advances PAST an invocation before it pushes the replacement and pops a frame the moment it is exhausted, so a linear chain A -> B -> C runs at frame depth ONE however long it is; only genuine nesting stacks. Measured: with MAX_NEST lifted, a chain of 6000 expands in 0.89 s where slice 1's recursion died with "stack overflow; max-call-depth exceeded". The cap stays at 200 and is now a MEMORY guard -- the hide set is copied per level, so a chain costs O(n^2) bindings: 88 MB at 1000, 286 MB at 3000, 782 MB at 6000. The diagnostic says that rather than blaming max-call-depth, and task-071 has the numbers.

TWO COUNTERS, NOT ONE, AND THAT IS NOT REDUNDANCY. The hide set is per TOKEN (it has to be: a function-like macro's body and its arguments arrive carrying different paint) and is what makes expansion terminate. `nest' counts how many macros a token has been expanded through, unconditionally, and is what makes a BROKEN hide set terminate -- with the hide set removed, `#define SELF SELF' would spin for ever and a harness cannot mutation-test a hang. The mutation that removes the hide set now fails with MAX_NEST's diagnostic, which is a failure a test can see.

THE REPLACEMENT LIST IS COMPILED ONCE, at `#define' time, into a flat element list plus the index where each PASTE CHAIN begins. `a##b##c' is one chain of three and pastes left to right. Chains rather than a flag per element because C89 6.8.3.1 expands an argument before substituting it EXCEPT where it is an operand of `#' or `##', and "operand of ##" means "in a chain of more than one". The plan is FORCED at define time, because `##' at either end and a `#' with no parameter after it are constraint violations of the `#define' itself, which gcc reports whether or not the macro is ever used.

ONE LEXING, THREE READERS. `lexAll' lexes a text and drops EOI; `lexJoined' is `lexAll' of two lexemes written side by side; `staysApart' asks whether they stay two, `pasteTok' asks whether they become one, and `stringifyToks' asks whether the literal it built is one SCON. `render' and `##' are the same question asked for opposite answers, and sharing the lexing is what stops a paste that succeeded from being re-split by the renderer. A paste yielding two tokens -- or none, because `/' and `*' open a comment -- is refused, as gcc refuses it.

CRITERION #3 IS WRONG AND I HAVE NOT REWRITTEN IT. It says the token a paste produces is NOT re-examined for further macro names. Three independent sources say otherwise:
  * C89 3.8.3.3: "The resulting token is available for further macro replacement."
  * lcc/cpp/macro.c's expand() calls doconcat() and then does `trp->tp -= rowlen(&ntr)', backing the row up over everything it just inserted.
  * `gcc -std=c89 -E -P' turns `#define CAT(a,b) a##b' + `#define XY 42' + `CAT(X,Y)' into `42'. Measured, not recalled.
Criterion #5 is a differential against gcc over a corpus that includes exactly this, so #3 and #5 cannot both hold. The standard's rule is implemented; #3 is left for you to settle. cases.nix carries the case and the reasoning at the case.

WHAT A CROSS-MODEL REVIEW FOUND, because it found a real one. `#' reproduces the spelling its argument was WRITTEN with, and an argument can come out of ANOTHER macro's replacement list -- so a replacement list has to hand its tokens on carrying their own trivia. `fromBody' was giving every one of them a single space, which made `#define Q(x) #x' with `#define WHERE Q(file.c:12)' produce "file . c : 12": a wrong string literal in the compiled program with no diagnostic anywhere. Every stringify case in the table passed its argument at the USE site, where the trivia is the source's own, so none of them could see it. Fixed, with two cases, a corpus pair gcc oracles, and a mutation. What the single space used to defend -- an expansion pasting against its neighbour -- `render' now defends properly at every boundary through `staysApart', which is slice 1's own fix doing the work.

THREE REFUSALS WHERE GCC ACCEPTS, all filed:
  * task-077 -- an invocation must fit on one logical line. Both halves are refused: an unclosed `(' mid-gather, and a function-like macro NAME at the end of a line whose SUCCESSOR BEGINS WITH `('. The second was over-broad in the first draft -- it refused whenever anything followed -- and was narrowed to that one shape before shipping, which costs one `elemAt' and takes `int y = F' + `;' out of the refused set.
  * task-078 -- a bare `#' in an object-like replacement list, carried from slice 1 with its reason restated.
  * And one over-refusal CLOSED rather than filed: `a#<continuation>#b' is `a##b' after ISO C's phase 2, and `isPaste' now tests `glue' as `funcLike' does. Before that it earned a diagnostic calling a valid replacement list malformed.

AND ONE DIVERGENCE THAT IS A DEFECT, PINNED RATHER THAN HIDDEN (task-080). C89 6.8.3.4 gives a function-like macro's replacement the hide set (HS(name) INTERSECT HS(rparen)) UNION {name}; this computes only the union, because `gather' throws the closing parenthesis's hide set away. So we hide MORE than the standard and stop a level early: gcc turns `#define f(a) a*g' + `#define g(a) f(a)' + `f(2)(9)' into `2*9*g' and we give `2*f(9)'. It is under-expansion, so the frontend refuses the leftover name rather than miscompiling it. cases.nix pins it with OUR answer and names task-080, so it has to CHANGE when that lands.

MEASURED COSTS. The worklist is 19% dearer in peak RSS than the recursion it replaced, on the OLD ladder input so that only the expander differs: 232308 kB net against 275792 kB, both over 195848 kB for lexing alone. memory.py's ceilings moved from 12.0 kB/token and 1.60x to 14.0 and 1.95, against 10.8-11.3 and 1.59-1.65 measured; that is 20% headroom where there was 35%. task-079 carries the cost, the two things that were tried and did not help, and the one that would.

THE CASE TABLE WAS VALIDATED AGAINST GCC, NOT AGAINST THIS CODE. Every one of the 75 expansion cases was run through `gcc -std=c89 -E -P -ffreestanding' and its declared token stream compared with gcc's, independently of what poc/08-cpp does. 73 matched. The two that did not are the `//' case, which gcc refuses outright, and the task-080 case, which is pinned as a divergence on purpose.

AND ONE CASE THAT DISCRIMINATES LESS THAN ITS NAME CLAIMED, found by mutating rather than by reading: `ID(V)' with `#define V 7' gives 7 whether or not the argument was expanded before substitution, because the raw `V' is rescanned inside the frame and expands there. It is now named "an argument that names a macro comes out expanded", and the case that actually separates pre-expansion from rescanning is the two-level stringify idiom -- `#' takes its operand raw, so `XSTR(V)' is "7" only if the argument was expanded on the way in. That is the mutation's fragment.

WHAT THE GATE SAYS, on the tree as committed. 75 expansion cases, 52 `#if' expressions, 10 line-number and linemarker cases, 7 macro-table cases, 703 tokens produced; 45 refusals each with a control and its own diagnostic text; three programs preprocessed, compiled and RUN on the Nix RV32I machine; six diagnostics placed for lcc's own resynch() and lcc's IR matching ours over 312 listing lines for all three programs; 48 translation units diffed against `gcc -E' as token streams (22 with directives, 26 without), 3173 tokens; 56 mutations each detected with its own distinct failure. `just e2e' exit 0, 8 PoCs, mutation counts 13 / 62 / 28 / 37 / 20 / 75 / 56.

WHAT A SECOND REVIEW PASS CHANGED, this one auditing the HARNESSES rather than the code. None of it was a false pass; all of it was a claim that outran what was checked.

  * `#if BIG(3,5) == 5' used `max' as its function-like macro, and max is COMMUTATIVE -- the case came out byte-identical with the two parameters substituted into each other's places. That is ir/unsig.c's divisor of 7 in the file whose own header warns about it. The body is `((a) * 10 + (b))' now.
  * "a chain of pastes joins left to right" could not see associativity -- concatenation is associative, so `123' comes out whichever way the chain folds. What it discriminates is OPERAND ORDER, because concatenation is not commutative, and the name says so now.
  * memory.py printed "Nx for 4x the table" from a ratio it never asserted, and nothing checked the two macro-ladder points were two different files. A ladder of [500, 500] would have cleared every floor and printed "1.0x for 1x the table" -- a false sentence -- and exited green. Guarded on the LEXED TOKEN COUNTS, which are deterministic where peak RSS is not.
  * Two self-guards had never been shown to fire, and one of them is the guard whose whole job is ir/unsig.c: `execute.nix's `blind', which asserts that no program's wrong answers equal its right one. Both have mutations now.
  * The task-014 mutation matched messages.sh's GENERIC failure line rather than the case-specific one every other message_check mutation uses.
  * must-fail's summary said "each with its own diagnostic"; five of the forty-five grep two different fragments out of two shared throw sites, on purpose -- one pins the directive's name and the other the task id. It says "diagnostic fragment" now, and the header says why.
  * check.nix's `produced' sums token counts and macro-table entry counts, so "N tokens produced" was mixed units. It says "values compared".

AND run/funcs.c GOT STRONGER, because the audit was right that it tested one byte of `#' and nothing of a replacement list's own punctuation. BLEND is now invoked with a MULTI-TOKEN argument (`v + 1'), so the parentheses in its body are load-bearing -- drop them and `(v+1)*4+2' becomes `v+1*4+2' and the number moves. TAG now stringifies a two-token argument written with two spaces and the program reads bytes 0 AND 2, so byte 2 is `J' only if `#' collapsed the whitespace and is a space otherwise. All four `instead' rows are now token streams that compile and run, where two of the old ones described a program that would not have compiled at all. The answers are 308 at n=7 and 434 at n=10, computed in execute.nix from the constants rather than read off a run.

FINAL GATE, on the tree as committed: `nix develop --command just e2e' exit 0, 8 PoCs, mutation counts 13 / 62 / 28 / 37 / 20 / 75 / 58. poc/08-cpp reports 75 expansion cases, 52 `#if' expressions, 10 line-number and linemarker cases, 7 macro-table cases, 703 values compared; 45 refusals each with a control and its own diagnostic fragment; three programs preprocessed, compiled and RUN (105/192, 408/705, 308/434); six diagnostics placed for lcc's own resynch() and lcc's IR matching ours over 321 listing lines; 48 translation units diffed against gcc -E as token streams, 3173 tokens; 58 mutations each detected with its own distinct failure. The earlier note's counts of 56 mutations and 703 "tokens" predate the harness round above.

ORCHESTRATOR: the implementer was right and my criterion was wrong -- not loosely worded, factually wrong about C.

Criterion #3 said the ## result is NOT re-examined for macro names. The opposite is true, and the implementer cited three independent sources before declining to tick it: C89 3.8.3.3 says the resulting token IS available for further macro replacement; lcc's own cpp/macro.c expand() calls doconcat() and then does 'trp->tp -= rowlen(&ntr)', backing the row up over the tokens it just inserted so they get rescanned; and gcc -std=c89 turns CAT(X,Y) into 42 given '#define XY 42'.

It also spotted that #3 and #5 could not both hold, since #5 is a differential against gcc over a corpus containing exactly that case. A criterion that contradicts another criterion in the same task is a defect in the task, not in the work.

Verified independently before amending: gcc -std=c89 -E -P gives 'int v = 42;', lcc's macro.c has the back-up at line 220 after doconcat at line 208, and our preprocessor now gives 'int v = 42;' too.

Criterion replaced with the correct rule and ticked. This is the fifth time an implementer has declined to reshape a criterion to fit its work, and the first where the criterion was wrong about the LANGUAGE rather than about this project. Writing an acceptance criterion from memory about a standard I had not checked is the error worth learning from -- the three sources that settle it took two minutes to consult.

A CROSS-MODEL REVIEW (codex) FOUND FIVE SILENT MISCOMPILES AFTER THE FIRST COMMIT. All five reproduced against gcc before anything was changed; all five are fixed in the follow-up commit. Same-model review had passed this work, which is the second time that has happened on this file.

  1. THE PASTED TOKEN'S HIDE SET WAS THE UNION OF ITS OPERANDS', NOT THE INTERSECTION. C89 6.8.3.4 (Prosser's `glue') gives the result HS(left) INTERSECT HS(right), because a name only ONE operand was forbidden to be is not a name the RESULT was forbidden to be. With `#define AB 1+A', `#define CAT(a,b) a##b', `#define EXP(a,b) CAT(a,b)' and `#if EXP(AB,B) == 2', `A' arrives from expanding AB carrying {AB} and `B' does not; unioning them hid the pasted `AB', we emitted `1+AB', the leftover identifier was worth zero and the `#if' was FALSE where gcc's was TRUE. A silently different arm. One line: `b.intersectAttrs' in place of `//'.

     IT ALSO REFUTES A CLAIM THIS REPORT MADE. I wrote that hiding too much is always LOUD because the frontend refuses the leftover name. Inside a `#if' there is no frontend: C89 6.8.1 makes a leftover identifier zero and the arithmetic comes out different. task-080's description carried the same wrong sentence and has been corrected.

  2-5. FOUR WRONG STRING LITERALS, AND THEY ARE ONE RULE ASKED IN FOUR PLACES:

         TRIVIA BELONGS TO THE POSITION, NOT TO THE TOKEN.

     A replacement list occupies the position its invocation had; an argument occupies the position its parameter had; a token `##' manufactures occupies the position of the token it replaced. Each takes the boundary of what it replaced, and its own leading boundary is discarded -- C89 6.8.3 says the whitespace before the first token of a replacement list is not part of the list, and 6.8.3.2 says the same of an argument in as many words. So the compiled plan now carries a `pre' per element, the tokens carry none, and a walk over the replacement list places each boundary -- a DELETED element handing its boundary to whatever follows rather than taking it away. That is one structural change, not four patches, and it is the same move `staysApart' made for the other boundary question.

     Measured before and after, gcc on the left:
       #define F(x) Q(a x)     F(b)        "a b"    was "ab"
       #define G(x) Q(a x+b)   G()         "a +b"   was "a+b"
       #define V 7             XQ(a+V)     "a+7"    was "a+ 7"
       #define F(p,q) Q(z+p##q) F(f,oo)    "z+foo"  was "z+ foo"

     A fifth place fell out of the same walk once it existed: a paste DEEP in a sequence, where the chain's own boundary does not reach it, takes the boundary of the token it replaced. `F(a+b,c)' is "z+a+bc". Its twin `F(a b,c)' is "z+a bc" and passes either way, which is why the pair is written both ways round.

  AND ONE THAT IS NOT ABOUT OWNERSHIP AT ALL, so it did NOT fall out of the rule and needed its own fix: ISO C's phase 2 removes a backslash-newline WITHOUT putting a space in its place, so `Q(a\<newline>+b)' is "a+b" and not "a +b". poc/02-lexer already records that trivia with its `glue' flag; the stringify test now asks `separates' -- whitespace that is not only a splice -- instead of `ws != ""'. The ownership rule is what makes it work through a macro BODY as well, since `pre' carries `glue' with the boundary.

  SO: ONE RULE COVERED FOUR OF THE SIX, a fifth fell out of it, and two needed their own fixes (the hide set, and what counts as whitespace). Saying "one rule subsumed them all" would have been tidier and false.

WHAT THE REVIEW CONFIRMED, AND THE SHARP PART OF IT. The 48-unit differential does detect injected disagreements and the macro-chain scaling is the shape documented -- and neither covered these failures. Five silent miscompiles passed a gcc differential because the CORPUS lacked the shapes that distinguish trivia ownership: every stringify case in it passed its argument at the USE site, where the whitespace is written in the same place it is read. The corpus now carries all six shapes (poc/08-cpp/cpp/stringify.c and paste.c), so the differential sees them; the case table carries them with expectations validated against gcc; and run.sh carries five more mutations.

ORCHESTRATOR, on a process defect of mine that the implementer flagged.

I marked this Done in 5044a9c, and FIVE silent miscompiles landed afterwards in a2dbf45 -- including one that made a #if take the wrong branch. The implementer noticed, said so, and left the status as I had set it rather than quietly changing it.

It is right. I ran the light gate, marked Done, and THEN ran the cross-model review. That is backwards. Done should mean reviewed and closed, and the review is precisely what a same-model gate cannot substitute for: codex has now found two silent miscompiles in slice 1 and five in slice 2, every one of them on work that had already passed its own reviewers and an honest differential.

Standing correction for the rest of this project: a task gets a cross-model review BEFORE it is marked Done, not after. The gate says the code runs; the review says the code is right. On this project those have differed seven times.

What the implementer got right that is worth keeping: asked whether one rule covered all five, it said 'neither, honestly: one rule covered four, a fifth fell out of it, and two needed their own fix. Claiming one rule subsumed them all would have been tidier and false.' The rule it found -- TRIVIA BELONGS TO THE POSITION, NOT THE TOKEN, grounded in C89 6.8.3 and 6.8.3.2 -- is the right abstraction, and it did not stretch it past where it reached.

Verified both reproducers myself after the fix: the #if now takes gcc's branch, and F(b) stringifies to "a b".
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Function-like macros, # stringify and ## paste. funcs.c preprocesses, compiles and runs on the in-Nix machine: 308 at n=7, 434 at n=10, verified independently, and lcc's frontend produces byte-identical IR from our preprocessed text for all three run/ programs.

The expander was rewritten as a genericClosure worklist, which fixed a real scaling wall rather than a theoretical one: a 6000-macro chain now expands in 0.89s where slice 1 died with max-call-depth exceeded. MAX_NEST stays 200 but its REASON changed -- the hide set is copied per level, so a chain costs O(n^2) bindings -- and the diagnostic now says that rather than blaming call depth.

Criterion #3 was wrong about C89 and has been replaced; see the notes.
<!-- SECTION:FINAL_SUMMARY:END -->
