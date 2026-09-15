---
id: TASK-011
title: Evaluate C constants from lexemes
status: Done
assignee: []
created_date: '2026-09-14 19:21'
updated_date: '2026-09-15 19:05'
labels:
  - frontend
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The lexer (poc/02-lexer) classifies ICON/FCON/SCON and keeps the lexeme, but computes no VALUE. lcc does this inside gettok, in icon(), fcon(), scon() and backslash(): it decodes escape sequences, picks the type from the suffix and the magnitude, and diagnoses overflow. Someone has to do it before there is anything to constant-fold or to emit.

Two Nix-specific traps make this more than transcription:

1. Integer overflow THROWS in Nix rather than wrapping (decision-001), which is exactly the case lcc detects by letting it happen and looking at the result. Detection has to be done by comparison BEFORE the multiply, not after.

2. Nix strings cannot hold a NUL byte (decision-001), so a decoded string literal cannot be represented as a Nix string at all once it contains a \\0 escape. String constants have to become byte lists, which is the same representation the emitter needs anyway.

Also open: lcc accepts multi-character constants like 'ab' with a warning and uses the first character; our lexer accepts them and says nothing yet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Overflow is detected and reported, not thrown by the evaluator and not silently wrapped
- [x] #2 Character constants are evaluated including simple, octal and hex escapes
- [x] #3 String constants are decoded to byte lists, so an embedded NUL is representable
- [x] #4 Floating constants are evaluated, or the task is split and float is deferred to task-009
- [x] #5 Behaviour is diffed against lcc's rcc for every constant form, not just asserted
- [x] #6 Integer constants are evaluated for decimal, octal and hexadecimal forms with u/U/l/L suffixes, and the type is chosen AS LCC CHOOSES IT -- which differs from C89 for 0xFFFFFFFF (lcc gives unsigned long, the standard unsigned int). lcc is both port source and oracle, so matching it is correct; the divergence is documented
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. poc/06-constants/const.nix: evaluate ICON (dec/oct/hex + u/U/l/L), character constants (simple/octal/hex escapes, multi-char first-char rule), SCON to byte lists with no terminator (the parser concatenates adjacent literals and appends the NUL); FCON rejected with a diagnostic naming decision-006.
2. Overflow detected by comparison BEFORE the multiply against the target's ULONG_MAX (4294967295), never by letting Nix throw; result is lcc's: warn and clamp to the type's max, type unsigned long.
3. cases.nix/check.nix hand-written tables; must-fail.nix rejects with controls; messages.sh checks diagnostic TEXT.
4. oracle.py: differential against rcc-rv32 (never raw rcc). Integer/char forms via 'int f(int x){return x < LEX;}' which prints CNSTI4 dec vs CNSTU4 hex, so value AND signedness are both visible; string forms via 'char s[]=LEX;' and defstring. Floor on the number of forms compared.
5. run.sh in current house style: sandbox.sh, mutate() with a DECLARED count checked for equality, a mutation aimed at every check including the oracle script.
6. Justfile recipe, and the full gate before each commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LANDED in commit 35844a3, as poc/06-constants (const.nix plus cases/check/must-fail/messages/stress/oracle and a run.sh). `just poc-constants', and `just poc' picks it up by directory name.

HOW OVERFLOW IS DETECTED WITHOUT THE EVALUATOR THROWING, since this is the decision task-027 inherits. `accumulate' compares BEFORE the multiply -- `acc.value > (ULONG_MAX - d) / base' -- which is lcc's own decimal test generalised to all three bases. lcc's hexadecimal and octal loops instead inspect the top bits of n AFTER shifting, which is only meaningful because C's unsigned arithmetic wraps, and is exactly what cannot be ported.

The ceiling is the TARGET's 4294967295 and not the host's 2^64-1, and that is an argument rather than a shortcut: every path through lcc's icon() sends an overflowing constant to unsigned long and clamps it to that type's max with a warning, so a value exceeding 4294967295 gives the same (value, type, warning) whether it exceeded by one or by 2^40. Every intermediate therefore stays three decimal orders of magnitude below the point where Nix would throw. The oracle diffs six overflowing forms, including the 2^64-1 case, and stress.nix evaluates a 5000-digit constant to prove the guard holds at the absurd end.

WHAT A STRING CONSTANT IS, the other decision task-027 inherits. evalSCON returns { units; width; warnings; }. `units' is ONE literal's decoded content with NO terminator; `width' is bytes per unit, 1 for "abc" and 2 for L"abc" (widechar is unsignedshort in lcc/src/types.c). The parser concatenates the unit lists of adjacent literals and appends ONE 0. Per-literal NULs would decode `"ab" "cd"' as a,b,0,c,d,0 instead of a,b,c,d,0 -- lcc's scon() joins first and terminates once, and our lexer deliberately emits one SCON per literal.

CRITERION BY CRITERION.

#1 met. Decimal, octal and hexadecimal, all four suffix shapes in both cases and both orders, and lcc's icon() type ladder. One arm of that ladder is deliberately ABSENT: `base != 10 && n > INT_MAX -> unsigned int' is dead on any target where long and int share a maximum, which this one does, because it is only reached when `n > LONG_MAX' already failed. Transliterating it would add a branch no input can take and no test can cover; const.nix says so at the site.

#2 met. Diagnosed and clamped, as lcc does -- never thrown, never wrapped. The warning text is lcc's own, including the quoted lexeme with its suffix, and oracle.py compares that text rather than just the value.

#3 met. Simple, octal (<=3 digits) and hexadecimal (unbounded, masked to widechar's 16 bits) escapes, the four self-yielding escapes, unrecognised escapes with lcc's warning, multi-character constants taking the first character with lcc's warning, and wide character constants. A narrow character constant is SIGN EXTENDED because symbolicIR sets unsigned_char = 0, which is why '\377' is -1; a wide one is not.

#4 met. Byte lists, embedded NUL included, verified against lcc's defstring for `"a\0b"'.

#5 met by its SECOND branch: float is deferred, not evaluated. decision-006 is the decision and task-009 (Done) is where it was taken; evalFCON throws and names decision-006 and task-015, and messages.sh holds it to naming both. Worth flagging rather than hiding: the criterion says "deferred to task-009", but task-009 is the DECIDE task and is closed, so there is no open task carrying the float implementation. decision-006's own answer is "revisit once the integer compiler works end to end". Leaving that as the record rather than filing a speculative task.

#6 met, with two exclusions that should be read rather than assumed. oracle.py asks rcc-rv32 about 111 forms -- 94 scalar, 17 string -- and compares value, SIGNEDNESS and diagnostic text for each. Excluded: float, which has no oracle at all (decision-004: %g, six significant digits); and forms lcc reports as an ERROR rather than a warning, `'\xg'' being the only one reachable here, because lcc continues with 0 while we throw, so there is nothing to diff. Those live in must-fail.nix with their diagnostic text checked instead.

WHAT THE ORACLE CANNOT SEE, and it is the reason cases.nix exists beside it: int and long are both 4-byte signed on this target, so lcc prints CNSTI4 for both and no C construct separates them in this IR. `7' and `7l' are both diffed and both agree; that they agree is all the oracle can say. The TYPE NAME is pinned by hand in cases.nix.

HOW SIGNEDNESS IS MADE VISIBLE AT ALL, which was the non-obvious part of the oracle. An initializer converts the constant to the declared type, so `unsigned long u = 1;' shows the declared type for every form and the diff would have been vacuous. A relational against an int variable keeps it: `x < 7u' emits CVIU4 + CNSTU4 + GEU4 while `x < 7' stays CNSTI4 + GEI4. Every scalar form is asked as `int fN(int x) { return x < FORM; }' and the first CNST node in the function is the constant.

MEASURED, at the point task-011 was first closed. Gate green: 6 PoCs, mutation counts 10 / 36 / 28 / 36 / 16, e2e 7m14s and 8m33s (the run before that rendered NO VERDICT on the lexer ladder -- a busy machine, decision-008, not a regression). poc/06-constants itself: 50 scalar + 13 string + 3 lexed-source cases, 14 rejects with 12 controls, 111 oracle forms of which 21 are diagnosed by both sides, and 16 mutations each detected with its own distinct failure.

THE MUTATION THAT MATTERS MOST replaces rcc-rv32 with `cat' in oracle.py. A differential that still passes with the reference removed is not a differential, and this tree has shipped seven harnesses that reported success while verifying nothing.

KNOWN LIMIT, filed as task-046. The character-code table is built from fromJSON of \u escapes, which yields exactly one byte only below U+0080, so a literal containing a byte above 127 -- a UTF-8 string in C source -- THROWS rather than evaluating. It cannot be extended the same way: fromJSON of a higher code point yields its UTF-8 encoding, and 0xc0, 0xc1 and 0xf5..0xff never appear in valid UTF-8 at all. A checked-in 255-byte file read with readFile would close it in one line, at the cost of a binary blob, which is a decision rather than an oversight. Nothing is unreachable today: \xNN and \NNN name every byte, and lcc's own sources are pure ASCII.

TWO DELIBERATE DEVIATIONS FROM lcc, both in the direction of refusing rather than continuing. `'\xg'' is an lcc error that continues with 0; we throw. The outcome is the same -- an lcc error makes rcc exit non-zero -- but the value never propagates. And `''' is rejected by our lexer where lcc reads uninitialised buffer.

NO TIMING LADDER, deliberately. This stage evaluates one lexeme at a time and has no cost driven by input size in a way that could silently go quadratic, so a ladder would buy a contention self-test and a NO VERDICT path for nothing. stress.nix asks the question that IS worth asking -- 60000 units from one literal, a 5000-digit constant, a 4000-digit hexadecimal escape -- and its answer is yes-or-no on any machine. It also settled one thing honestly: dropping the deepSeq in scanUnits' genericClosure operator does NOT overflow at 60000 units, because every field of an item depends on its own offset rather than the previous item's. The deepSeq stays as insurance against the next field added, and const.nix says that rather than claiming it is load-bearing.

REVIEW ROUND (qa-test-runner and mped-architect, run in parallel after the first two commits). Both found real defects; what follows is what changed, because several of them were fail-open shapes of exactly the kind this tree keeps shipping.

FIXED IN THE EVALUATOR.

`evalToken' read `tok.kind' and `tok.text' as BARE lookups, defeating this file's own stated invariant at the one entry point task-027 is told to call: an attribute miss is the class tryEval does not catch (task-037), so it would have propagated through any must-fail suite that tried to cover it. Both now go through `or (throw ...)', with two rejects and a control.

`signedTypes' was exported as a LIST, so `elem "itn" signedTypes' was false -- a misspelt type name read as UNSIGNED, silently, on the exact path the emitter will use to decide whether to two's-complement a value. Replaced by a single `types' table carrying max and signedness per rung, with `signedOf' a function whose unknown case throws. "unsigned short" is now in that table rather than being patched around in oracle.nix.

`target.INT_MAX' and its three siblings were dead, under a comment claiming they existed so the tables would not restate the target. cases.nix deliberately does not import const.nix -- its whole argument is that a wrong evaluator must not bless its own output -- so the honest fix was to delete the fields, not to wire them up.

`bodyOf' checked that a lexeme opened and closed with the SAME character rather than the right one, so `evalSCON "'a'"' and `evalSCON "xax"' both succeeded. It now takes the expected quote. Two more rejects.

FIXED IN THE HARNESS, and these are the ones worth reading.

A MISTYPED `fn' IN must-fail.nix READ AS A CORRECT REFUSAL. `apply' ended in a HARNESS FAULT `throw', `evaluates' wraps it in tryEval, and tryEval catches a throw -- so `fn = "IOCN"' scored as "the evaluator rejected it" and the file printed its cleanest line. Demonstrated by review. Entry-point names are now validated at table level, outside the tryEval.

EVERY FLOOR IN THIS PoC HAD SPENDABLE SLACK. Review deleted all ten diagnosed overflow forms from oracle.nix and the differential stayed GREEN against MIN_SCALARS = 80. poc/lib/mutant.sh already argues at length that this is how a count goes down in silence and that `-eq' is the answer; the mutation count used equality and none of the tables did. All of them now declare a count and assert equality: check.nix, must-fail.nix, oracle.py. messages.sh no longer restates must-fail.nix's floor, it reads the declared number.

TWO GUARDS IN check.nix WERE UNREACHABLE. The "the comparison is not elementwise" totals sat after the per-case verdict, and `bad == [ ]' already means every case's whole expected list matched, so neither could ever fire. They read as the anti-zip-truncation protection and provided none. Deleted, with the header saying why the protection actually comes from comparing whole lists per case.

THE ORACLE HAD A REAL FAIL-OPEN, narrow but structural. The scalar branch took "the first CNST node while inside an f-name", with nothing anchoring that node to the form. Review simulated dropping it: 92 of 94 forms then disagreed loudly and TWO still read as agreement -- `1' and `'\1'', where the relational's own CNSTI4 1 is the right answer by accident. Each function now has its constant nodes counted and asserted at 3.

The count in the oracle's summary line was taken from OUR answers rather than from lcc's stderr -- the shape that file's own header forbids. It is counted from the parsed diagnostics now, and there is a declared total (22) asserted as a positive control, so a change to rcc's diagnostic format cannot quietly turn every form into "lcc warned nothing".

`parse_oracle' had a dead error branch: rcc does NOT tag errors with "error:", and a non-zero exit is caught before the parser runs anyway. Removed rather than left describing a guard that cannot run.

MUTATIONS: 16 -> 20, and three of the old ones were wrong about themselves. "an overflowing constant wraps instead of clamping" does not wrap (accumulate freezes at the last partial); renamed. Three fragments depended on a case being FIRST in a comma-separated list, so inserting a reject would have turned them into gate failures with no defect behind them; they name a case now. Four checks had nothing aimed at them and now do: the CONTROL half of must-fail.nix, the oracle's string comparison, the per-function node count, and -- the one that matters -- the pre-multiply overflow guard itself. Removing it makes a 5000-digit constant run the accumulation on until NIX raises "integer overflow", which is the failure criterion #2 exists to prevent and which no other mutation could reach.

ALSO ADDED, found while re-reading rather than by review: a case decoding all 95 printable ASCII characters and expecting 32..126. The code table is BUILT from fromJSON rather than written out, and nothing else would have caught an entry landing on the wrong code -- the other cases use a handful of characters and would all still have passed. Verified it bites by shifting the table by one.

A DEVIATION FROM C89 THAT CRITERION #1 SHOULD BE READ AGAINST, surfaced rather than papered over. C89 6.1.3.2 gives an octal or hexadecimal constant the ladder int -> unsigned int -> long -> unsigned long, so `0xFFFFFFFF' is UNSIGNED INT. lcc's icon() tests `n > long max' before the unsigned-int rung and so reaches unsigned long, and we match lcc rather than the standard, because lcc is the oracle. Measured that it makes no observable difference here: `x < 0xFFFFFFFF' and `x < 4294967295u' produce byte-identical IR, both types being 4-byte unsigned. On a target whose long is wider than its int they would differ, and that is a decision for whoever ports this. cases.nix has a row saying so.

THREE FOLLOW-UPS FILED: task-047 (adjacent literals of different width have no join rule and no case), task-048 (a mutated copy symlinks its sibling PoCs LIVE, so a mid-gate edit changes what the mutations evaluate), task-049 (lcc spells two diagnostics differently for non-printable characters and no oracle form reaches that path).

ONE CRITERION ADDED TO ANOTHER TASK, flagged because it is not mine to decide: task-027 now has an AC requiring the slice's oracle to compare rcc's STDERR. `warnings' is recorded and never printed, which is the right separation, but none of task-027's six criteria would have gone red if the parser dropped it. Revert the AC if you disagree.

NOT FIXED, and said plainly. The integer-lexeme grammar is now specified twice -- poc/02-lexer's reHexInt/reDecInt/intSuffix and const.nix's intConst.forms -- and the lexer already decided hex-vs-octal-vs-decimal and threw the answer away, forcing the re-match. They agree today and give different diagnostics for the same bad input. cases.nix has also outgrown its stated job of covering what the oracle is blind to; most of its 51 scalar rows also appear in oracle.nix's form list. Both are rot risks rather than defects, and both are better settled when task-027 decides what a token carries.

AFTER THE REVIEW ROUND, measured: gate green, 6 PoCs, mutation counts 10 / 36 / 28 / 36 / 20, e2e 6m19s. poc/06-constants now runs 51 scalar + 14 string + 3 lexed-source cases, 20 rejects with 16 controls, 111 oracle forms of which lcc diagnoses 22 across 21 forms, and 20 mutations each detected with its own distinct failure.

ORCHESTRATOR: verified independently and accepting all three flagged deviations.

Overflow, checked directly: 4294967295 gives 4294967295/unsigned long/0 warnings; 4294967296 clamps with 1 warning; 99999999999999999999 -- twenty digits, far past 2^64 -- also clamps with 1 warning and does NOT throw. That last case is the proof the comparison happens before the multiply rather than after.

Strings, checked directly: "a\0b" decodes to units [97, 0, 98]. An embedded NUL survives, which is AC#4 and the reason byte lists were necessary at all. "ab" and "cd" each carry no terminator, so a join gives 5 units and not 6.

DEVIATION on #1, 'as C89 chooses it'. lcc's icon() tests against long max before C89's unsigned-int rung, so 0xFFFFFFFF types as unsigned long where the standard says unsigned int. Implementing lcc rather than the standard is CORRECT for this project and the criterion was loose: lcc is both our port source and our differential oracle, so implementing C89 strictly would put us permanently at odds with the thing we diff against. The implementer also measured that x < 0xFFFFFFFF and x < 4294967295u emit byte-identical IR, so nothing observable differs on this target -- though it would on one with a wider long. Criterion amended to say lcc rather than C89, with that divergence named.

This is the third time a criterion of mine was the thing that was wrong.

DEVIATION on #5. It points at task-009, which is the DECIDE task and is closed, so no open task carried the float implementation. The implementer declined to file a speculative task, which was a reasonable call, but decision-006's 'revisit once the integer compiler works end to end' was then the only record of a real deliverable. Filed as task-050, explicitly not actionable yet.

DEVIATION on #6, 'every constant form'. 111 forms diffed with two documented exclusions -- float, which has no oracle at all, and forms lcc treats as an error rather than a warning, which are in must-fail.nix with their diagnostic text checked. Accepted: an exclusion that is named and covered elsewhere is not a gap.

Accepting the acceptance criterion it added to task-027 as well. It is right that nothing else would have gone red if the parser recorded warnings and never printed them.
<!-- SECTION:NOTES:END -->
