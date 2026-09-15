# Scale driver. Takes a .s file, assembles it, and prints one line of counts.
#
#   nix eval --impure --raw --expr 'import ./bench.nix { path = "/abs/x.s"; }'
#
# `path` is a string rather than a path because it comes from the shell, and
# `/. + path` turns it back into one.
#
# The WHOLE assembly is forced, image bytes included, because the byte list is
# where the memory goes: one Nix integer per byte is four live values per
# instruction, and decision-001's closing point is that the evaluator's
# per-live-value overhead is the budget to watch. Forcing only the placements
# would measure the cheap half and report a number nobody could plan with.
#
# The counts are of ITEMS, symbols and BYTES, none of which an assembler that
# quietly emitted nothing could satisfy: the caller rejects zeros and checks
# the byte count against the instruction count it generated.
{ path }:
let
  b = builtins;
  asm = import ./asm.nix { };
  parse = import ./parse.nix { inherit asm; };
  text = b.readFile (/. + path);
  items = parse.parse (b.baseNameOf path) text;
  r = asm.assemble { inherit items; };
in
b.deepSeq r.bytes "${toString (b.stringLength text)}\t${toString (b.length items)}\t${
  toString (b.length (b.attrNames r.symbols))}\t${toString (b.length r.bytes)}\n"
