# Scale driver. Takes a .sym listing, labels every node of every forest in it,
# and prints one line of counts.
#
#   nix eval --impure --raw --expr 'import ./bench.nix { path = "/abs/x.sym"; }'
#
# `path` is a string rather than a path because it comes from the shell, and
# `/. + path` turns it back into one.
#
# Labelling, not the whole compile, because the point is to measure the dynamic
# programming at a scale no hand-written test reaches, and lcc's own corpus is
# full of opcodes this PoC's rule table does not cover -- floats, conversions,
# block moves. Labelling is defined for those: they simply get no rules. It is
# also the pass whose cost worries us, because it holds a cost-and-rule entry
# per (node, nonterminal) live at once, which is the memory shape decision-001
# says to watch.
#
# The count is of ENTRIES, not of nodes, so it cannot be satisfied by a
# labeller that returns an empty table: an empty table would report zero and
# the caller rejects that.
{ path }:
let
  b = builtins;
  parse = import ./parse.nix;
  table = import ./rules.nix;
  text = b.readFile (/. + path);

  # The frame is real code's business; at this scale we only need %a to be
  # answerable, so it answers with the symbol's own text.
  stubTarget = {
    depthRegs = [ "s1" ];
    cseRegs = [ "s2" ];
    argReg = i: "a${toString i}";
    label = _: n: ".L${n}";
    epilogue = f: ".L${f}_epilogue";
    operand = node: if node.syms == [ ] then "0" else b.head node.syms;
    inherit ((import ./emit.nix { })) constValue;
  };
  burg = import ./burg.nix { inherit table; target = stubTarget; };

  forests = b.concatLists (map (f: f.forests) (parse.parseAll text));
  counted = map
    (forest:
      let labels = burg.labelForest forest; in
      b.foldl' (a: id: a + b.length (b.attrNames labels.${id})) 0 forest.order)
    forests;
  entries = b.foldl' (a: c: a + c) 0 counted;
  nodes = b.foldl' (a: f: a + b.length f.order) 0 forests;
in
b.deepSeq counted "${toString (b.stringLength text)}\t${toString nodes}\t${toString entries}\n"
