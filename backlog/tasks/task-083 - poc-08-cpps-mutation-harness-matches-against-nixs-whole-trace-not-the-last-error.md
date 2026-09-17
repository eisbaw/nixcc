---
id: TASK-083
title: >-
  poc/08-cpp's mutation harness matches against nix's whole trace, not the last
  error
status: To Do
assignee: []
created_date: '2026-09-17 10:00'
labels:
  - harness
  - preprocessor
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found while adding a mutation in task-013.02, and it is the gap task-013's own forward-carried note warned about: "poc/05-loop's mutation stage trims nix's output to the text after the LAST `error:' line before matching a fragment ... copy the awk rather than rediscovering it". poc/08-cpp/run.sh never did.

WHY IT MATTERS. `mutate' captures the whole of nix's output, and nix echoes the SOURCE around every frame of a trace. check.nix and execute.nix each contain the message template of every other check in them, so a fragment taken from one template matches the output of any mutation that makes that file fail at all -- on something else entirely.

MEASURED. Adding a mutation whose fragment was execute.nix's own sentence "prints the same answer whether the preprocessor chose the right arm or not" made the distinctness loop report three collisions at once: "a macro is not expanded at all", "an #else never fires" and "## joins nothing" all print that sentence, because all three make execute.nix throw and nix echoes the source of the branch above the one that threw. The suite CAUGHT it -- that is what the distinctness loop is for -- and the mutation was rewritten to use the interpolated text ("macros.c with 7 prints the same answer"), which exists only in the rendered message. That is a fix for one fragment, not for the shape.

WHAT THE FIX IS. poc/05-loop/run.sh's mutate() ends with

    outputs+=("$(printf '%s\n' "$out" |
      awk '/^ *error: /{buf = ""} {buf = buf $0 "\n"} END{printf "%s", buf}')")

which keeps only the text from the LAST `error:' line onwards, and keeps output with no `error:' line at all -- a shell stage, or python -- whole.

WHAT IT WILL BREAK, and this is why it is a task rather than a one-line change. Some poc/08-cpp fragments match text that comes BEFORE an `error:' line in the same output. messages.sh prints its own verdict and then `  it said: <the final error line>', so the trim would keep only the second of those and drop the case name. At least these three fragments would have to be re-picked with the trim in place:

  * "'an unimplemented directive still points at the task that records the omission' threw"
  * and any other `$message_check' fragment of the "threw, but its diagnostic" shape

The `'X' did not throw' fragments are safe: messages.sh emits those with no `error:' line anywhere in the output.

The distinctness loop makes this safe to attempt -- it reports every fragment that stops matching, all in one run, since task-013.02 made it collect rather than exit on the first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mutate() trims to the text after the last error: line, as poc/05-loop does, and output with no error: line is kept whole
- [ ] #2 Every fragment that stops matching under the trim is re-picked rather than the trim being dropped
- [ ] #3 The mutation whose fragment is currently the interpolated 'macros.c with 7 prints' can go back to the plain sentence
<!-- AC:END -->
