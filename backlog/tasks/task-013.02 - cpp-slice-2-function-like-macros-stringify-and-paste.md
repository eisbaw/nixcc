---
id: TASK-013.02
title: 'cpp slice 2: function-like macros, stringify and paste'
status: To Do
assignee: []
created_date: '2026-09-16 17:27'
updated_date: '2026-09-16 19:16'
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
- [ ] #1 Function-like macros expand with correct argument substitution, including empty arguments and commas inside parentheses
- [ ] #2 The # operator stringifies, collapsing internal whitespace to one space and escaping quotes and backslashes
- [ ] #3 The ## operator pastes, and the result is NOT re-examined for further macro names
- [ ] #4 A macro does not re-expand inside its own expansion, direct or indirect
- [ ] #5 Differential against gcc -E on a corpus built to hit the corner cases above, comparing token streams
- [ ] #6 Harness mutation-tested
<!-- AC:END -->

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
<!-- SECTION:NOTES:END -->
