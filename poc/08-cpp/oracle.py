#!/usr/bin/env python3
"""Run a real cpp over the corpus, then compare its token stream with ours.

Criterion #4 of task-013.01: "differential against gcc -E on a corpus,
comparing TOKEN STREAMS rather than whitespace". The comparison itself is in
oracle.nix, because it needs this project's own lexer to turn both sides into
tokens; this script exists because running gcc is a subprocess and an
evaluation cannot do that to itself.

WHAT MUST NOT HAPPEN HERE, and both have happened elsewhere in this tree: a
corpus that shrank to nothing while the diff stayed green, and a differential
that would still pass with the reference removed. The counts are declared in
oracle.nix and checked for equality; ORACLE is a module-level name so that a
mutation can replace it with `cat' and watch this stage go red.

TWO CORPORA. poc/08-cpp/cpp/*.c exercise the directives. poc/07-parser/c/*.c
are the 26 preprocessor-free translation units this project already diffs
against lcc byte for byte, and they are here because a preprocessor has to be
the IDENTITY on a file with no directives -- the half of the differential that
catches a pass which quietly drops ordinary C.

    oracle.py POC_DIR WORK_DIR
"""
import pathlib
import shutil
import subprocess
import sys

# The reference preprocessor, and a module-level constant precisely so a
# mutation can point it somewhere useless.
ORACLE = "gcc"
# -std=c89 rather than the default: in gnu89 mode gcc predefines `unix' and
# `linux' as object-like macros, which would silently rewrite any corpus file
# using either as an identifier. -P suppresses linemarkers, which are not
# tokens. -ffreestanding stops gcc pulling in stdc-predef.h, whose definitions
# would otherwise be in scope for the corpus without anything saying so.
FLAGS = ["-std=c89", "-E", "-P", "-ffreestanding"]


def fault(msg):
    print(f"HARNESS FAULT: {msg}", file=sys.stderr)
    sys.exit(2)


def main(argv):
    if len(argv) != 2:
        fault("usage: oracle.py POC_DIR WORK_DIR")
    poc = pathlib.Path(argv[0]).resolve()
    work = pathlib.Path(argv[1]).resolve()
    if not work.is_dir():
        fault(f"{work} is not a directory")

    # Named rather than left to a bare FileNotFoundError with a traceback.
    # run.sh checks both before it starts, but this script is also run
    # directly and by every mutation, and frontend.sh re-checks its own
    # dependency for the same reason.
    if shutil.which(ORACLE) is None:
        fault(f"no `{ORACLE}' on PATH. This differential needs a real "
              f"preprocessor to compare against; the dev shell provides gcc, "
              f"so run it inside `nix develop'.")
    if shutil.which("nix") is None:
        fault("no `nix' on PATH -- run this inside nix develop")

    corpus = sorted((poc / "cpp").glob("*.c"))
    identity = sorted((poc.parent / "07-parser" / "c").glob("*.c"))
    if not corpus:
        fault(f"no corpus files under {poc / 'cpp'}")
    if not identity:
        fault(f"no preprocessor-free translation units under {poc.parent / '07-parser' / 'c'}")

    out = work / "gcc"
    out.mkdir(exist_ok=True)

    def run_oracle(src):
        dst = out / (src.parent.name + "-" + src.name + ".i")
        r = subprocess.run([ORACLE, *FLAGS, str(src)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fault(f"{ORACLE} failed on {src}:\n{r.stderr}")
        dst.write_text(r.stdout)
        return dst

    def entries(paths):
        return "[ " + " ".join(
            '{ name = "%s"; src = %s; gcc = %s; }' % (p.name, p, run_oracle(p))
            for p in paths) + " ]"

    expr = (f"import {poc}/oracle.nix {{ "
            f"cases = {entries(corpus)}; identity = {entries(identity)}; }}")
    r = subprocess.run(["nix", "eval", "--impure", "--raw", "--expr", expr],
                       capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(1)
    print(f"  {len(corpus)} corpus files and {len(identity)} preprocessor-free "
          f"units went through `{ORACLE} {' '.join(FLAGS)}'")


if __name__ == "__main__":
    main(sys.argv[1:])
