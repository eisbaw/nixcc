---
id: TASK-002
title: 'PoC-2: fold-based C lexer and throughput measurement'
status: To Do
assignee: []
created_date: '2026-09-14 18:20'
updated_date: '2026-09-14 18:46'
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
- [ ] #1 Lexer recognises the C89 token classes: identifiers, keywords, integer/float/char/string literals, all punctuators, comments, and whitespace
- [ ] #2 Implementation uses foldl'/genList/map only; no recursive function whose depth grows with input length
- [ ] #3 Lexes a multi-kilobyte real C source without stack overflow (use a preprocessed lcc or tinycc source file)
- [ ] #4 Round-trip property test: concatenating token lexemes with recorded inter-token whitespace reproduces the input byte for byte
- [ ] #5 Table of tricky cases with hand-written expected token sequences passes (e.g. 0x1f, 'a', '\\n', "a\"b", ->, ++, <<=, ..., /* */ containing //, a//comment at EOF)
- [ ] #6 Runnable as 'just poc-lexer'
- [ ] #7 Accumulator is linear by construction: per-step lists flattened once with concatLists, or index-driven genList/map. No ++ accumulation inside any fold
- [ ] #8 Linearity is demonstrated, not asserted: doubling input size at most doubles wall time, measured across at least 4 sizes spanning 8x
- [ ] #9 A 1000-line preprocessed C file lexes in under 10 seconds and under 2 GB peak RSS; if it does not, the number is reported honestly rather than the threshold moved
- [ ] #10 Throughput recorded in task notes for at least 4 input sizes: tokens/sec and peak RSS
<!-- AC:END -->
