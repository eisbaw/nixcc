# lcc/src/sym.c and the mutable state the rest of the frontend threads.
#
# lcc's frontend is a pile of globals: symbol tables, the code list, the dag's
# hash buckets, three counters and `refinc'. None of that transliterates, so
# every function that can change the state takes it FIRST.
#
# THE RETURN CONVENTION IS NOT UNIFORM, and pretending otherwise in this
# paragraph is how a caller comes to write `(sy.warn s "x").s'. A function that
# produces a VALUE as well as a new state returns `{ s; v; }'; a function that
# only transforms the state returns the state itself. `warn', `setsym',
# `modsym', `enterscope' and most of dag.nix are the second kind; `newsym',
# `install', `genlabel', `findlabel' and `code' are the first.
#
# THE ONE THING THAT MAKES THIS WORK: symbols, trees and dag nodes are interned
# to integer ids and stored in attrsets on the state. lcc compares symbol and
# node POINTERS -- dag.c's CSE hashes a machine address, tree.c's root1 tests
# `p->kids[1] == p->kids[0]->kids[0]', enode.c's addrof tests `p == q' -- and
# Nix has neither addresses nor mutable cells. With ids, identity is `==' on an
# integer and mutation is one attrset update, which is decision-002's "rewrite,
# not port" in its most concrete form.
let
  b = builtins;

  # lcc's scope ladder, c.h. Numeric because `scope >= PARAM' and
  # `level > LOCAL' are order tests.
  CONSTANTS = 1;
  LABELS = 2;
  GLOBAL = 3;
  PARAM = 4;
  LOCAL = 5;
in
self:
let
  ty = self.types;
  st = self.store;
in
rec {
  inherit CONSTANTS LABELS GLOBAL PARAM LOCAL;

  # Code-item kinds, in lcc's enum order: `cp->kind < Label' and
  # `cp->kind <= Label' are order tests that stmt.c's branch() and definelab()
  # depend on, so the order is load-bearing and is written out rather than
  # implied by a list.
  kindOrder = {
    Blockbeg = 0;
    Blockend = 1;
    Local = 2;
    Address = 3;
    Defpoint = 4;
    Label = 5;
    Start = 6;
    Gen = 7;
    Jump = 8;
    Switch = 9;
  };
  kindNum = k: kindOrder.${k} or (throw "sym: no such code kind `${k}'");

  # The storage-class spellings symbolic.c prints (token.h's `%k'), declared
  # once. They appear as bare string literals in about two dozen places across
  # the parser, which is two dozen chances for a typo to become a `sclass='
  # field nothing compares -- the oracle would catch it, but only because the
  # oracle happens to exist.
  sclasses = {
    auto = "auto";
    extern = "extern";
    register = "register";
    static = "static";
    typedef = "typedef";
    none = "";
  };

  emptySymbol = {
    name = "";
    type = null;
    sclass = "";
    scope = 0;
    ref = 0.0;
    defined = false;
    addressed = false;
    computed = false;
    temporary = false;
    generated = false;
    structarg = false;
    offset = 0;
    srcline = 0; # lcc's Symbol.src, reduced to a line (task-012)
    ncalls = 0; # only meaningful on a function symbol
    flabel = null; # the return label funcdefn allocates for a function
    alias = null; # EXTERN symbols point at the `externals' entry
    labelnum = null; # LABELS symbols carry their number
    equatedto = null; # u.l.equatedto
    value = null; # ENUM symbols carry their value, CONSTANTS theirs
    loc = null; # u.c.loc: the generated static a string constant is laid out under
  };

  initial = {
    syms = st.empty;
    nextsym = 1;
    trees = st.empty;
    nexttree = 1;
    nodes = st.empty;
    nextnode = 1;
    buckets = { }; # dag.c's CSE table: structural key -> node id
    nodecount = 0;
    forest = [ ]; # node ids; the LAST element is lcc's `forest'
    code = [ ]; # code items, in order; the last is lcc's `codelist'
    labelctr = 1; # genlabel's static counter
    tempid = 0;
    refinc = 1.0;
    regcount = 0;
    level = GLOBAL;
    scopes = [ ]; # [ { level; tbl = { name -> symid }; } ], innermost first
    globals = { }; # `identifiers' at GLOBAL
    globalOrder = [ ]; # installation order, so finalize can walk it in reverse
    externals = { };
    externalOrder = [ ];
    labels = { }; # per-function: label number -> symid
    constants = { }; # interned constant symbols: key -> symid
    constOrder = [ ]; # installation order, so finalize can walk it in reverse
    out = [ ]; # the .sym listing, one CHUNK of lines per function
    buf = [ ]; # lines of the function being emitted; see listing.nix's `emit'
    diags = [ ]; # { line; text; } -- rcc's stderr, for criterion #7
    line = 0; # lcc's src.y: the line of the token last read
    errcnt = 0;
    warncount = 0; # tree.c's `warn', reset by root()
    cfunc = null;
    needconst = 0;
    explicitCast = 0;
    autos = [ ];
    registers = [ ];
  };

  # --- symbols -----------------------------------------------------------
  getsym = s: id: st.get "symbol" s.syms id;

  setsym = s: id: v: s // { syms = st.set s.syms id v; };

  modsym = s: id: f: setsym s id (f (getsym s id));

  newsym = s: attrs:
    let id = s.nextsym; in
    {
      s = s // {
        nextsym = id + 1;
        syms = st.set s.syms id (emptySymbol // attrs // { inherit id; });
      };
      v = id;
    };

  # --- scopes ------------------------------------------------------------
  enterscope = s: s // {
    level = s.level + 1;
    tempid = if s.level + 1 == LOCAL then 0 else s.tempid;
    scopes = [ { level = s.level + 1; tbl = { }; } ] ++ s.scopes;
  };

  exitscope = s: s // {
    level = s.level - 1;
    scopes = if s.scopes == [ ] then [ ] else b.tail s.scopes;
  };

  # install into the innermost scope whose level is `lev'. lcc's install()
  # takes the table and walks `previous' links; here the scope stack is the
  # table chain, and GLOBAL lives outside it in `globals'.
  install = s: name: lev: attrs:
    let r = newsym s (attrs // { inherit name; scope = lev; }); in
    if lev <= GLOBAL then {
      s = r.s // {
        globals = r.s.globals // { ${name} = r.v; };
        globalOrder = r.s.globalOrder ++ [ r.v ];
      };
      inherit (r) v;
    }
    else
      let
        hit = b.filter (i: (b.elemAt r.s.scopes i).level == lev)
          (b.genList (i: i) (b.length r.s.scopes));
      in
      if hit == [ ] then throw "sym: no scope at level ${toString lev} to install `${name}' into"
      else
        let
          k = b.head hit;
          sc = b.elemAt r.s.scopes k;
        in
        {
          s = r.s // {
            scopes = b.genList
              (i: if i == k then sc // { tbl = sc.tbl // { ${name} = r.v; }; } else b.elemAt r.s.scopes i)
              (b.length r.s.scopes);
          };
          inherit (r) v;
        };

  # lookup searches innermost first, then the globals.
  lookup = s: name:
    let
      found = b.filter (sc: sc.tbl ? ${name}) s.scopes;
    in
    if found != [ ] then (b.head found).tbl.${name}
    else s.globals.${name} or null;

  # The symbol a name resolves to in the CURRENT scope only, which is what
  # decl.c's redeclaration checks want.
  lookupIn = s: name: lev:
    let hit = b.filter (sc: sc.level == lev && sc.tbl ? ${name}) s.scopes; in
    if hit != [ ] then (b.head hit).tbl.${name}
    else if lev <= GLOBAL then s.globals.${name} or null
    else null;

  lookupExternal = s: name: s.externals.${name} or null;

  installExternal = s: name: attrs:
    let r = newsym s (attrs // { inherit name; scope = GLOBAL; }); in
    {
      s = r.s // {
        externals = r.s.externals // { ${name} = r.v; };
        externalOrder = r.s.externalOrder ++ [ r.v ];
      };
      inherit (r) v;
    };

  # --- generators --------------------------------------------------------
  # genlabel is a FILE-wide counter in lcc (`static int label = 1'), not a
  # per-function one, so the second function in a translation unit does not
  # start at 1. Getting that wrong shifts every label in the listing.
  genlabel = s: n: { s = s // { labelctr = s.labelctr + n; }; v = s.labelctr; };

  findlabel = s: n:
    if s.labels ? ${toString n} then { inherit s; v = s.labels.${toString n}; }
    else
      let
        r = newsym s {
          name = toString n;
          scope = LABELS;
          generated = true;
          labelnum = n;
        };
      in
      { s = r.s // { labels = r.s.labels // { ${toString n} = r.v; }; }; inherit (r) v; };

  genident = s: sclass: t: lev:
    let
      g = genlabel s 1;
      r = newsym g.s {
        name = toString g.v;
        scope = lev;
        inherit sclass;
        type = t;
        generated = true;
      };
    in
    r;

  temporary = s: sclass: t:
    let
      id = s.tempid + 1;
      r = newsym (s // { tempid = id; }) {
        name = toString id;
        scope = if s.level < LOCAL then LOCAL else s.level;
        inherit sclass;
        type = t;
        temporary = true;
        generated = true;
      };
    in
    r;

  # --- constants ---------------------------------------------------------
  # sym.c's constant(): interned by (type, value) so that two occurrences of
  # `1' are one Symbol, which is what makes two CNSTI4 nodes CSE into one.
  vtoa = t: v:
    let u = ty.unqual t; in
    if u.op == "INT" then toString v
    else if u.op == "UNSIGNED" then
      (if b.bitAnd v (0 - 32768) != 0 then "0x${toHex v}" else toString v)
    # output.c's `%p': `0' for the null pointer and `0x' plus lower-case hex
    # for anything else. NOT `0x0' -- lcc prints the prefix only when the
    # pointer is non-null, and this name is what `CNSTP4 0' in the listing IS.
    else if u.op == "POINTER" then (if v == 0 then "0" else "0x${toHex v}")
    # sym.c's vtoa returns the string itself for an array of char -- v.p, the
    # interned bytes. A byte list cannot be a Nix string (decision-001), and
    # this name is never PRINTED: a string constant's symbol appears in no
    # node's syms, because expr.c hands the tree its generated `loc' instead.
    # So the name exists to be hashed, and it is spelled as the byte list.
    else if u.op == "ARRAY" then "[${b.concatStringsSep "," (map toString v)}]"
    else throw "sym: vtoa has no spelling for a `${u.op}' constant";

  # lcc's own printf (lcc/src/output.c's outu) is LOWER case for both %x and
  # %X, so `0xffffffff' rather than `0xFFFFFFFF'. Reading the C format string
  # and assuming libc's semantics is how that one gets wrong.
  hexDigits = "0123456789abcdef";
  toHex = n:
    let
      go = x: acc:
        if x == 0 then acc
        else go (x / 16) (b.substring (b.bitAnd x 15) 1 hexDigits + acc);
    in
    if n == 0 then "0" else go n "";

  # The interning key is the TYPE and the value's own spelling, which is what
  # lcc's constant() compares -- eqtype plus the value. `ty.outtype' rather
  # than `u.name' because an array type has no name, and two literals of
  # different lengths must not share a bucket.
  constantSym = s: t: v:
    let
      u = ty.unqual t;
      key = "${u.op}:${toString u.size}:${ty.outtype u}:${vtoa u v}";
    in
    if s.constants ? ${key} then { inherit s; v = s.constants.${key}; }
    else
      let
        r = newsym s {
          name = vtoa u v;
          scope = CONSTANTS;
          sclass = "static";
          type = u;
          value = v;
          defined = true;
        };
      in
      {
        s = r.s // {
          constants = r.s.constants // { ${key} = r.v; };
          constOrder = r.s.constOrder ++ [ r.v ];
        };
        inherit (r) v;
      };

  intconst = s: n: constantSym s ty.inttype n;

  # sym.c's mkstr() and the SCON arm of expr.c's primary(), which do the same
  # two things: intern the constant, then give it a generated STATIC symbol at
  # GLOBAL scope to live under in the lit segment. The second call for the same
  # literal finds the constant already interned AND already located, so two
  # occurrences of "abc" share one `defstring' -- which is the whole reason
  # constant() is a hash table rather than a list.
  stringSym = s0: t: units:
    let
      c = constantSym s0 t units;
      q = getsym c.s c.v;
    in
    if q.loc != null then { inherit (c) s v; }
    else
      let g = genident c.s sclasses.static q.type GLOBAL; in
      { s = modsym g.s c.v (x: x // { loc = g.v; }); inherit (c) v; };

  # stmt.c's addlocal(). It lives here and not in dag.nix because all it does
  # is append a code item and re-scope a symbol: simp.c's addrtree calls it as
  # well as dag.c's listnodes, and a shared helper reached through two layers
  # is worse than one that sits under both.
  addlocal = s: p:
    let q = getsym s p; in
    if q.defined then s
    else
      let c = code s "Local" { var = p; }; in
      modsym c.s p (x: x // { defined = true; scope = c.s.level; });

  # --- code list ---------------------------------------------------------
  # stmt.c's reachable(): scan back over the non-control items; if what you
  # land on is a Jump or a Switch, nothing can reach here.
  # lcc walks BACK from the tail and stops at the first item that is Label or
  # later, which is usually one step. Building the whole index list and
  # filtering it gives the same answer and costs O(code length) on every
  # code() call -- and code() is called two or three times per statement, so
  # that is quadratic in the size of a function. Measured on a 1600-statement
  # function it was the single largest term.
  reachable = s: kind:
    if kindNum kind <= kindNum "Start" then true
    else
      let
        go = i:
          if i < 0 then null
          else if kindNum (b.elemAt s.code i).kind >= kindNum "Label" then i
          else go (i - 1);
        hit = go (b.length s.code - 1);
      in
      hit == null || (
        let k = (b.elemAt s.code hit).kind; in
        !(k == "Jump" || k == "Switch")
      );

  # code(kind) in stmt.c, including its unreachable-code warning.
  code = s: kind: item:
    let s' = if reachable s kind then s else warn s "unreachable code\n"; in
    { s = s' // { code = s'.code ++ [ ({ inherit kind; } // item) ]; }; v = b.length s'.code; };

  # --- diagnostics -------------------------------------------------------
  # error.c prints `%w: ' -- the file, which is empty when rcc reads stdin,
  # then the line -- followed by the message. Recorded rather than printed:
  # Nix has no stderr, and criterion #7 wants these DIFFED against rcc's.
  warn = s: text: s // {
    diags = s.diags ++ [ { inherit (s) line; text = "warning: " + text; } ];
  };

  # An ERROR throws, where lcc records it and carries on. That is a deliberate
  # divergence and the house rule -- refuse loudly rather than miscompile --
  # and it is safe for the oracle diff, which only ever compares programs both
  # frontends accept. It does mean our stderr carries warnings only; lcc's
  # error TEXT is therefore not part of what criterion #7 compares, and any
  # future slice that wants error recovery has to undo this first.
  err = s: text: throw "line ${toString s.line}: ${text}";

  # Every REFUSAL carries the line it happened on, for the reason task-011
  # handed this slice as an open question: a Nix throw cannot be caught and
  # re-thrown with a position -- builtins.tryEval discards the message
  # entirely -- so the position has to be attached where the token is still in
  # scope. That is why this takes the state rather than being a free function,
  # and why `const.nix' is never asked to raise a diagnostic of its own: the
  # parser raises it, at the site that knows which token it was looking at.
  refuse = s: text: throw "line ${toString s.line}: ${text}";
}
