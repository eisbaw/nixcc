#!/usr/bin/env python3
"""Diff this parser's output against lcc's, node for node and line for line.

This is criteria #2, #3 and #7 of task-027 in one script, and it is a script
rather than a shell function so that a mutation can reach it -- a function
defined in run.sh is out of scope inside the mount namespace each mutation
runs in. poc/03-matcher/build-and-run.sh and poc/04-assembler/gnu-diff.sh are
the other two worked examples.

WHAT IS COMPARED, and why each part is named rather than implied:

  * The whole listing, byte for byte. That subsumes criterion #3 -- node
    numbers and `#n' back-references are IN the text -- but subsuming it is
    not the same as proving it, so the counts below are extracted and asserted
    on. A renumbering bug changes `12. ADDI4 #13 #14' into `13. ADDI4 #12
    #14'; an opcode-only diff sees two identical multisets of opcodes and
    passes. That is the failure this file exists to catch, and run.sh aims a
    mutation at exactly it.

  * rcc's STDERR, byte for byte. task-011 left the constant evaluator
    returning a `warnings' list that nothing printed, and criterion #7 is the
    gate that stops this parser dropping it: a clamped constant or a
    diagnosed escape that reaches no output channel is invisible to every
    other check here. lcc's format is `LINE: warning: TEXT' when reading
    stdin, which is what compile.nix reproduces.

THE ORACLE IS `rcc-rv32', NEVER RAW `rcc -target=symbolic'. The raw one
declares little_endian = 0 and lays out bitfields and initialisers for a
big-endian machine; decision-004 has the whole argument.

    oracle.py POC_DIR
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys

ORACLE = "rcc-rv32"

# DECLARED counts, checked for EQUALITY, not floors. poc/lib/mutant.sh makes
# this argument about mutation counts and it is just as true here: a floor can
# be spent downward in silence. These began as floors with 70% slack, which
# meant two thirds of the corpus could stop being compared without either
# number moving -- review demonstrated exactly that failure on this project's
# sibling suite, where a floor of 80 stayed green after ten diagnosed forms
# were deleted.
#
# The cost is that adding a corpus file means editing these. That edit is the
# one that was wanted anyway: it is where you notice what the new file brought.
#
# The FILE count is not here: cases.nix declares it (corpusCount plus
# programCount) and oracle.nix hands it over, because a Python restatement of
# a Nix number had already gone stale twice.
FUNCTIONS = 73
NODE_LINES = 2211
BACKREFS = 1879
# lcc diagnoses this corpus in several places -- an unsigned comparison whose
# answer is constant, an expression with no effect, a shift by too many bits,
# a linkage that changed between declarations, an escape sequence that is not
# one and two that name a value too big for a byte. The last three are the
# string literal's own half of criterion #7: poc/06-constants RECORDS a
# diagnosed escape and prints nothing, so the SCON arm of the parser has to
# replay it or a literal whose bytes were silently clamped compiles clean.
#
# Counting lcc's stderr LINES is what makes "the oracle stopped reading it" a
# failure: with nothing read, the comparison below would find nothing to
# disagree with and report the cleanest line it has.
DIAGS = 16

NODE_LINE = re.compile(r"^ ?(\d+)([.'])\s")
BACKREF = re.compile(r"#(\d+)")


def fault(msg):
    print(f"HARNESS FAULT: {msg}", file=sys.stderr)
    sys.exit(2)


def counts(text):
    """Node numbers and back-references in a listing, as multisets."""
    numbers, refs, functions = [], [], 0
    for line in text.splitlines():
        if line.startswith("function "):
            functions += 1
        m = NODE_LINE.match(line)
        if m:
            numbers.append(int(m.group(1)))
            refs.extend(int(r) for r in BACKREF.findall(line))
    return numbers, refs, functions


def main(argv):
    if len(argv) != 1:
        fault("usage: oracle.py POC_DIR")
    poc = pathlib.Path(argv[0]).resolve()

    if shutil.which("nix") is None:
        fault("no `nix' on PATH -- run this inside nix develop")

    proc = subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr", f"import {poc}/oracle.nix"],
        capture_output=True, text=True)
    if proc.returncode != 0:
        print("our own frontend refused to compile the corpus:", file=sys.stderr)
        print(proc.stderr, file=sys.stderr)
        sys.exit(1)
    answer = json.loads(proc.stdout)
    ours, expected = answer["answers"], answer["expected"]

    sources = {}
    for name in ours:
        # A basename present in BOTH directories would silently compare one
        # file's listing against the other file's lcc output, because
        # oracle.nix's listToAttrs keeps the first of a duplicate name. The
        # sets are disjoint today; nothing else enforces it.
        found = [poc / sub / f"{name}.c" for sub in ("c", "run")
                 if (poc / sub / f"{name}.c").exists()]
        if len(found) > 1:
            fault(f"{name}.c exists in both c/ and run/; the differential "
                  f"cannot tell which listing belongs to which source")
        if found:
            sources[name] = found[0]
    missing = sorted(set(ours) - set(sources))
    if missing:
        fault(f"no source file found for {', '.join(missing)}")

    # AFTER the two checks above, and that order is the whole reason this is
    # not one line earlier. oracle.nix keys its answers by basename, so a name
    # present in both c/ and run/ silently loses one of the two -- and the
    # first thing that goes wrong is this count, which then reports a file
    # MISSING from a corpus that has all its files. The duplicate check above
    # is the one that names what actually happened; it existed before and had
    # never been reachable, because this arithmetic fell over in front of it.
    if len(ours) != expected:
        fault(f"the corpus offered {len(ours)} files to compare, against the "
              f"{expected} cases.nix declares")

    ir_bad, err_bad = [], []
    nodes = refs = functions = diags = 0

    for name in sorted(ours):
        try:
            run = subprocess.run([ORACLE], stdin=sources[name].open("rb"),
                                 capture_output=True, text=True)
        except FileNotFoundError:
            fault(f"no `{ORACLE}' on PATH; the flake builds it, so run this "
                  f"inside nix develop")
        # An oracle that exits non-zero has emitted a TRUNCATED listing, and
        # comparing against it would report our frontend as the thing that
        # disagrees. Misattribution is worse than a failure here.
        if run.returncode != 0:
            fault(f"{ORACLE} exited {run.returncode} on {name}.c, so its listing "
                  f"is not a listing:\n{run.stderr}")
        want, want_err = run.stdout, run.stderr
        got, got_err = ours[name]["listing"], ours[name]["diags"]

        n, r, f = counts(want)
        # The control that makes replacing the oracle with `cat' fail HERE,
        # with its own words, rather than as an unreadable whole-file diff.
        if not n or not f:
            print(f"the oracle produced no node lines and no `function' line for "
                  f"{name}.c, so this form was never compared; is {ORACLE} really "
                  f"lcc's frontend?", file=sys.stderr)
            sys.exit(1)
        nodes += len(n)
        refs += len(r)
        functions += f
        diags += len(want_err.splitlines())

        if got != want:
            ir_bad.append((name, want, got))
        if got_err != want_err:
            err_bad.append((name, want_err, got_err))

    if functions != FUNCTIONS:
        fault(f"{functions} functions were compared, against the {FUNCTIONS} this "
              f"differential declares (criterion #2 asks for at least 10)")
    if nodes != NODE_LINES:
        fault(f"{nodes} numbered node lines were compared, against the "
              f"{NODE_LINES} this differential declares")
    if diags != DIAGS:
        fault(f"{diags} of lcc's diagnostic lines were compared, against the "
              f"{DIAGS} this differential declares; criterion #7 rests on "
              f"lcc's stderr being read at all")
    if refs != BACKREFS:
        fault(f"{refs} `#n' back-references were compared, against the "
              f"{BACKREFS} this differential declares; criterion #3 rests "
              f"on these being in the comparison")

    # The floors come FIRST, before any diff is reported. They say "this
    # differential measured nothing", which is a harness fault and a worse
    # thing to be than a disagreement -- and if a disagreement were reported
    # first, an oracle that had stopped reading lcc's stderr would look like a
    # frontend that had started inventing warnings.
    for name, want, got in ir_bad[:2]:
        print(f"--- IR differs for {name}.c", file=sys.stderr)
        for line in difference(want, got):
            print(line, file=sys.stderr)
    for name, want, got in err_bad[:2]:
        print(f"--- diagnostics differ for {name}.c", file=sys.stderr)
        print(f"  lcc says:  {want!r}", file=sys.stderr)
        print(f"  we say:    {got!r}", file=sys.stderr)

    if ir_bad or err_bad:
        print(f"{len(ir_bad)} listing(s) and {len(err_bad)} diagnostic stream(s) "
              f"differ from lcc's", file=sys.stderr)
        sys.exit(1)

    print(f"{len(ours)} translation units and {functions} functions diffed against "
          f"{ORACLE}, byte for byte: {nodes} numbered node lines and {refs} `#n' "
          f"back-references matched, and so did all {diags} lines of lcc's stderr")


def difference(want, got):
    """The first few differing lines, with their positions."""
    a, bb = want.splitlines(), got.splitlines()
    out = []
    for i in range(max(len(a), len(bb))):
        x = a[i] if i < len(a) else "<missing>"
        y = bb[i] if i < len(bb) else "<missing>"
        if x != y:
            out.append(f"  line {i + 1}: lcc {x!r}")
            out.append(f"  line {i + 1}: we  {y!r}")
        if len(out) >= 8:
            break
    return out


if __name__ == "__main__":
    main(sys.argv[1:])
