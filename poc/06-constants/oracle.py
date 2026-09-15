"""Differential-test the Nix constant evaluator against lcc's own frontend.

Criterion #6 of task-011 is that behaviour is DIFFED against rcc rather than
asserted, so this asks lcc the same question about every form in oracle.nix
and compares three things per form: the value, the signedness, and the
diagnostic text.

THE ORACLE IS `rcc-rv32', NEVER `rcc -target=symbolic'. The raw oracle
declares little_endian = 0 -- a big-endian machine -- and init.c consults it
when it splits an initializer, which is exactly the code path a string
constant flows through. decision-004 is the whole argument; the wrapper is
what the Justfile's `just ir' uses too.

WHY THIS IS A SEPARATE SCRIPT rather than a few lines in run.sh: a mutation
has to be able to reach it. A check that no mutation is aimed at is a check
nothing proves runs, and this tree has shipped seven harnesses that reported
success while verifying nothing.

WHAT IS COMPARED, and what is not:

  * every form's value and signedness, decoded from CNSTI4/CNSTU4 nodes and
    from defstring/defconst output -- not re-encoded on our side, because
    reimplementing symbolic.c's escaping in Nix would be a second copy of a
    thing that can be wrong in the same way twice;
  * every WARNING lcc prints, attributed to the form on whose line it
    appeared, against the warnings our evaluator recorded. Matching the text
    is deliberate: a compiler that clamps an overflowing constant without
    saying so is wrong in the way that is hardest to notice.
  * NOT int-vs-long. Both are 4-byte signed here, both print as CNSTI4, and
    no C construct separates them in this IR. oracle.nix says so too.
"""

import json
import re
import subprocess
import sys

# DECLARED counts, checked for EQUALITY rather than floors. A diff over an
# empty list prints its cleanest line after comparing nothing, which is this
# tree's recurring failure -- but a floor with slack in it is the same failure
# on a smaller scale, and review demonstrated it here: deleting all ten
# diagnosed overflow forms left this green against a floor of 80. The argument
# for equality is poc/lib/mutant.sh's, made there about mutation counts.
DECLARED_SCALARS = 94
DECLARED_STRINGS = 17
# And the diagnostics, because a form list can be intact while the stderr
# parser silently stops matching anything. This is the positive control for
# the warning half of the comparison: rcc must actually say this many things.
DECLARED_DIAGNOSTICS = 22
# Every form is asked as `int fN(int x) { return x < FORM; }', which lowers to
# the form's own constant plus the relational's CNSTI4 1 and CNSTI4 0. If a
# function ever holds a different number, the "first CNST node" rule below has
# stopped selecting the form and would silently report the relational's own
# 1 or 0 as the answer -- which is right by accident for the forms `1' and
# `'\1''. Review found that; this is what closes it.
CNSTS_PER_SCALAR = 3

ORACLE = "rcc-rv32"

NODE = re.compile(r"\bCNST([IU])4\s+(\S+)")
EXPORT = re.compile(r"^export (\w+)$")
DEFSTRING = re.compile(r'^defstring "(.*)"$')
DEFCONST = re.compile(r"^defconst unsigned\.2 (\d+)$")
# rcc prefixes a warning with "LINE: warning: ". It does NOT tag an error the
# same way -- `'\xg'' comes back as "1: ill-formed hexadecimal escape
# sequence" with no marker and exit 1 -- so there is no error branch here. A
# non-zero exit is caught before this function runs, which is the only way an
# lcc error can reach us.
DIAGNOSTIC = re.compile(r"^(\d+): warning: (.*)$")


def nix_eval(poc):
    """Our side: the forms, the C to ask lcc with, and our answers."""
    out = subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr", f"import {poc}/oracle.nix"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        sys.exit(f"HARNESS FAULT: evaluating {poc}/oracle.nix failed:\n{out.stderr}")
    return json.loads(out.stdout)


def unescape(s):
    """Decode symbolic.c's emitString, which is the only encoder between
    lcc's byte array and us.

    Its rule (lcc/src/symbolic.c): `"' and `\\' are backslash-escaped, a byte
    in [0x20, 0x7f) is printed as itself, and anything else becomes a
    backslash and exactly three octal digits.
    """
    out = []
    i = 0
    while i < len(s):
        if s[i] != "\\":
            out.append(ord(s[i]))
            i += 1
        elif s[i + 1] in '"\\':
            out.append(ord(s[i + 1]))
            i += 2
        else:
            digits = s[i + 1 : i + 4]
            if len(digits) != 3 or any(d not in "01234567" for d in digits):
                sys.exit(
                    f"HARNESS FAULT: `\\{digits}' in a defstring is neither an "
                    f"escaped quote nor three octal digits, so this is not the "
                    f"encoding symbolic.c is documented to use"
                )
            out.append(int(digits, 8))
            i += 4
    return out


def parse_oracle(stdout, stderr, count):
    """Turn rcc's output into one observation per form.

    Forms are numbered, and the symbol names carry the number, so an
    observation is attributed by NAME rather than by position -- a parser that
    silently dropped a form would otherwise shift every later comparison onto
    the wrong expectation and could still come out green.
    """
    observed = {}
    nodes = {}
    current = None
    for raw in stdout.splitlines():
        line = raw.strip()
        m = EXPORT.match(line)
        if m:
            current = m.group(1)
            continue
        if current is None:
            continue
        if current.startswith("f"):
            node = NODE.search(line)
            # The FIRST constant node in the function is the form; the
            # CNSTI4 1 and CNSTI4 0 after it are the relational's own result.
            # `nodes' counts them all, so that the assumption is checked
            # rather than trusted -- see CNSTS_PER_SCALAR.
            if node:
                nodes[current] = nodes.get(current, 0) + 1
                if current not in observed:
                    observed[current] = {
                        "kind": "scalar",
                        "signedness": "signed" if node.group(1) == "I" else "unsigned",
                        "value": int(node.group(2), 0),
                    }
            continue
        m = DEFSTRING.match(line)
        if m:
            observed.setdefault(current, {"kind": "string", "units": [], "width": 1})
            observed[current]["units"] += unescape(m.group(1))
            continue
        m = DEFCONST.match(line)
        if m:
            observed.setdefault(current, {"kind": "string", "units": [], "width": 2})
            observed[current]["units"].append(int(m.group(1)))

    diagnostics = [[] for _ in range(count)]
    for raw in stderr.splitlines():
        m = DIAGNOSTIC.match(raw.strip())
        if not m:
            continue
        index = int(m.group(1)) - 1
        if not 0 <= index < count:
            sys.exit(f"HARNESS FAULT: the oracle reported on line {m.group(1)}, which is not one of the {count} form lines:\n{raw}")
        diagnostics[index].append(m.group(2))
    return observed, diagnostics, nodes


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: oracle.py POC-DIR")
    poc = sys.argv[1]
    spec = nix_eval(poc)

    count = spec["count"]
    lexemes = spec["lexemes"]
    answers = spec["answers"]
    if not count == len(lexemes) == len(answers):
        sys.exit(f"HARNESS FAULT: oracle.nix declares {count} forms but gave {len(lexemes)} lexemes and {len(answers)} answers")
    scalars = sum(1 for a in answers if a["kind"] == "scalar")
    strings = count - scalars
    if scalars != DECLARED_SCALARS or strings != DECLARED_STRINGS:
        sys.exit(
            f"HARNESS FAULT: the oracle table holds {scalars} scalar and "
            f"{strings} string forms, against the {DECLARED_SCALARS} and "
            f"{DECLARED_STRINGS} this check declares. Raise the declared "
            f"numbers with the table."
        )

    try:
        run = subprocess.run(
            [ORACLE], input=spec["csource"], capture_output=True, text=True
        )
    except FileNotFoundError:
        sys.exit(f"HARNESS FAULT: no `{ORACLE}' on PATH. Run this inside `nix develop', which is where the wrapper lives.")
    if run.returncode != 0:
        sys.exit(f"HARNESS FAULT: `{ORACLE}' exited {run.returncode}:\n{run.stderr}")

    observed, diagnostics, nodes = parse_oracle(run.stdout, run.stderr, count)
    parsed = sum(len(d) for d in diagnostics)

    bad = []
    compared = 0
    for i, (lexeme, ours) in enumerate(zip(lexemes, answers)):
        name = ("f" if ours["kind"] == "scalar" else "s") + str(i)
        theirs = observed.get(name)
        if theirs is None:
            bad.append(f"  {lexeme}: the oracle produced no constant for `{name}', so this form was never compared")
            continue
        compared += 1
        if ours["kind"] == "scalar":
            if nodes.get(name) != CNSTS_PER_SCALAR:
                bad.append(
                    f"  {lexeme}: `{name}' holds {nodes.get(name)} constant "
                    f"nodes, not {CNSTS_PER_SCALAR}, so the first one is no "
                    f"longer certain to be the form rather than the "
                    f"relational's own result"
                )
            if (ours["signedness"], ours["value"]) != (theirs["signedness"], theirs["value"]):
                bad.append(
                    f"  {lexeme}: we say {ours['signedness']} {ours['value']}, "
                    f"lcc says {theirs['signedness']} {theirs['value']}"
                )
        else:
            if (ours["width"], ours["units"]) != (theirs["width"], theirs["units"]):
                bad.append(
                    f"  {lexeme}: we say width {ours['width']} {ours['units']}, "
                    f"lcc says width {theirs['width']} {theirs['units']}"
                )
        if ours["warnings"] != diagnostics[i]:
            bad.append(
                f"  {lexeme}: we warn {ours['warnings']}, lcc warns {diagnostics[i]}"
            )

    if compared != count:
        bad.append(f"  only {compared} of {count} forms were compared at all")
    elif parsed != DECLARED_DIAGNOSTICS:
        # The positive control for the warning half: without it, a change to
        # rcc's diagnostic format would stop DIAGNOSTIC matching, every form
        # would read as "lcc warned nothing", and only the forms WE warn about
        # would notice. It is checked only once every form was observed,
        # because if lcc produced no output at all then "never compared" is
        # the diagnosis and this is merely its consequence.
        bad.append(
            f"  {parsed} diagnostics were parsed out of the oracle's stderr, "
            f"against the {DECLARED_DIAGNOSTICS} this check declares -- either "
            f"the form table changed, or rcc's diagnostic format did and this "
            f"stage has stopped reading it"
        )
    if bad:
        print(f"the constant evaluator and lcc disagree on {len(bad)} point(s):", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        sys.exit(1)

    # Counted from what LCC said, not from our own answers. The number is the
    # point of the sentence it appears in, and a count taken from the table
    # rather than from the work is the shape this file's header forbids.
    warned = sum(1 for d in diagnostics if d)
    print(
        f"oracle: {count} constant forms ({scalars} scalar, {strings} string) "
        f"agree with lcc on value, signedness and diagnostic text; lcc "
        f"diagnosed {parsed} of them across {warned} forms, and so did we"
    )


if __name__ == "__main__":
    main()
