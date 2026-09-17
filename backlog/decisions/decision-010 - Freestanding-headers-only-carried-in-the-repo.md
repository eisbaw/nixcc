---
id: decision-010
title: 'Freestanding headers only, carried in the repo'
date: '2026-09-17 07:01'
status: accepted
---
## Context

`#include` needs two questions answered before it can be built: where a header
comes from, and how that survives a pure evaluation. Neither was tracked until
task-070.

**Purity, measured.** A bare `nix eval --expr` refuses absolute paths outright:
"access to absolute path '/nix' is forbidden in pure evaluation mode". But that
is not how the checks run. The flake's existing checks already read source
purely -- `import ./poc/01-encoder/encode.nix`, `${./poc/01-encoder/compare.py}`
-- and `nix eval .#checks.x86_64-linux.cpp.drvPath` evaluates with no `--impure`
at all. **Flake-relative paths are pure; only absolute ones are not.** So headers
carried in the repository are readable inside `nix flake check`, and the problem
that looked like a blocker is not one.

**Content.** lcc ships five headers -- `assert.h`, `float.h`, `limits.h`,
`math.h`, `stdarg.h` -- and no `stdio.h`, `stdlib.h` or `string.h`. More to the
point, there is no libc: the runtime holds `__mulsi3`, `__divsi3`, `__modsi3`,
`__udivsi3`, `__umodsi3` and nothing else. No malloc, no printf, no memcpy.

## Decision

Ship the **C89 freestanding set only** -- `float.h`, `limits.h`, `stdarg.h`,
`stddef.h` -- carried in the repository so the path is flake-relative and pure.
Hosted headers are out of scope.

The preprocessor takes the header set as a parameter rather than reaching for a
fixed location, so `nix flake check` passes the flake-relative path and `just
run` passes the same path from its impure eval. One mechanism, both callers.

## Consequences

`stdio.h` would be a lie. Shipping a header whose functions have no
implementation behind it would let a program compile and then fail at
instruction selection or, worse, link to nothing -- which is exactly the
silent-failure shape this project refuses everywhere else. Declaring
freestanding is the honest position, not a limitation reluctantly accepted.

Programs keep using the `wc()` syscall hook for output, as every program under
`poc/07-parser/run/` already does. The syscall ABI is target knowledge and has
never been C.

`#include` still gets properly exercised: include guards, nesting, both forms,
and real header content. The slice is not weakened by the narrower set.

Nothing is vendored. This project has kept lcc at arm's length by fetching it at
build time rather than committing it (decision-002 records why its licence
matters), and writing four small headers avoids adding a third-party licence to
a repository that currently carries none.

If a hosted subset is ever wanted, the honest order is libc first, headers
second -- `memcpy` and `strlen` are small and testable on the emulator, and
task-007's runtime is where they would live.
