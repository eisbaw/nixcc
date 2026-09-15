# The entry point: C source text in, lcc's `-target=symbolic' listing out.
#
# The modules are tied together with one recursive `let'. The dependency graph
# is very nearly a DAG -- ops depends on types; sym on types and store; dag on
# trees, sym, ops, types and store; listing on dag; parse on everything -- and
# exactly ONE back-edge makes it a knot: trees <-> simp. enode.c's constructors
# call simplify() and simp.c calls cnsttree(), root(), cond(), bittree() and
# eqtree(). That one is irreducible and is what the fixpoint is for.
#
# It is worth being precise about this rather than saying "lcc's call graph is
# cyclic", which an earlier version of this comment did: dag.c's calls to
# idtree() and jump() are NOT a cycle here, because jump lives in dag.nix and
# dag -> trees is a forward edge. A reader told the graph is worse than it is
# will not bother to cut the layers that are already cut.
#
# WHY THE LISTING TEXT IS THE INTERFACE, rather than handing the backend an
# attrset directly. poc/03-matcher/parse.nix already reads this format, and it
# CHECKS it: node numbering, reference counts, dangling `#n', post-order. So
# routing our own output through it means the text the oracle diff compares is
# the very text the backend compiles, and a malformed listing is caught by an
# existing, mutation-tested parser rather than by a new one written today.
let
  b = builtins;
  lexer = import ../02-lexer/lex.nix;

  self = {
    types = import ./types.nix;
    store = import ./store.nix;
    ops = import ./ops.nix self;
    sym = import ./sym.nix self;
    simp = import ./simp.nix self;
    trees = import ./trees.nix self;
    dag = import ./dag.nix self;
    parse = import ./parse.nix self;
    listing = import ./listing.nix self;
    const = import ../06-constants/const.nix;
  };
in
rec {
  inherit self;

  start = src:
    let
      toks = lexer.lex src;
      first = b.head toks;
    in
    self.sym.initial // {
      inherit toks;
      ti = 0;
      inherit (first) line;
      curseg = 0;
      dagdepth = 0;
    };

  # The whole translation unit. `deepSeq' is not decoration: the state is a
  # chain of attrset updates as long as the token stream, and decision-001
  # measured that forcing such a chain late is "stack overflow", not slowness.
  run = src:
    let
      s0 = start src;
      s1 = self.parse.program s0;
      s2 = self.listing.finalize s1;
    in
    b.deepSeq s2.out s2;

  # The listing, exactly as rcc-rv32 would print it: one line per entry, one
  # trailing newline.
  listingOf = src: linesOf (run src);

  # `buf' must be empty here: listing.nix flushes it at the end of every
  # function and once more in finalize. Appending it anyway would have hidden a
  # missing flush -- and did, until a mutation that deleted the append changed
  # nothing at all.
  linesOf = s:
    if s.buf != [ ]
    then throw "compile: ${toString (b.length s.buf)} listing line(s) were never flushed out of the buffer; a stage returned without calling listing.flush"
    else b.concatStringsSep "\n" (b.concatLists s.out) + "\n";

  # rcc's stderr, in rcc's own format (`LINE: warning: TEXT'), so criterion
  # #7's comparison is a string diff rather than a judgement call. `diagsOf'
  # takes a finished state so that oracle.nix and fuzz.nix can render the
  # diagnostics off the SAME `run' that produced the listing; they each had
  # their own copy of this one-liner, which is one copy too many for a format
  # the whole differential rests on.
  diagsOf = s: b.concatStringsSep "" (map (d: "${toString d.line}: ${d.text}") s.diags);

  diagnosticsOf = src: diagsOf (run src);

  # Everything the front end held live at the end of a translation unit,
  # forced. Criterion #5 asks for memory "with tokens/AST/DAG live
  # simultaneously", and that is what this is: trees and dag nodes are never
  # released -- there is no arena to free -- so the final state IS the peak.
  census = src:
    let s = run src; in
    b.deepSeq s {
      tokens = b.length s.toks;
      # BUILT is every tree and node the whole translation unit ever made;
      # LIVE is what is still reachable at the end. funcdefn releases a
      # finished function's trees and nodes, so the two differ and the PEAK
      # sits in the middle -- during the largest single function, not here.
      # That is why memory.py's ladder has a one-big-function point as well as
      # a many-small-functions one: the second measures the wrong thing on its
      # own.
      treesBuilt = s.nexttree - 1;
      nodesBuilt = s.nextnode - 1;
      treesLive = b.length (self.store.values s.trees);
      nodesLive = b.length (self.store.values s.nodes);
      symbols = s.nextsym - 1;
      lines = b.length (b.filter b.isString (b.split "\n" src));
      out = b.length (b.concatLists s.out);
    };

  # What the backend consumes. Routed through poc/03-matcher's listing parser
  # on purpose -- see the header.
  forestsOf = src: (import ../03-matcher/parse.nix).parseAll (listingOf src);
}
