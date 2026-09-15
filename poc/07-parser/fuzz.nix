# Our answer for every generated program in `dir', as one JSON object, so that
# fuzz.py pays for ONE evaluator start-up rather than one per program.
#
# Flatter than oracle.nix, which also hands back the file count cases.nix
# declares: here the count is the GENERATOR's, so fuzz.py already knows it and
# there is nothing for this file to tell it.
dir:
let
  b = builtins;
  cc = import ./compile.nix;

  names = b.filter (n: b.match ".*\\.c" n != null) (b.attrNames (b.readDir dir));

  answer = n:
    let s = cc.run (b.readFile (dir + "/${n}")); in
    {
      name = b.substring 0 (b.stringLength n - 2) n;
      value = {
        listing = cc.linesOf s;
        diags = cc.diagsOf s;
      };
    };
in
b.listToAttrs (map answer names)
