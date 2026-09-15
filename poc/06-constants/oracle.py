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

# A floor on the number of forms, checked against what oracle.nix actually
# produced. A diff over an empty list prints its cleanest line after
# comparing nothing, which is this tree's recurring failure; the floor is what
# makes an emptied table a fault instead of a pass.
MIN_FORMS = 100
# And floors on the two halves separately, so that emptying one of them
# cannot hide behind the other being long.
MIN_SCALARS = 80
MIN_STRINGS = 10

ORACLE = "rcc-rv32"

NODE = re.compile(r"\bCNST([IU])4\s+(\S+)")
EXPORT = re.compile(r"^export (\w+)$")
DEFSTRING = re.compile(r'^defstring "(.*)"$')
DEFCONST = re.compile(r"^defconst unsigned\.2 (\d+)$")
DIAGNOSTIC = re.compile(r"^(\d+): (warning|error): (.*)$")


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
            if node and current not in observed:
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
        if m.group(2) == "error":
            sys.exit(
                f"HARNESS FAULT: the oracle ERRORED on form {index} "
                f"({m.group(3)}). Forms that make lcc error belong in "
                f"must-fail.nix, not here -- there is nothing to diff when the "
                f"two sides fail in different ways."
            )
        diagnostics[index].append(m.group(3))
    return observed, diagnostics


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
    if count < MIN_FORMS or scalars < MIN_SCALARS or strings < MIN_STRINGS:
        sys.exit(
            f"HARNESS FAULT: the oracle table shrank to {scalars} scalar and "
            f"{strings} string forms, against the {MIN_SCALARS} and "
            f"{MIN_STRINGS} this check declares. A diff over a table that "
            f"short is not the differential criterion #6 asks for."
        )

    try:
        run = subprocess.run(
            [ORACLE], input=spec["csource"], capture_output=True, text=True
        )
    except FileNotFoundError:
        sys.exit(f"HARNESS FAULT: no `{ORACLE}' on PATH. Run this inside `nix develop', which is where the wrapper lives.")
    if run.returncode != 0:
        sys.exit(f"HARNESS FAULT: `{ORACLE}' exited {run.returncode}:\n{run.stderr}")

    observed, diagnostics = parse_oracle(run.stdout, run.stderr, count)

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
    if bad:
        print(f"the constant evaluator and lcc disagree on {len(bad)} point(s):", file=sys.stderr)
        print("\n".join(bad), file=sys.stderr)
        sys.exit(1)

    warned = sum(1 for a in answers if a["warnings"])
    print(
        f"oracle: {count} constant forms ({scalars} scalar, {strings} string) "
        f"agree with lcc on value, signedness and diagnostic text; "
        f"{warned} of them are diagnosed by both"
    )


if __name__ == "__main__":
    main()
