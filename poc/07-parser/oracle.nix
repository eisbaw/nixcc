# Our answer for every file the oracle differential compares, as one JSON
# object, so that oracle.py pays for ONE evaluator start-up rather than two per
# file. Both halves come out of a single `run', because listingOf and
# diagnosticsOf would otherwise compile each file twice.
#
# This file deliberately contains no expectations. What lcc says is lcc's to
# say; the comparison is oracle.py's.
let
  b = builtins;
  cases = import ./cases.nix;
  cc = import ./compile.nix;

  files =
    map (n: { name = n; path = ./c + "/${n}.c"; }) cases.corpus
    ++ map (p: { inherit (p) name; path = ./run + "/${p.name}.c"; }) cases.programs;

  answer = f:
    let s = cc.run (b.readFile f.path); in
    {
      inherit (f) name;
      value = {
        listing = cc.linesOf s;
        diags = cc.diagsOf s;
      };
    };
in
{
  answers = b.listToAttrs (map answer files);
  # How many files there SHOULD be, from cases.nix's own declared counts.
  # oracle.py used to restate the sum as a Python constant, which had already
  # gone stale twice in one afternoon.
  expected = cases.corpusCount + cases.programCount;
}
