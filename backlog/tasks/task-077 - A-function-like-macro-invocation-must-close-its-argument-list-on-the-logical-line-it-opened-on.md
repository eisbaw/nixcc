---
id: TASK-077
title: >-
  A function-like macro invocation must close its argument list on the logical
  line it opened on
status: To Do
assignee: []
created_date: '2026-09-17 07:37'
updated_date: '2026-09-17 09:15'
labels:
  - frontend
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while implementing task-013.02.

poc/08-cpp expands ONE LOGICAL LINE at a time: the outer genericClosure in cpp.nix runs one step per logical line and each step's output becomes one line record, which is what render turns into one output line and what the linemarker arithmetic is computed from. A function-like macro invocation whose `(' opens on one line and whose `)' closes on the next therefore runs out of input mid-gather, and is REFUSED naming this task rather than silently dropped or mis-split.

gcc accepts it -- measured: '#define F(a,b) a+b' with 'F(1,<newline>2)' gives '1 +2'. Real C uses this constantly, so this is a real gap and not a curiosity.

WHAT IT WOULD TAKE, and why it was not done in slice 2. The gather would have to read past the end of its logical line, up to (but not into) the next DIRECTIVE line -- cpp.nix already has the index of every directive line, so the stop condition is O(1) per token and needs no scan. The cost is elsewhere: the step must then report how far it consumed, the state must carry that index so the following line-steps emit nothing for tokens already eaten, and the line RECORD that the expansion lands in now holds tokens from more than one physical line. The eight relocation cases in cases.nix and frontend.sh's check that lcc's resynch() agrees with our markers are all computed against the current one-record-per-logical-line invariant, so this is a change to the line model rather than to the expander.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A function-like invocation whose argument list spans logical lines expands as gcc does, or is refused
- [ ] #2 The line records and the linemarkers stay correct when an expansion swallows tokens from a following line
- [ ] #3 poc/08-cpp/must-fail.nix's case for the refusal is updated or removed with it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
NARROWED BY task-013.02 BEFORE IT SHIPPED, so the remaining refusal is smaller than this task first described. `more' is now "the next logical line's FIRST TOKEN is a `('" rather than "there is a next non-directive logical line", which costs one `elemAt' and takes `int y = F' followed by `;' -- an ordinary identifier to gcc -- out of the refused set entirely. cases.nix carries that as an expansion case and run.sh carries the mutation that widens it back.

What is left is exactly the ambiguous shape: a name at the end of a line whose successor begins with `(', and an argument list opened and not closed. Both genuinely need the line-model change described above.
<!-- SECTION:NOTES:END -->
