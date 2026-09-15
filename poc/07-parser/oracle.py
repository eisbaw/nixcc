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

# Floors on what was compared, not on what matched. A differential that
# compared an empty corpus, or listings with no node lines in them, would
# otherwise report the same clean line as one that compared everything.
MIN_FILES = 22
MIN_FUNCTIONS = 10
MIN_NODE_LINES = 300
MIN_BACKREFS = 200
# lcc diagnoses this corpus in several places -- an unsigned comparison whose
# answer is constant, an expression with no effect, a shift by too many bits.
# A floor on how many of its stderr LINES came back is what makes "the oracle
# stopped reading lcc's stderr" a failure: with nothing read, the comparison
# below would find nothing to disagree with and report the cleanest line it
# has.
MIN_DIAGS = 6

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
    ours = json.loads(proc.stdout)

    if len(ours) < MIN_FILES:
        fault(f"the corpus offered {len(ours)} files to compare, under the "
              f"{MIN_FILES} this differential declares")

    sources = {}
    for name in ours:
        for sub in ("c", "run"):
            p = poc / sub / f"{name}.c"
            if p.exists():
                sources[name] = p
    missing = sorted(set(ours) - set(sources))
    if missing:
        fault(f"no source file found for {', '.join(missing)}")

    ir_bad, err_bad = [], []
    nodes = refs = functions = diags = 0

    for name in sorted(ours):
        run = subprocess.run([ORACLE], stdin=sources[name].open("rb"),
                             capture_output=True, text=True)
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

    if functions < MIN_FUNCTIONS:
        fault(f"only {functions} functions were compared, under the "
              f"{MIN_FUNCTIONS} criterion #2 asks for")
    if nodes < MIN_NODE_LINES:
        fault(f"only {nodes} numbered node lines were compared, under the "
              f"{MIN_NODE_LINES} this differential declares")
    if diags < MIN_DIAGS:
        fault(f"only {diags} of lcc's diagnostic lines were compared, under the "
              f"{MIN_DIAGS} this differential declares; criterion #7 rests on "
              f"lcc's stderr being read at all")
    if refs < MIN_BACKREFS:
        fault(f"only {refs} `#n' back-references were compared, under the "
              f"{MIN_BACKREFS} this differential declares; criterion #3 rests "
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
