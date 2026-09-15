#!/usr/bin/env python3
"""Two generated corpora, diffed against lcc: a seeded random one and an
exhaustive boundary cross-product.

WHY THIS EXISTS BESIDE oracle.py. The fixed corpus under c/ is a hand-written
list of things that must be true, and the forward-carried lesson from this
project is that such a list catches a row DELETED from it and never a row that
should have been added. A generator derives the population instead: it will
reach operator, type and control-flow combinations nobody sat down and wrote,
and it reaches new ones the moment the generator's grammar grows.

IT IS SEEDED, so it is reproducible: the same N programs every run, and a
failure can be replayed by seed. It is not a search -- it is a second corpus
that happens to have been written by a program.

AND UNIFORM SAMPLING CANNOT FIND A TWO-OPERAND COINCIDENCE. The one folding
bug this slice shipped and fixed was `-1 << 31', where simp.c's overflow guard
multiplies by `1<<31' as an `int' and therefore by INT_MIN. Its probability
under the random generator is about 1e-6 per node; three more seeds at sixty
programs each did not reach it. So the second corpus is not random at all: it
is every pair from a boundary set crossed with every binary operator, signed
and unsigned, plus every shift count around the width of the type. That is the
shape that finds coincidences, and it is exhaustive rather than lucky.

WHAT IS COMPARED is what oracle.py compares: the whole listing byte for byte,
and rcc's stderr byte for byte. What differs is only where the programs come
from, and that ONE `nix eval' answers for all of them, because the evaluator's
start-up dominates at this size.

    fuzz.py POC_DIR
"""
import json
import pathlib
import random
import shutil
import subprocess
import sys
import tempfile

ORACLE = "rcc-rv32"
SEED = 20260915
COUNT = 40

# The boundary cross-product. Every pair, every operator, both signednesses.
SIGNED = ["(-2147483647-1)", "-1", "0", "1", "2147483647"]
UNSIGNED = ["0u", "1u", "2147483648u", "4294967295u"]
SHIFTS = ["-1", "0", "1", "30", "31", "32"]
PER_FILE = 120
# DECLARED counts, checked for equality, for the reason oracle.py's header
# gives: a floor can be spent downward in silence. The generator is seeded, so
# these are exact and reproducible; they change only when the grammar or the
# seed changes, and that is the edit where you look at what changed.
NODE_LINES = 5629
DISTINCT_OPCODES = 48

BIN = ["+", "-", "*", "/", "%", "<<", ">>", "&", "|", "^"]
CMP = ["<", ">", "<=", ">=", "==", "!="]
CONSTS = ["0", "1", "2", "3", "7", "8", "16", "31", "32", "255", "65536",
          "2147483647", "0u", "1u", "4294967295u", "2147483648u", "0L", "100L"]


def fault(msg):
    print(f"HARNESS FAULT: {msg}", file=sys.stderr)
    sys.exit(2)


def expr(names, d, r):
    if d == 0 or r.random() < 0.3:
        c = r.random()
        if c < 0.45 and names:
            return r.choice(names)
        if c < 0.85:
            return r.choice(CONSTS)
        return str(r.randint(0, 10))
    c = r.random()
    if c < 0.55:
        return f"({expr(names, d - 1, r)} {r.choice(BIN)} {expr(names, d - 1, r)})"
    if c < 0.65:
        return f"({expr(names, d - 1, r)} {r.choice(CMP)} {expr(names, d - 1, r)})"
    if c < 0.72:
        return f"({expr(names, d - 1, r)} {r.choice(['&&', '||'])} {expr(names, d - 1, r)})"
    if c < 0.80:
        return (f"({expr(names, d - 1, r)} ? {expr(names, d - 1, r)}"
                f" : {expr(names, d - 1, r)})")
    if c < 0.86:
        return f"(-{expr(names, d - 1, r)})"
    if c < 0.90:
        return f"(~{expr(names, d - 1, r)})"
    if c < 0.94:
        return f"(!{expr(names, d - 1, r)})"
    if names and c < 0.97:
        return f"({r.choice(names)}++)"
    if names:
        return f"(--{r.choice(names)})"
    return expr(names, d - 1, r)


def stmt(names, d, r, ind):
    p = " " * ind
    c = r.random()
    if c < 0.35:
        return f"{p}{r.choice(names)} = {expr(names, d, r)};\n"
    if c < 0.45:
        op = r.choice(["+=", "-=", "*=", "|=", "&=", "^=", "<<=", ">>="])
        return f"{p}{r.choice(names)} {op} {expr(names, d, r)};\n"
    if c < 0.60 and d > 0:
        s = f"{p}if ({expr(names, d, r)}) {{\n{stmt(names, d - 1, r, ind + 4)}{p}}}"
        if r.random() < 0.5:
            s += f" else {{\n{stmt(names, d - 1, r, ind + 4)}{p}}}"
        return s + "\n"
    if c < 0.70 and d > 0:
        v = r.choice(names)
        return (f"{p}while ({v} > 0) {{\n{stmt(names, d - 1, r, ind + 4)}"
                f"{p}{v} = {v} - 1;\n{p}}}\n")
    if c < 0.78 and d > 0:
        v = r.choice(names)
        return (f"{p}for ({v} = 0; {v} < {r.randint(1, 9)}; {v}++) {{\n"
                f"{stmt(names, d - 1, r, ind + 4)}{p}}}\n")
    if c < 0.84 and d > 0:
        return (f"{p}do {{\n{stmt(names, d - 1, r, ind + 4)}{p}}} "
                f"while ({r.choice(names)} < 0);\n")
    if c < 0.90:
        return f"{p}return {expr(names, d, r)};\n"
    if c < 0.95:
        return f"{p}{r.choice(names)} = h({expr(names, d, r)}, {expr(names, d, r)});\n"
    return f"{p};\n"


def boundary():
    """Every (operand, operator, operand) at the edges of both integer types."""
    out = []
    for op in BIN:
        for a in SIGNED:
            for c in SIGNED:
                out.append(f"int s{len(out)}(void){{ return ({a}) {op} ({c}); }}")
        for a in UNSIGNED:
            for c in UNSIGNED:
                out.append(f"unsigned u{len(out)}(void){{ return ({a}) {op} ({c}); }}")
    for op in CMP:
        for a in SIGNED:
            for c in SIGNED:
                out.append(f"int t{len(out)}(void){{ return ({a}) {op} ({c}); }}")
        for a in UNSIGNED:
            for c in UNSIGNED:
                out.append(f"int v{len(out)}(void){{ return ({a}) {op} ({c}); }}")
    for a in SIGNED:
        out.append(f"int n{len(out)}(void){{ return -({a}); }}")
        out.append(f"int m{len(out)}(void){{ return ~({a}); }}")
        out.append(f"int o{len(out)}(void){{ return !({a}); }}")
    # Constant operand crossed with constant COUNT, which is where simp.c's
    # `1<<r' overflow guard lives. The signed-operand table above does not
    # reach it: 31 is not one of the operands.
    for op in ("<<", ">>"):
        for a in SIGNED:
            for k in SHIFTS:
                out.append(f"int z{len(out)}(void){{ return ({a}) {op} ({k}); }}")
        for a in UNSIGNED:
            for k in SHIFTS:
                out.append(f"unsigned e{len(out)}(void){{ return ({a}) {op} ({k}); }}")
    for k in SHIFTS:
        out.append(f"int p{len(out)}(int x){{ return x << ({k}); }}")
        out.append(f"int q{len(out)}(int x){{ return x >> ({k}); }}")
        out.append(f"unsigned w{len(out)}(unsigned x){{ return x << ({k}); }}")
        out.append(f"unsigned y{len(out)}(unsigned x){{ return x >> ({k}); }}")
    return out


def program(r):
    ps = [f"p{i}" for i in range(r.randint(0, 3))]
    ls = [f"v{i}" for i in range(r.randint(1, 4))]
    names = ps + ls
    sig = ", ".join(f"int {x}" for x in ps) or "void"
    body = "".join(f"    int {x};\n" for x in ls)
    body += "".join(f"    {x} = {r.randint(0, 9)};\n" for x in ls)
    body += "".join(stmt(names, 3, r, 4) for _ in range(r.randint(1, 6)))
    body += f"    return {expr(names, 4, r)};\n"
    return f"extern int h(int, int);\n\nint f({sig})\n{{\n{body}}}\n"


def main(argv):
    if len(argv) != 1:
        fault("usage: fuzz.py POC_DIR")
    poc = pathlib.Path(argv[0]).resolve()
    if shutil.which("nix") is None:
        fault("no `nix' on PATH -- run this inside nix develop")

    d = pathlib.Path(tempfile.mkdtemp(prefix="nixcc-fuzz-"))
    for i in range(COUNT):
        (d / f"t{i}.c").write_text(program(random.Random(SEED + i)))
    fns = boundary()
    files = COUNT
    for i in range(0, len(fns), PER_FILE):
        (d / f"x{i // PER_FILE}.c").write_text("\n".join(fns[i:i + PER_FILE]) + "\n")
        files += 1

    proc = subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr",
         f"import {poc}/fuzz.nix {d}"], capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"our own frontend refused a generated program (seed base {SEED}); "
              f"the sources are in {d}:", file=sys.stderr)
        print(proc.stderr, file=sys.stderr)
        sys.exit(1)
    ours = json.loads(proc.stdout)
    if len(ours) != files:
        fault(f"{len(ours)} generated programs came back, against the {files} "
              f"this stage generates")

    nodes = 0
    opcodes = set()
    bad = []
    for name in sorted(ours):
        src = d / f"{name}.c"
        try:
            run = subprocess.run([ORACLE], stdin=src.open("rb"),
                                 capture_output=True, text=True)
        except FileNotFoundError:
            fault(f"no `{ORACLE}' on PATH; run this inside nix develop")
        if run.returncode != 0:
            fault(f"{ORACLE} exited {run.returncode} on generated {name}.c "
                  f"(sources in {d}), so its listing is not a listing:\n{run.stderr}")
        want, want_err = run.stdout, run.stderr
        got, got_err = ours[name]["listing"], ours[name]["diags"]
        for line in want.splitlines():
            parts = line.lstrip().split()
            if parts and parts[0][:-1].isdigit() and parts[0][-1] in ".'":
                nodes += 1
                opcodes.add(parts[1])
        if got != want or got_err != want_err:
            bad.append((name, want, got, want_err, got_err))

    if nodes != NODE_LINES:
        fault(f"the generated corpus produced {nodes} node lines, against the "
              f"{NODE_LINES} this stage declares; with a fixed seed that number "
              f"moves only when the generator does, and at zero it is generating "
              f"programs with nothing in them")
    if len(opcodes) != DISTINCT_OPCODES:
        fault(f"the generated corpus produced {len(opcodes)} distinct opcodes, "
              f"against the {DISTINCT_OPCODES} this stage declares")

    for name, want, got, want_err, got_err in bad[:1]:
        # The path, not the source: a boundary file holds a hundred and twenty
        # functions and printing it buries the four lines that matter.
        print(f"--- generated program {d}/{name}.c differs", file=sys.stderr)
        a, b = want.splitlines(), got.splitlines()
        for i in range(max(len(a), len(b))):
            x = a[i] if i < len(a) else "<missing>"
            y = b[i] if i < len(b) else "<missing>"
            if x != y:
                print(f"  line {i + 1}: lcc {x!r}", file=sys.stderr)
                print(f"  line {i + 1}: we  {y!r}", file=sys.stderr)
        if got_err != want_err:
            print(f"  stderr lcc {want_err!r}", file=sys.stderr)
            print(f"  stderr we  {got_err!r}", file=sys.stderr)
    if bad:
        print(f"{len(bad)} of {COUNT} generated programs differ from lcc's",
              file=sys.stderr)
        sys.exit(1)

    print(f"{COUNT} random programs (seed {SEED}) and {len(fns)} boundary forms "
          f"diffed against {ORACLE}, byte for byte: {nodes} node lines over "
          f"{len(opcodes)} distinct opcodes, and every line of lcc's stderr")


if __name__ == "__main__":
    main(sys.argv[1:])
