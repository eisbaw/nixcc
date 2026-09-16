---
id: TASK-072
title: 'The preprocessor''s macro table is an attrset updated with //, which copies'
status: To Do
assignee: []
created_date: '2026-09-16 18:50'
labels:
  - frontend
  - preprocessor
  - perf
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by review during task-013.01, and measured into poc/08-cpp/memory.py's second ladder rather than left as a remark.

poc/08-cpp/cpp.nix keeps macros in one attrset and `defineIn' ends with `st.macros // { ${name} = ...; }'. `//' builds a new binding array holding every key the table already had, so n `#define's copy n^2/2 bindings. That is poc/07-parser/store.nix's finding -- the one that made the symbol, tree and node tables chunked -- wearing an attrset hat instead of a list one, and decision-001 does not name it because decision-001 only measured lists.

MEASURED, peak RSS above lexing the same file: 4 MB at 500 macros, 37 MB at 2000, 138 MB at 4000. The gate now carries the 500-and-2000 points with a 100 MB ceiling on the top one, so it cannot get quietly worse; what it cannot do is go away.

WHY IT DID NOT BITE IN SLICE 1. Nothing writes four thousand `#define's by hand. task-013.03 is `#include', and one real header chain is a four-figure macro count, so this arrives there as 'the preprocessor got slow' with no measurement to bisect against unless it is fixed first.

WHAT THE FIX IS NOT. store.nix buckets integer ids by `id / 64'; a macro name has no integer to divide. Bucketing on the first character was tried on paper and rejected: real macro names cluster on a prefix (GL_, STDIO_, the header's own tag), so the buckets fill unevenly and the constant barely moves. builtins.hashString gives uniform buckets but would have to run on the membership test, which is called once per TOKEN in the file, not once per define.

The shape worth costing: hash only on INSERT and DELETE, and keep the per-token membership test against a structure that does not need the bucket -- or accept the cost and cap the macro count with a diagnostic, the way task-071 caps nesting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The cost of a 4000-macro table is measured, and either brought below the current curve or capped with a diagnostic naming this task
- [ ] #2 The membership test stays O(1) per token: whatever the fix is, it must not run a hash per token of the file
- [ ] #3 poc/08-cpp/memory.py's macro ladder records the new number, and its ceiling is lowered to match rather than left with slack
<!-- AC:END -->
