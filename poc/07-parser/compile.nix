# The entry point: C source text in, lcc's `-target=symbolic' listing out.
#
# The modules are tied together with one recursive `let', because lcc's
# frontend is not a layered stack -- dag.c calls expr.c's idtree() and stmt.c's
# jump(), expr.c calls simp.c, simp.c calls enode.c -- and pretending otherwise
# would mean duplicating something. Nix's laziness makes the knot legal: each
# `import ... self' returns an attrset whose fields only look at `self' when
# they are forced.
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

  linesOf = s: b.concatStringsSep "\n" (b.concatLists s.out ++ s.buf) + "\n";

  # rcc's stderr, in rcc's own format (`LINE: warning: TEXT'), so criterion
  # #7's comparison is a string diff rather than a judgement call.
  diagnosticsOf = src:
    let s = run src; in
    b.concatStringsSep "" (map (d: "${toString d.line}: ${d.text}") s.diags);

  # Everything the front end held live at the end of a translation unit,
  # forced. Criterion #5 asks for memory "with tokens/AST/DAG live
  # simultaneously", and that is what this is: trees and dag nodes are never
  # released -- there is no arena to free -- so the final state IS the peak.
  census = src:
    let s = run src; in
    b.deepSeq s {
      tokens = b.length s.toks;
      trees = s.nexttree - 1;
      nodes = s.nextnode - 1;
      symbols = s.nextsym - 1;
      lines = b.length (b.filter b.isString (b.split "\n" src));
      out = b.length (b.concatLists s.out);
    };

  # What the backend consumes. Routed through poc/03-matcher's listing parser
  # on purpose -- see the header.
  forestsOf = src: (import ../03-matcher/parse.nix).parseAll (listingOf src);
}
