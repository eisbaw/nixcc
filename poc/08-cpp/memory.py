#!/usr/bin/env python3
"""What the preprocessor COSTS, which on this project means memory.

decision-001 and decision-007 both land in the same place: what threatens this
compiler is not throughput but the evaluator's per-value overhead. The lexer
costs about 4 kB of peak RSS per token and the frontend 142-359 kB per source
line, so a stage that holds a second token list alive doubles the wrong number.
This preprocessor works on TOKENS precisely so that it does not have to hold
two, and that claim needs a measurement rather than a paragraph.

WHAT IS MEASURED, and why it is two evaluations and not one. The absolute
figure for "preprocessing n lines" is not the interesting number -- most of it
is the lexer's, and the lexer's is already measured by poc/02-lexer. The
interesting number is the DIFFERENCE: the same source, once lexed and once
preprocessed, so the overhead attributable to this stage is what is left. Both
jobs are in the same interleaved session, so they are measured against the same
machine.

NO TIMING VERDICT, AND SO NO NO-VERDICT PATH. decision-008's correction says
plainly that the memory figures are unaffected by which of this machine's three
core classes ran them -- bytes do not care -- and only the TIME claim was an
artefact. So this file renders a verdict on peak RSS and reports the contention
figure beside it without depending on it, which is what poc/07-parser/memory.py
does for the same reason. Measurement is still round-robin through
contention.rounds(), because a session that measured the lexer points first and
the preprocessor points second would confound the two with everything else that
happened in between.

    memory.py POC_DIR
"""
import pathlib
import shutil
import sys

sys.path.append(str(pathlib.Path(__file__).resolve().parent.parent / "lib"))
try:
    import contention
except ImportError as e:
    print(f"HARNESS FAULT: cannot import the contention guard ({e}); "
          f"poc/lib must sit beside this harness")
    sys.exit(2)

REPEATS = 3
# TWO AXES, because they cost differently and only one of them is linear.
#
# LADDER grows the SOURCE at a fixed macro count: n functions, each using
# macros inside a conditional. That is the axis the per-token figure is about.
#
# MACRO_LADDER grows the TABLE at a fixed, tiny source. An attrset updated
# with `//' copies every existing binding, so n `#define's copy n^2/2 of them,
# and the first ladder cannot see it -- `synthetic n' defines six macros
# whatever n is. This axis is here because it was found by review rather than
# by the gate, which is the wrong way round, and because task-013.03 is
# `#include' and one real header chain is a four-figure macro count.
LADDER = [200, 800]
MACRO_LADDER = [500, 2000]
# DECLARED and checked for equality, because an empty LADDER passed this file
# GREEN: `len(runs) != len(jobs)` is derived against derived and both are
# zero, MIN_TOKENS lives inside a loop that never runs, and both verdict loops
# leave `worst_rate` and `worst_overhead` at 0.0, which compares favourably
# with every ceiling. Its cleanest line, after measuring nothing --
# poc/lib/mutant.sh spends forty lines on exactly that shape.
DECLARED_POINTS = 2

# Per TOKEN of the preprocessed stream, net of the evaluator's own start-up.
# Measured at 10.8-11.3 kB over three sessions, against 5.0 kB per token for the
# bare lexer on the same source -- and part of that gap is not cost but
# ARITHMETIC: the preprocessed stream has fewer tokens, because the directive
# lines are gone, so the same bytes are divided by a smaller number. The
# ceiling has room for the evaluator to change and not enough for a second
# live token list.
MAX_KB_PER_TOKEN = 14.0
# What this stage adds to lexing the same text. Measured at 1.59, 1.60 and
# 1.65 over three sessions on the same machine, which is the spread the ceiling has to be
# read against. A preprocessor that copied the token list rather than passing
# the lexer's own attrsets through would show up here and nowhere else --
# every other check in this PoC is about what the tokens ARE.
#
# IT WAS 1.18-1.19 IN SLICE 1 AND THAT IS NOT INPUT DRIFT. Slice 2 replaced a
# recursive expander with a genericClosure worklist, which allocates four
# values per token of a line that names a macro where the recursion allocated
# one. Measured on the OLD ladder input at 800 functions, so that only the
# expander differs: 232308 kB net for slice 1's expander against 275792 kB for
# slice 2's, both against 195848 kB for lexing alone -- 1.19x against 1.41x.
# The rest of the way to 1.59-1.65x is this ladder, which now uses
# function-like macros and a paste as well, because a ladder over slice 1's
# input would be measuring slice 1. task-079 carries the cost, what was tried
# against it and what would actually work; both ceilings carried 35% headroom
# over the measurement before and carry about 20% now, on purpose.
MAX_OVERHEAD = 1.95
# What the macro table costs above lexing the same file, at the top of
# MACRO_LADDER. Measured at 4 MB for 500 macros and 40 MB for 2000 -- it was
# 37 MB before each entry grew a parameter list and a compiled replacement
# plan -- and 138 MB for 4000, growing far faster than the table does, because
# an attrset updated with `//' copies every binding it already holds, so n
# defines copy n^2/2 of them. This is an absolute on ONE point rather than a
# ratio, deliberately: a ratio here would have to accept the growth it is
# supposed to be watching. task-072 is what would make it linear.
MAX_MACRO_TABLE_KB = 100 * 1024
# And an absolute one, because "per token" stays flattering while the total
# goes somewhere a machine cannot follow.
MAX_RSS_KB = 1024 * 1024
MIN_TOKENS = 5000
# The macro ladder's floors, and they differ by SIDE rather than being one
# number, because the two sides are measuring different things. Lexed, the
# file is thousands of directive tokens and the floor says the file was
# really built. Preprocessed, those tokens are gone -- consuming them is the
# whole point -- and what is left is the one function at the end, so its
# floor only says an evaluation happened at all.
MIN_MACRO_LEXED = 500
MIN_MACRO_OUT = 10

fault = contention.fault


def main(argv):
    if len(argv) != 1:
        fault("usage: memory.py POC_DIR")
    poc = pathlib.Path(argv[0]).resolve()

    nix = shutil.which("nix")
    if nix is None:
        fault("no `nix' on PATH -- run this inside nix develop")

    def expr(stage, axis, n):
        fn = "synthetic" if axis == "lines" else "syntheticMacros"
        src = f"(import {poc}/cases.nix).{fn} {n}"
        if stage == "lexed":
            make = f"(import {poc}/../02-lexer/lex.nix).lex ({src})"
        else:
            make = (f"(import {poc}/cpp.nix).tokensOf "
                    f'{{ src = {src}; file = "synthetic.c"; }}')
        # deepSeq, or the count is taken off a list whose elements are still
        # thunks and the measurement is of an evaluation that did not happen.
        return (f"let t = {make}; in builtins.deepSeq t "
                f'"${{toString (builtins.length t)}}"')

    if len(LADDER) != DECLARED_POINTS or len(MACRO_LADDER) != DECLARED_POINTS:
        fault(f"the ladders have {len(LADDER)} and {len(MACRO_LADDER)} points "
              f"against the {DECLARED_POINTS} this file declares for each")

    jobs = ([("lines", stage, n) for n in LADDER
             for stage in ("lexed", "preprocessed")]
            + [("macros", stage, n) for n in MACRO_LADDER
               for stage in ("lexed", "preprocessed")])
    argvs = [contention.baseline_argv(nix)]
    argvs += [[nix, "eval", "--impure", "--raw", "--expr", expr(stage, axis, n)]
              for axis, stage, n in jobs]

    # Round-robin, as decision-008 requires of anything on this machine that
    # subtracts one reading from another.
    measured = contention.rounds(argvs, REPEATS)
    base = measured.points[0]
    runs = measured.points[1:]
    if len(runs) != len(jobs):
        fault(f"{len(runs)} points came back for {len(jobs)} jobs; this is not "
              f"measuring what it declares")

    print(f"machine: {contention.cores()} cores; other work occupied up to "
          f"{contention.busiest(measured):.2f} of them while measuring "
          f"(no verdict here depends on that)")
    print(f"  evaluator baseline: {base.rss / 1024:.0f} MB peak RSS")

    net = {}
    for (axis, stage, n), point in zip(jobs, runs):
        tokens = int(point.out)
        if axis == "lines":
            floor = MIN_TOKENS
        else:
            floor = MIN_MACRO_LEXED if stage == "lexed" else MIN_MACRO_OUT
        if tokens < floor:
            # The point is NAMED, not just counted: two ladder points can trip
            # this for different reasons -- a shrunken ladder and a ladder
            # whose two sides became the same evaluation -- and a message that
            # said only "a ladder point" could not tell them apart.
            fault(f"the {stage} point at {n} "
                  f"{'functions' if axis == 'lines' else 'macros'} produced "
                  f"{tokens} tokens, under the {floor} this axis needs; it is "
                  f"measuring an evaluation that preprocessed nothing worth "
                  f"measuring")
        this = point.rss - base.rss
        net[(axis, stage, n)] = (this, tokens)
        # No per-token figure on the macro axis: the preprocessed side emits
        # sixteen tokens whatever the table holds, so kB-per-token there is
        # the table's cost divided by an unrelated number.
        unit = "functions" if axis == "lines" else "macros  "
        rate = f"{this / tokens:4.1f} kB per token, " if axis == "lines" else ""
        print(f"  {stage:13s} {n:4d} {unit}: {point.rss / 1024:5.0f} MB peak RSS, "
              f"{this / 1024:5.0f} MB net, {rate}{tokens} tokens")
        if point.rss > MAX_RSS_KB:
            sys.exit(f"a ladder point peaked at {point.rss / 1024:.0f} MB, over "
                     f"the {MAX_RSS_KB / 1024:.0f} MB ceiling")

    worst_rate = 0.0
    worst_overhead = 0.0
    for n in LADDER:
        lexed, lexed_tokens = net[("lines", "lexed", n)]
        pp, pp_tokens = net[("lines", "preprocessed", n)]
        if pp_tokens >= lexed_tokens:
            fault(f"at {n} functions the preprocessed stream is {pp_tokens} "
                  f"tokens against {lexed_tokens} lexed; the directives were "
                  f"not consumed, so this is not measuring a preprocessor")
        if lexed <= 0:
            fault(f"the lexed point at {n} functions measured "
                  f"{lexed} kB above the baseline, so there is nothing to "
                  f"take a ratio against")
        worst_rate = max(worst_rate, pp / pp_tokens)
        worst_overhead = max(worst_overhead, pp / lexed)

    print(f"  at most {worst_rate:.1f} kB of peak RSS per preprocessed token, "
          f"under the {MAX_KB_PER_TOKEN:.0f} kB ceiling, and at most "
          f"{worst_overhead:.2f}x what lexing the same source costs, under "
          f"{MAX_OVERHEAD:.2f}x")

    # The macro table, on its own axis and reported as what it is: quadratic.
    # No linearity verdict is taken here, because the implementation is not
    # linear and a check that pretended otherwise would be red on a tree that
    # had not changed. What IS checked is the absolute cost at the top point.
    added = {}
    for n in MACRO_LADDER:
        lexed, _ = net[("macros", "lexed", n)]
        pp, _ = net[("macros", "preprocessed", n)]
        if pp <= lexed:
            fault(f"the macro-table point at {n} macros cost {pp} kB against "
                  f"{lexed} kB for lexing the same file; the table is not "
                  f"being built, so this measures nothing")
        added[n] = pp - lexed
    lo, hi = MACRO_LADDER[0], MACRO_LADDER[-1]
    # THE TWO POINTS HAVE TO BE TWO DIFFERENT FILES, and that is checked on
    # the TOKEN COUNTS rather than on the memory, because token counts are
    # deterministic and peak RSS is not. Without it a ladder of [500, 500]
    # clears every floor above, `pp > lexed' holds at each point, the top
    # point sits under the ceiling, and this stage prints "1.0x for 1x the
    # table" -- a false sentence -- and exits green. The growth figure below
    # is PRINTED and not asserted, deliberately (the implementation is not
    # linear and a verdict would have to accept the growth it is watching),
    # which is exactly why the thing it is computed from needs a guard.
    lexed_lo = net[("macros", "lexed", lo)][1]
    lexed_hi = net[("macros", "lexed", hi)][1]
    if lexed_hi <= lexed_lo:
        fault(f"the macro ladder's two points lexed to {lexed_hi} and "
              f"{lexed_lo} tokens, so they are not two different files and "
              f"the growth figure below would compare a measurement with "
              f"itself")
    growth = added[hi] / added[lo]
    print(f"  the macro table costs {added[lo] / 1024:.0f} MB above lexing at "
          f"{lo} macros and {added[hi] / 1024:.0f} MB at {hi} -- {growth:.1f}x "
          f"for {hi // lo}x the table, because an attrset updated with `//' "
          f"copies every binding it already holds (task-072); the "
          f"{MAX_MACRO_TABLE_KB / 1024:.0f} MB ceiling is on the top point, "
          f"not a claim that this is linear")
    if added[hi] > MAX_MACRO_TABLE_KB:
        sys.exit(f"a table of {hi} macros costs {added[hi] / 1024:.0f} MB above "
                 f"lexing the same file, over the "
                 f"{MAX_MACRO_TABLE_KB / 1024:.0f} MB ceiling; see task-072")
    if worst_rate > MAX_KB_PER_TOKEN:
        sys.exit(f"the preprocessor costs {worst_rate:.1f} kB of peak RSS per "
                 f"token, over the {MAX_KB_PER_TOKEN:.0f} kB ceiling")
    if worst_overhead > MAX_OVERHEAD:
        sys.exit(f"preprocessing costs {worst_overhead:.2f}x what lexing the "
                 f"same source costs, over the {MAX_OVERHEAD:.2f}x ceiling; "
                 f"this stage is holding a second copy of the token stream")


if __name__ == "__main__":
    main(sys.argv[1:])
