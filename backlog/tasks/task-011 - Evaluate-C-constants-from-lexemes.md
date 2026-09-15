---
id: TASK-011
title: Evaluate C constants from lexemes
status: Done
assignee: []
created_date: '2026-09-14 19:21'
updated_date: '2026-09-15 18:27'
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
- [x] #1 Integer constants are evaluated for decimal, octal and hexadecimal forms with u/U/l/L suffixes, and the type is chosen as C89 chooses it
- [x] #2 Overflow is detected and reported, not thrown by the evaluator and not silently wrapped
- [x] #3 Character constants are evaluated including simple, octal and hex escapes
- [x] #4 String constants are decoded to byte lists, so an embedded NUL is representable
- [x] #5 Floating constants are evaluated, or the task is split and float is deferred to task-009
- [x] #6 Behaviour is diffed against lcc's rcc for every constant form, not just asserted
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

MEASURED. Gate green: 6 PoCs, mutation counts 10 / 36 / 28 / 36 / 16, e2e 7m14s, and 8m33s on the run before the commit (the run before that rendered NO VERDICT on the lexer ladder -- a busy machine, decision-008, not a regression). poc/06-constants itself: 50 scalar + 13 string + 3 lexed-source cases, 14 rejects with 12 controls, 111 oracle forms of which 21 are diagnosed by both sides, and 16 mutations each detected with its own distinct failure.

THE MUTATION THAT MATTERS MOST replaces rcc-rv32 with `cat' in oracle.py. A differential that still passes with the reference removed is not a differential, and this tree has shipped seven harnesses that reported success while verifying nothing.

KNOWN LIMIT, filed as task-046. The character-code table is built from fromJSON of \u escapes, which yields exactly one byte only below U+0080, so a literal containing a byte above 127 -- a UTF-8 string in C source -- THROWS rather than evaluating. It cannot be extended the same way: fromJSON of a higher code point yields its UTF-8 encoding, and 0xc0, 0xc1 and 0xf5..0xff never appear in valid UTF-8 at all. A checked-in 255-byte file read with readFile would close it in one line, at the cost of a binary blob, which is a decision rather than an oversight. Nothing is unreachable today: \xNN and \NNN name every byte, and lcc's own sources are pure ASCII.

TWO DELIBERATE DEVIATIONS FROM lcc, both in the direction of refusing rather than continuing. `'\xg'' is an lcc error that continues with 0; we throw. The outcome is the same -- an lcc error makes rcc exit non-zero -- but the value never propagates. And `''' is rejected by our lexer where lcc reads uninitialised buffer.

NO TIMING LADDER, deliberately. This stage evaluates one lexeme at a time and has no cost driven by input size in a way that could silently go quadratic, so a ladder would buy a contention self-test and a NO VERDICT path for nothing. stress.nix asks the question that IS worth asking -- 60000 units from one literal, a 5000-digit constant, a 4000-digit hexadecimal escape -- and its answer is yes-or-no on any machine. It also settled one thing honestly: dropping the deepSeq in scanUnits' genericClosure operator does NOT overflow at 60000 units, because every field of an item depends on its own offset rather than the previous item's. The deepSeq stays as insurance against the next field added, and const.nix says that rather than claiming it is load-bearing.
<!-- SECTION:NOTES:END -->
