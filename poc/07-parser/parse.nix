# lcc/src/decl.c, lcc/src/stmt.c and the parsing half of lcc/src/expr.c.
#
# Recursive descent, over the tokens poc/02-lexer produces -- there is no
# second lexer here, and `lex' is imported rather than re-implemented
# (criterion #1). Descent is safe under decision-001: its depth tracks
# EXPRESSION NESTING, which is well under a hundred for real C, not input
# length. What is banned is a traversal whose depth grows with the file, and
# the statement and declarator loops below are iterative for that reason.
#
# THE PARSER AND THE DAG BUILDER ARE INTERLEAVED, exactly as lcc interleaves
# them, and that is not a stylistic choice. lcc's forests span statement
# boundaries: stmt.c's expression-statement case calls listnodes and only calls
# walk() when `nodecount == 0 || nodecount > 200', so five consecutive
# assignments become ONE forest with one node numbering and CSE across all of
# them. poc/03-matcher/ir/expr.sym shows it: the assignments and the `if''s
# comparison share `2. ADDRLP4 count=10 x'. A parser that built a whole AST and
# then walked it would get the forest boundaries wrong and every node number
# after the first would differ.
#
# TWO TOKEN FACTS INHERITED FROM task-002, neither worked around here:
#   * lcc has no compound-assignment tokens. `<<=' is LSHIFT then `=', and
#     expr3's loop condition `prec[t] == k1 && *cp != '='' disambiguates by
#     peeking at the RAW NEXT CHARACTER. Our tokens carry the trivia that
#     preceded them, so `*cp == '='' is "the next token's ws is empty and its
#     text starts with =" -- the same information, not a second copy of it.
#   * Tokens carry a line and no column (task-012). lcc threads a full
#     Coordinate; we thread the line alone, so a diagnostic reads `12: warning:
#     ...' where lcc's would read `12: warning: ...' for stdin input too. The
#     column is only ever printed by -g stab output, which this slice does not
#     emit, so the difference is invisible in the oracle diff -- but it IS a
#     difference, and task-012 is where it gets closed.
let
  b = builtins;
in
self:
let
  ty = self.types;
  inherit (self) ops;
  sy = self.sym;
  tr = self.trees;
  inherit (self) dag;
  inherit (self) simp;
  inherit (self) const;
in
rec {
  # --- token classification (token.h's `kind' column) ---------------------
  typeSpecifiers = [ "VOID" "CHAR" "SHORT" "INT" "LONG" "FLOAT" "DOUBLE" "SIGNED" "UNSIGNED" "CONST" "VOLATILE" "STRUCT" "UNION" "ENUM" ];
  storageSpecifiers = [ "AUTO" "EXTERN" "REGISTER" "STATIC" "TYPEDEF" ];
  statementStarters = [ ";" "BREAK" "CASE" "CONTINUE" "DEFAULT" "DO" "ELSE" "FOR" "GOTO" "IF" "RETURN" "SWITCH" "WHILE" "{" ];
  exprStarters = [ "ID" "!" "FCON" "ICON" "SCON" "&" "INCR" "(" "*" "+" "-" "DECR" "SIZEOF" "~" "TYPECODE" "FIRSTARG" ];

  # Every token kind this file names, so that check.nix can hold them against
  # the set poc/02-lexer can actually produce. A typo in one of the lists above
  # does not fail: `kindOf' simply returns the token, the case never matches,
  # and the construct is quietly unreachable.
  namedKinds = typeSpecifiers ++ storageSpecifiers ++ statementStarters
    ++ exprStarters ++ b.attrNames binops
    ++ [ "ELSE" "WHILE" ":" ")" "]" "}" "?" "EOI" "DEREF" ];

  kindOf = k:
    if b.elem k typeSpecifiers then "CHAR"
    else if b.elem k storageSpecifiers then "STATIC"
    else if b.elem k statementStarters then "IF"
    else if b.elem k exprStarters then "ID"
    else k;

  # token.h's prec and oper columns, and the optree function each token picks.
  binops = {
    "%" = { prec = 13; gen = "MOD"; ctor = "bittree"; };
    "&" = { prec = 8; gen = "BAND"; ctor = "bittree"; };
    "*" = { prec = 13; gen = "MUL"; ctor = "multree"; };
    "+" = { prec = 12; gen = "ADD"; ctor = "addtree"; };
    "-" = { prec = 12; gen = "SUB"; ctor = "subtree"; };
    "/" = { prec = 13; gen = "DIV"; ctor = "multree"; };
    "ANDAND" = { prec = 5; gen = "AND"; ctor = "andtree"; };
    "OROR" = { prec = 4; gen = "OR"; ctor = "andtree"; };
    "LEQ" = { prec = 10; gen = "LE"; ctor = "cmptree"; };
    "EQL" = { prec = 9; gen = "EQ"; ctor = "eqtree"; };
    "NEQ" = { prec = 9; gen = "NE"; ctor = "eqtree"; };
    "GEQ" = { prec = 10; gen = "GE"; ctor = "cmptree"; };
    "RSHIFT" = { prec = 11; gen = "RSH"; ctor = "shtree"; };
    "LSHIFT" = { prec = 11; gen = "LSH"; ctor = "shtree"; };
    "<" = { prec = 10; gen = "LT"; ctor = "cmptree"; };
    "=" = { prec = 2; gen = "ASGN"; ctor = "asgntree"; };
    ">" = { prec = 10; gen = "GT"; ctor = "cmptree"; };
    "^" = { prec = 7; gen = "BXOR"; ctor = "bittree"; };
    "|" = { prec = 6; gen = "BOR"; ctor = "bittree"; };
    "," = { prec = 1; gen = null; ctor = null; };
  };
  precOf = k: (binops.${k} or { prec = 0; }).prec;

  # EVERY TABLE LOOKUP IN THIS FILE CARRIES `or (throw ...)', including the
  # ones that are provably safe today. builtins.tryEval does NOT catch an
  # attribute-missing error (task-037): it propagates through and takes the
  # whole must-fail suite down rather than being reported, so a refusal spelled
  # as a bare select is a refusal no test can see. The proof that a lookup is
  # safe is exactly the kind that rots.
  ctorOf = name: {
    inherit (tr) bittree;
    inherit (tr) multree;
    inherit (tr) addtree;
    inherit (tr) subtree;
    inherit (tr) andtree;
    inherit (tr) cmptree;
    inherit (tr) eqtree;
    inherit (tr) shtree;
    inherit (tr) asgntree;
  }.${name} or (throw "parse: `${name}' is not one of enode.c's tree constructors");
  infoOf = k: binops.${k} or (throw
    "parse: `${k}' has no entry in the operator table, so its precedence and its tree constructor are unknown");

  apply2 = name: s: gname: l: r: (ctorOf name) s (ops.bare gname) l r;

  # --- the token cursor --------------------------------------------------
  cur = s: b.elemAt s.toks s.ti;
  tk = s: (cur s).kind;
  text = s: (cur s).text;

  advance = s:
    let
      i = s.ti + 1;
      next = b.elemAt s.toks i;
    in
    if i >= b.length s.toks then s // { ti = i - 1; }
    else s // { ti = i; inherit (next) line; };

  # The token after the current one, bound-checked. The lexer always ends the
  # stream with EOI so running off is only reachable at the very end -- but
  # three sites indexed `ti + 1' raw while `nextIsEq' bound-checked, which is
  # the same class of bug guarded in one place out of four.
  peek = s:
    let i = s.ti + 1; in
    if i < b.length s.toks then b.elemAt s.toks i
    else b.elemAt s.toks (b.length s.toks - 1);

  # expr3's `*cp != '='': the raw character after the current token.
  nextIsEq = s:
    let n = peek s; in
    n.ws == "" && b.substring 0 1 n.text == "=";

  # `found `''' on a truncated file is not a diagnostic. EOI carries no text,
  # so it is named rather than quoted.
  found = s: if tk s == "EOI" then "end of input" else "`${text s}'";

  expect = s: k:
    if tk s == k then advance s
    else sy.err s "syntax error; found ${found s} expecting `${k}'\n";

  # --- expressions -------------------------------------------------------
  expr = s0: tok:
    let
      e = expr1 s0 null;
      loop = st: p:
        if tk st != "," then { s = st; v = p; }
        else
          let
            a = expr1 (advance st) null;
            c = tr.pointer a.s a.v;
            d = tr.value c.s p;
            f = tr.root d.s d.v;
            g = tr.tree f.s (ops.bare "RIGHT") (tr.get f.s c.v).type f.v c.v;
          in
          loop g.s g.v;
      r = loop e.s e.v;
    in
    if tok != null then r // { s = expect r.s tok; } else r;

  expr0 = s: tok: let r = expr s tok; in tr.root r.s r.v;

  expr1 = s0: tok:
    let
      e = expr2 s0;
      k = tk e.s;
      p = precOf k;
      r =
        if k == "=" || (p >= 6 && p <= 8) || (p >= 11 && p <= 13) then
          let
            info = infoOf k;
            s1 = advance e.s;
          in
          if info.gen == "ASGN" then
            let
              a = expr1 s1 null;
              c = tr.value a.s a.v;
            in
            tr.asgntree c.s (ops.bare "ASGN") e.v c.v
          else
            let
              s2 = expect s1 "=";
              a = expr1 s2 null;
            in
            tr.incr a.s info.gen (ctorOf info.ctor) e.v a.v
        else e;
    in
    if tok != null then r // { s = expect r.s tok; } else r;

  expr2 = s0:
    let p = expr3 s0 4; in
    if tk p.s != "?" then p
    else
      let
        a = tr.pointer p.s p.v;
        s1 = advance a.s;
        l = expr s1 ":";
        lp = tr.pointer l.s l.v;
        r = expr2 lp.s;
        rp = tr.pointer r.s r.v;
      in
      tr.condtree rp.s a.v lp.v rp.v;

  # expr3's two nested loops, k1 walking DOWN from the current token's
  # precedence. Rewritten as a fold over the precedence levels because Nix has
  # no `for', but the traversal order is lcc's.
  expr3 = s0: k:
    let
      u = unary s0;
      levels = st: p: k1:
        if k1 < k then { s = st; v = p; }
        else
          let r = sameLevel st p k1; in
          levels r.s r.v (k1 - 1);
      sameLevel = st: p: k1:
        if !(precOf (tk st) == k1 && !(nextIsEq st)) then { s = st; v = p; }
        else
          let
            info = infoOf (tk st);
            opk = tk st;
            s1 = advance st;
            a = tr.pointer s1 p;
            c =
              if opk == "ANDAND" || opk == "OROR"
              then (let x = expr3 a.s k1; in tr.pointer x.s x.v)
              else (let x = expr3 a.s (k1 + 1); in tr.pointer x.s x.v);
            d = apply2 info.ctor c.s info.gen a.v c.v;
          in
          sameLevel d.s d.v k1;
    in
    levels u.s u.v (precOf (tk u.s));

  # expr.c's four arithmetic prefix operators share one skeleton, and lcc
  # shares it too -- `p = unary(); p = pointer(p); if (PRED) BODY else
  # typeerror(OP, p, NULL)'. As four copies it was forty-five lines in which
  # the only differences were a predicate and a body; as a table it is four
  # rows you can read beside expr.c's four cases.
  prefixOps = {
    "+" = {
      gen = "ADD";
      pred = ty.isarith;
      # Unary `+' is not a no-op: it promotes.
      body = s: p: t: tr.cast s p (ty.promote t);
    };
    "-" = {
      gen = "SUB";
      pred = ty.isarith;
      # On an unsigned operand lcc says so and rewrites `-x' as `~x + 1',
      # because NEG has no unsigned form in ops.h.
      body = s: p: t0:
        let
          t = ty.promote t0;
          d = tr.cast s p t;
        in
        if ty.isunsigned t then
          let
            s1 = sy.warn d.s "unsigned operand of unary -\n";
            n = simp.simplify s1 (ops.bare "BCOM") t d.v null;
            one = tr.cnsttree n.s t 1;
          in
          simp.simplify one.s (ops.bare "ADD") t n.v one.v
        else simp.simplify d.s (ops.bare "NEG") t d.v null;
    };
    "~" = {
      gen = "BCOM";
      pred = ty.isint;
      body = s: p: t0:
        let
          t = ty.promote t0;
          d = tr.cast s p t;
        in
        simp.simplify d.s (ops.bare "BCOM") t d.v null;
    };
    "!" = {
      gen = "NOT";
      pred = ty.isscalar;
      # `!e' is a CONDITION, so it goes through cond() and comes out typed int
      # whatever the operand was.
      body = s: p: _t: let d = tr.cond s p; in simp.simplify d.s (ops.bare "NOT") ty.inttype d.v null;
    };
  };

  prefix = s0: k:
    let
      info = prefixOps.${k} or (throw "parse: `${k}' is not a prefix operator");
      a = unary (advance s0);
      c = tr.pointer a.s a.v;
      t = (tr.get c.s c.v).type;
    in
    if info.pred t then info.body c.s c.v t
    else { s = tr.typeerror c.s info.gen c.v null; inherit (c) v; };

  unary = s0:
    let k = tk s0; in
    if k == "*" then
      let
        a = unary (advance s0);
        c = tr.pointer a.s a.v;
        t = (tr.get c.s c.v).type;
      in
      if ty.isptr t && (ty.isfunc (ty.unqual t).type || ty.isarray (ty.unqual t).type)
      then tr.retype c.s c.v (ty.unqual t).type
      else tr.rvalue c.s c.v
    else if k == "&" then
      let
        a = unary (advance s0);
        t = (tr.get a.s a.v).type;
        c = if ty.isarray t || ty.isfunc t then tr.retype a.s a.v (ty.ptr t) else tr.lvalue a.s a.v;
        inherit ((tr.get c.s c.v)) sym;
      in
      if ops.isaddrop (tr.get c.s c.v).op then
        (
          if (sy.getsym c.s sym).sclass == sy.sclasses.register
          then { s = sy.err c.s "invalid operand of unary &; `${(sy.getsym c.s sym).name}' is declared register\n"; inherit (c) v; }
          else { s = sy.modsym c.s sym (q: q // { addressed = true; }); inherit (c) v; }
        )
      else c
    else if prefixOps ? ${k} then prefix s0 k
    else if k == "INCR" || k == "DECR" then
      let
        a = unary (advance s0);
        c = tr.pointer a.s a.v;
        one = tr.consttree c.s 1 ty.inttype;
      in
      tr.incr one.s (if k == "INCR" then "ADD" else "SUB")
        (if k == "INCR" then tr.addtree else tr.subtree) c.v one.v
    else if k == "SIZEOF" then
      let
        s1 = advance s0;
        r =
          if tk s1 == "(" && isTypename (advance s1) then
            let
              n = typename (advance s1);
              s2 = expect n.s ")";
            in
            { s = s2; t = n.v; }
          else if tk s1 == "(" then
            let
              e = expr (advance s1) ")";
              pf = postfix e.s e.v;
            in
            { inherit (pf) s; t = (tr.get pf.s pf.v).type; }
          else
            let u = unary s1; in { inherit (u) s; t = (tr.get u.s u.v).type; };
      in
      if ty.isfunc r.t || r.t.size == 0
      then { s = sy.err r.s "invalid type argument `${ty.outtype r.t}' to `sizeof'\n"; v = null; }
      else tr.cnsttree r.s ty.unsignedlong r.t.size
    # ONE `(' arm, as expr.c has one `case ...('. Splitting it in two ran
    # `advance s0' three times and re-did isTypename's symbol lookup with it.
    else if k == "(" then
      let s1 = advance s0; in
      if !(isTypename s1) then (let e = expr s1 ")"; in postfix e.s e.v)
      else
        let
          n = typename s1;
          s2 = expect n.s ")";
          t1 = n.v;
          t = ty.unqual t1;
          u = unary s2;
          pu = tr.pointer u.s u.v;
          pty = (tr.get pu.s pu.v).type;
          c =
            if (ty.isarith pty && ty.isarith t) || (ty.isptr pty && ty.isptr t)
            then
              let x = tr.cast (pu.s // { explicitCast = pu.s.explicitCast + 1; }) pu.v t; in
              { s = x.s // { inherit (pu.s) explicitCast; }; inherit (x) v; }
            else if (ty.isptr pty && ty.isint t) || (ty.isint pty && ty.isptr t)
            then tr.cast pu.s pu.v t
            else if t != ty.voidtype
            then { s = sy.err pu.s "cast from `${ty.outtype pty}' to `${ty.outtype t1}' is illegal\n"; inherit (pu) v; }
            else { inherit (pu) s; inherit (pu) v; };
        in
        if tr.gen c.s c.v == "INDIR" || t.size == 0
        then tr.tree c.s (ops.bare "RIGHT") t1 null c.v
        else tr.retype c.s c.v t1
    else
      let p = primary s0; in postfix p.s p.v;

  postfix = s0: p0:
    let
      loop = s: p:
        let k = tk s; in
        if k == "INCR" || k == "DECR" then
          let
            one = tr.consttree s 1 ty.inttype;
            i = tr.incr one.s (if k == "INCR" then "ADD" else "SUB")
              (if k == "INCR" then tr.addtree else tr.subtree) p one.v;
            inner = tr.tree i.s (ops.bare "RIGHT") (tr.get i.s p).type p i.v;
            outer = tr.tree inner.s (ops.bare "RIGHT") (tr.get inner.s p).type inner.v p;
          in
          loop (advance outer.s) outer.v
        # expr.c's `[' arm, which is four lines because all the work is in
        # enode.c's addtree: `a[i]' IS `*(a + i)', and the scaling by the
        # element size happens there. The last two lines matter and are not
        # decoration -- subscripting an array OF arrays yields the inner array
        # rather than a load, which is what makes `m[1][2]' one address
        # computation instead of a load of an array.
        else if k == "[" then
          let
            e = expr (advance s) "]";
            pp = tr.pointer e.s p;
            pq = tr.pointer pp.s e.v;
            a = tr.addtree pq.s (ops.bare "ADD") pp.v pq.v;
            at = (tr.get a.s a.v).type;
            r =
              if ty.isptr at && ty.isarray (ty.unqual at).type
              then tr.retype a.s a.v (ty.unqual at).type
              else tr.rvalue a.s a.v;
          in
          loop r.s r.v
        else if k == "." || k == "DEREF" then sy.refuse s "parse: struct members are outside slice 1"
        else if k == "(" then
          let
            pp = tr.pointer s p;
            t = (tr.get pp.s pp.v).type;
          in
          if ty.isptr t && ty.isfunc (ty.unqual t).type then
            let c = call (advance pp.s) pp.v (ty.unqual t).type; in
            loop c.s c.v
          else sy.refuse pp.s "parse: `${ty.outtype t}' is not a function"
        else { inherit s; v = p; };
    in
    loop s0 p0;

  primary = s0:
    let k = tk s0; in
    if k == "ICON" then
      let
        r = const.evalICON (text s0);
        # task-011's evaluator names the type as a STRING, and the strings
        # are lcc's spellings -- which types.nix already carries, in the `name'
        # field it uses to keep `int' and `long int' distinct. Building the
        # table from the types rather than restating their names means the two
        # cannot drift.
        #
        # `long' is the one exception: the evaluator says `long' where
        # types.nix (and lcc) say `long int'.
        constTypes = b.listToAttrs (map (x: { inherit (x) name; value = x; }) [
          ty.inttype
          ty.unsignedtype
          ty.unsignedlong
          ty.widechar
        ]) // { "long" = ty.longtype; };
        t = constTypes.${r.type} or (sy.refuse s0
          "parse: the constant evaluator returned the type `${r.type}', which is not one this frontend knows");
        # task-011's evaluator RECORDS its warnings and prints nothing. Dropping
        # them here would compile a silently clamped constant, which is the
        # regression criterion #7 exists to catch -- so they are replayed at the
        # position of the token that produced them.
        s1 = b.foldl' (st: w: sy.warn st (w + "\n")) s0 r.warnings;
        c = tr.cnsttree s1 t r.value;
      in
      { s = advance c.s; inherit (c) v; }
    else if k == "FCON" then
      sy.refuse s0 "parse: floating-point constant `${text s0}': float support is deferred (decision-006, task-015)"
    else if k == "SCON" then
      let
        # lex.c's scon() joins ADJACENT string literals and appends EXACTLY ONE
        # terminator, in that order. task-011's evaluator returns one literal's
        # units with NO terminator precisely so the join can be done here and
        # the 0 appended once: per-literal terminators would decode
        # `"ab" "cd"' as six units instead of five.
        #
        # The run is measured before it is decoded rather than accumulated
        # with `++' as it is walked, which decision-001 forbids in a loop: the
        # concatenation is one `concatLists' over a list built by genList.
        runLength = i:
          if i < b.length s0.toks && (b.elemAt s0.toks i).kind == "SCON"
          then runLength (i + 1) else i - s0.ti;
        n = runLength s0.ti;
        parts = b.genList (i: const.evalSCON (b.elemAt s0.toks (s0.ti + i)).text) n;
        widths = b.attrNames (b.listToAttrs
          (map (x: { name = toString x.width; value = true; }) parts));
        # task-047: lcc's own rule for `"ab" L"cd"' is not reproduced here
        # because there is no case behind it. Refusing is the house answer.
        s1 =
          if b.length widths != 1
          then sy.refuse s0 "parse: adjacent string literals of different widths are joined here, and this frontend has no rule for the result (task-047)"
          else s0;
        # The evaluator RECORDS its warnings and prints nothing, and criterion
        # #7 diffs lcc's stderr, so they are replayed at the literal's own
        # position -- the same argument the ICON arm above makes.
        s2 = b.foldl' (st: w: sy.warn st (w + "\n")) s1
          (b.concatLists (map (x: x.warnings) parts));
        units = b.concatLists (map (x: x.units) parts) ++ [ 0 ];
        elem = if (b.head parts).width == 2 then ty.widechar else ty.chartype;
        t = ty.array elem (b.length units) 0;
        c = sy.stringSym s2 t units;
        i = tr.idtree c.s (sy.getsym c.s c.v).loc;
        # The cursor moves past the WHOLE run, not one literal: `advance' is
        # the caller's job everywhere else in primary, so it is done here for
        # all n and the result is handed back already positioned.
        adv = b.foldl' (st: _: advance st) i.s (b.genList (x: x) n);
      in
      { s = adv; inherit (i) v; }
    else if k == "ID" then
      let
        name = text s0;
        found = sy.lookup s0 name;
      in
      if found == null then implicitId s0 name
      else
        let q = sy.getsym s0 found; in
        if q.sclass == "enum" then
          let c = tr.consttree s0 q.value ty.inttype; in { s = advance c.s; inherit (c) v; }
        else
          let i = tr.idtree s0 found; in { s = advance i.s; inherit (i) v; }
    else sy.refuse s0 "parse: illegal expression at ${found s0}";

  # An undeclared identifier. lcc guesses `int f()' when a `(' follows and
  # errors otherwise; both paths install a symbol so the rest of the parse has
  # something to hang on.
  implicitId = s0: name:
    if (peek s0).kind == "(" then
      let
        fty = ty.func ty.inttype null 1;
        p = sy.install s0 name s0.level { type = fty; sclass = sy.sclasses.extern; srcline = s0.line; };
        q = sy.lookupExternal p.s name;
        warned =
          if q != null && !(ty.eqtype (sy.getsym p.s q).type fty true)
          then sy.warn p.s "implicit declaration of `${name}' does not match previous declaration at ${
            toString (sy.getsym p.s q).srcline}\n"
          else p.s;
        e =
          if q != null then { s = warned; v = q; }
          else sy.installExternal warned name { type = fty; sclass = sy.sclasses.extern; srcline = s0.line; };
        s1 = sy.modsym e.s p.v (x: x // { alias = e.v; });
        i = tr.idtree s1 p.v;
      in
      { s = advance i.s; inherit (i) v; }
    else sy.refuse s0 "parse: undeclared identifier `${name}'";

  # --- enode.c's call(), which reads tokens and so lives here -------------
  call = s0: f: fty:
    let
      ufty = ty.unqual fty;
      inherit (ufty) proto;
      rty = ty.unqual (ty.freturn (ty.unqual fty));
      args0 = if tr.hascall s0 f then f else null;
      loop = s: n: args: r:
        let
          q0 = expr1 s null;
          q1 = tr.pointer q0.s q0.v;
          hasProtoArg = proto != null && n < b.length proto && b.elemAt proto n != ty.voidtype;
          tooMany = proto != null && n >= b.length proto;
          conv =
            if tooMany then
              sy.refuse q1.s "parse: too many arguments; the prototype takes ${
                toString (b.length proto)}"
            else if hasProtoArg then
              let
                v = tr.value q1.s q1.v;
                aty = tr.assignType v.s (b.elemAt proto n) v.v;
                c =
                  if aty != null then tr.cast v.s v.v aty
                  else { s = sy.err v.s "type error in argument ${toString (n + 1)}; found `${
                    ty.outtype (tr.get v.s v.v).type}' expected `${ty.outtype (b.elemAt proto n)}'\n"; inherit (v) v; };
              in
              if (ty.isint (tr.get c.s c.v).type || ty.isenum (tr.get c.s c.v).type)
                && (tr.get c.s c.v).type.size != ty.inttype.size
              then tr.cast c.s c.v (ty.promote (tr.get c.s c.v).type)
              else c
            else
              let v = tr.value q1.s q1.v; in
              tr.cast v.s v.v (ty.promote (tr.get v.s v.v).type);
          qt = (tr.get conv.s conv.v).type;
          r1 =
            if tr.hascall conv.s conv.v
            then (if r != null
            then (let x = tr.tree conv.s (ops.bare "RIGHT") ty.voidtype r conv.v; in { inherit (x) s; inherit (x) v; })
            else { inherit (conv) s; inherit (conv) v; })
            else { inherit (conv) s; v = r; };
          a = tr.tree r1.s (ops.mkop "ARG" qt) qt conv.v args;
        in
        if tk a.s != "," then { inherit (a) s; args = a.v; r = r1.v; n = n + 1; }
        else loop (advance a.s) (n + 1) a.v r1.v;
      done =
        if tk s0 != ")" then loop s0 0 null args0
        else { s = s0; args = null; r = args0; n = 0; };
      s1 = expect done.s ")";
      s2 =
        if proto != null && done.n < b.length proto && b.elemAt proto done.n != ty.voidtype
        then sy.err s1 "insufficient number of arguments\n" else s1;
      withR =
        if done.r != null
        then tr.tree s2 (ops.bare "RIGHT") ty.voidtype done.r done.args
        else { s = s2; v = done.args; };
    in
    tr.calltree withR.s f rty withR.v;

  # --- declarations ------------------------------------------------------
  isTypename = s:
    let k = tk s; in
    kindOf k == "CHAR"
    || (k == "ID" && (let p = sy.lookup s (text s); in p != null && (sy.getsym s p).sclass == sy.sclasses.typedef));

  specifier = s0: wantSclass:
    let
      loop = st: acc:
        let k = tk st; in
        if k == "AUTO" || k == "REGISTER" || k == "STATIC" || k == "EXTERN" || k == "TYPEDEF"
        then set st acc "cls" k
        else if k == "CONST" then set st acc "cons" k
        else if k == "VOLATILE" then set st acc "vol" k
        else if k == "SIGNED" || k == "UNSIGNED" then set st acc "sign" k
        else if k == "LONG" then
          (if acc.size == "LONG"
          then set st (acc // { size = null; }) "size" "LONGLONG"
          else set st acc "size" "LONG")
        else if k == "SHORT" then set st acc "size" "SHORT"
        else if k == "VOID" || k == "CHAR" || k == "INT" || k == "FLOAT" || k == "DOUBLE"
        then set st (acc // { base = basicOf k; }) "type" k
        else if k == "STRUCT" || k == "UNION" || k == "ENUM"
        then sy.refuse st "parse: struct, union and enum types are outside slice 1"
        else if k == "ID" && isTypename st && acc.type == null && acc.sign == null && acc.size == null
        then
          let p = sy.lookup st (text st); in
          set st (acc // { base = (sy.getsym st p).type; }) "type" k
        else { s = st; inherit acc; };
      set = st: acc: field: v:
        if acc.${field} != null
        then sy.refuse st "parse: invalid use of `${v}'"
        else if !(acc ? ${field}) then throw "parse: the specifier accumulator has no `${field}' slot"
        else loop (advance st) (acc // { ${field} = v; });
      r = loop s0 {
        cls = if wantSclass then null else "AUTO";
        cons = null;
        vol = null;
        sign = null;
        size = null;
        type = null;
        base = null;
      };
      a0 = r.acc;
      # specifier()'s `if (type == 0) { type = INT; ty = inttype; }' runs
      # BEFORE the combination rules below, so a bare `unsigned' has to reach
      # them looking like `unsigned int' -- otherwise it comes out as `int'.
      a = if a0.type == null then a0 // { type = "INT"; } else a0;
      base = if a0.type == null then ty.inttype else a.base;
      # decl.c's combination check, which this port omitted. Without it
      # `short float x;' is not an error, it is a `short' -- lcc REJECTS the
      # declaration and we were giving it a different type and compiling it.
      illegal =
        (a.size == "SHORT" && a.type != "INT")
        || (a.size == "LONGLONG" && a.type != "INT")
        || (a.size == "LONG" && a.type != "INT" && a.type != "DOUBLE")
        || (a.sign != null && a.type != "INT" && a.type != "CHAR");
      t0 =
        if illegal then sy.refuse r.s "parse: invalid type specification"
        # decision-006 in as many words: "the frontend must REJECT float
        # declarations with a clear diagnostic rather than silently
        # miscompiling them". Refusing only the CONVERSIONS, which is where
        # this port first stopped, leaves `double x; double y; x = y;'
        # compiling -- and compiling byte-identically to lcc, so the oracle
        # diff is structurally blind to it. The declaration is the surface
        # decision-006 names, so the declaration is where the refusal goes.
        else if a.type == "FLOAT" || a.type == "DOUBLE" || ty.isfloat base
        then sy.refuse r.s "parse: `${
          if a.size == "LONG" then "long double" else lowerName a.type
        }' declarations are deferred (decision-006, task-015)"
        else if a.type == "CHAR" && a.sign != null
        then (if a.sign == "UNSIGNED" then ty.unsignedchar else ty.signedchar)
        else if a.size == "SHORT" then (if a.sign == "UNSIGNED" then ty.unsignedshort else ty.shorttype)
        else if a.size == "LONG" && a.type == "DOUBLE" then ty.longdouble
        else if a.size == "LONGLONG" then sy.refuse r.s "parse: `long long' is outside slice 1"
        else if a.size == "LONG" then (if a.sign == "UNSIGNED" then ty.unsignedlong else ty.longtype)
        else if a.sign == "UNSIGNED" && a.type == "INT" then ty.unsignedtype
        else base;
      t1 = if a.cons != null then qualify "CONST" t0 else t0;
      t2 = if a.vol != null then qualify "VOLATILE" t1 else t1;
    in
    {
      inherit (r) s;
      v = t2;
      sclass = if a.cls == null then sy.sclasses.none
      else sclassName.${a.cls} or (throw "parse: `${a.cls}' is not a storage class");
    };

  # Nix's builtins have no case conversion, and the one place that needs it
  # is a diagnostic naming the type keyword the user wrote.
  lowerName = k: b.replaceStrings
    [ "A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z" ]
    [ "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z" ]
    k;

  # The token spelling of each storage class, mapping onto sym.nix's single
  # declaration of what symbolic.c prints.
  sclassName = {
    AUTO = sy.sclasses.auto;
    EXTERN = sy.sclasses.extern;
    REGISTER = sy.sclasses.register;
    STATIC = sy.sclasses.static;
    TYPEDEF = sy.sclasses.typedef;
  };

  basicOf = k: {
    VOID = ty.voidtype;
    CHAR = ty.chartype;
    INT = ty.inttype;
    FLOAT = ty.floattype;
    DOUBLE = ty.doubletype;
  }.${k} or (throw "parse: `${k}' is not a basic type specifier");

  qualify = q: t:
    if t.op == "CONST" && q == "VOLATILE" then t // { op = "CONST+VOLATILE"; }
    else if t.op == "VOLATILE" && q == "CONST" then t // { op = "CONST+VOLATILE"; }
    else { op = q; type = t; inherit (t) size align; };

  # dclr1 builds the declarator's type CHAIN, outermost first; dclr then folds
  # the chain onto the base type. Kept as two functions because that split is
  # what makes `int *f(void)' and `int (*f)(void)' come out different.
  #
  # A chain link is NOT a type. lcc's tnode() reuses the Type struct for these
  # skeletons, which is fine in C where the two are distinguished by where they
  # are; here they would be two different things wearing one shape, and a
  # skeleton that leaked into type code would fail as an attribute miss --
  # which builtins.tryEval cannot catch (task-037). So a link is tagged `link'
  # and carries no size or align at all.
  link = kind: attrs: attrs // { link = kind; };

  dclr1 = s0: wantId: wantParams:
    let
      k = tk s0;
      head =
        if k == "ID" then
          (if wantId then { s = advance s0; id = text s0; t = null; params = null; }
          else sy.refuse s0 "parse: extraneous identifier `${text s0}'")
        else if k == "*" then
          # dclr1's `*' case collects the CONST/VOLATILE run that may follow
          # the star before recursing. Dropping it makes `int * const p;' --
          # ordinary C that lcc compiles -- die as "missing identifier", which
          # names the wrong thing entirely.
          let
            quals = st: acc:
              if tk st == "CONST" || tk st == "VOLATILE"
              then quals (advance st) (acc ++ [ (tk st) ])
              else { s = st; v = acc; };
            q = quals (advance s0) [ ];
            inner = dclr1 q.s wantId wantParams;
            qualified = b.foldl' (t: name: link name { type = t; }) inner.t q.v;
          in
          inner // { t = link "POINTER" { type = qualified; }; }
        else if k == "(" then
          let inner = dclr1 (advance s0) wantId wantParams; in
          inner // { s = expect inner.s ")"; }
        else { s = s0; id = null; t = null; params = null; };
      suffix = st: t: id: params:
        let k2 = tk st; in
        if k2 == "(" then
          let
            e = sy.enterscope (advance st);
            e2 = if e.level > sy.PARAM then sy.enterscope e else e;
            ps = parameters e2;
            t2 = link "FUNCTION" { type = t; inherit (ps) proto oldstyle; };
          in
          if wantParams && params == null
          then suffix ps.s t2 id ps.v
          else suffix (exitparams ps.s) t2 id params
        else if k2 == "[" then
          let
            s1 = advance st;
            n =
              if kindOf (tk s1) == "ID"
              then intexpr s1 "]"
              else { s = expect s1 "]"; v = 0; };
          in
          # dclr1 rejects a non-positive size, and intexpr has already cast the
          # constant to `int' -- so `int a[4000000000u]' is diagnosed as the
          # negative size it becomes, exactly as lcc diagnoses it, rather than
          # silently accepted.
          if kindOf (tk s1) == "ID" && n.v <= 0
          then sy.refuse n.s "parse: `${toString n.v}' is an illegal array size"
          else suffix n.s (link "ARRAY" { type = t; count = n.v; }) id params
        else { s = st; inherit t id params; };
    in
    suffix head.s head.t head.id head.params;

  exitparams = s: if s.level > sy.PARAM then sy.exitscope (sy.exitscope s) else sy.exitscope s;

  dclr = s0: basety: wantId: wantParams:
    let
      r = dclr1 s0 wantId wantParams;
      # The chain runs outermost-first, so it is applied innermost-first.
      apply = base: chain:
        if chain == null then base
        else apply (step base chain) chain.type;
      step = base: chain:
        if chain.link == "POINTER" then ty.ptr base
        else if chain.link == "FUNCTION" then ty.func base chain.proto chain.oldstyle
        else if chain.link == "ARRAY" then ty.array base chain.count 0
        else if chain.link == "CONST" || chain.link == "VOLATILE" then qualify chain.link base
        else throw "parse: `${chain.link}' is not a declarator chain link";
    in
    r // { t = apply basety r.t; };

  parameters = s0:
    let
      prototyped = kindOf (tk s0) == "STATIC" || isTypename s0;
      loop = st: n: acc:
        let
          sp = specifier st true;
          d = dclr sp.s sp.v true false;
          id = if d.id == null then toString (n + 1) else d.id;
          p = if d.t == ty.voidtype then { inherit (d) s; v = null; }
          else dclparam d.s sp.sclass id d.t;
          acc' = if p.v == null then acc else acc ++ [ p.v ];
        in
        if tk p.s != "," then { inherit (p) s; v = acc'; }
        else if tk (advance p.s) == "ELLIPSIS"
        then sy.refuse p.s "parse: variadic functions are outside slice 1"
        else loop (advance p.s) (n + 1) acc';
      r =
        if prototyped then loop s0 0 [ ]
        else if tk s0 == "ID" then sy.refuse s0 "parse: old-style parameter lists are outside slice 1"
        else { s = s0; v = [ ]; };
      s1 = if tk r.s == ")" then advance r.s else expect r.s ")";
    in
    {
      s = s1;
      inherit (r) v;
      proto = if prototyped then map (p: (sy.getsym r.s p).type) r.v else null;
      oldstyle = !prototyped;
    };

  dclparam = s00: sclass0: id: t0:
    let
      t = if ty.isfunc t0 then ty.ptr t0 else if ty.isarray t0 then ty.atop t0 else t0;
      ignoreRegister = sclass0 == sy.sclasses.register && ty.isvolatile t;
      s0 = if ignoreRegister
      then sy.warn s00 "register declaration ignored for `${ty.outtype t} ${id}'\n"
      else s00;
      sclass = if ignoreRegister then "" else sclass0;
      cls = if sclass == "" then sy.sclasses.auto else sclass;
      dup = sy.lookupIn s0 id s0.level;
      r =
        if dup != null then sy.refuse s0 "parse: duplicate declaration for `${id}'"
        else sy.install s0 id s0.level { };
      s1 = sy.modsym r.s r.v (q: q // {
        sclass = cls;
        type = t;
        defined = true;
        srcline = s0.line;
      });
      s2 = if cls == sy.sclasses.register then s1 // { regcount = s1.regcount + 1; } else s1;
    in
    { s = s2; inherit (r) v; };

  # decl.c's intexpr(): the value is CAST TO INT before it is used, which is
  # what turns `4000000000u' into a negative array size and makes lcc warn
  # about the conversion on the way. Reading the unsigned magnitude straight
  # out of the constant skips both the warning and the diagnosis.
  intexpr = s0: tok:
    let
      s1 = s0 // { needconst = s0.needconst + 1; };
      e = expr1 s1 tok;
      g = tr.get e.s e.v;
      c = tr.cast e.s e.v ty.inttype;
    in
    if g.op.gen == "CNST" && (g.op.kind == "I" || g.op.kind == "U")
    then { s = c.s // { inherit (s0) needconst; }; v = (tr.get c.s c.v).value; }
    else sy.refuse e.s "parse: integer expression must be constant";

  typename = s0:
    let
      sp = specifier s0 false;
      k = tk sp.s;
    in
    if k == "*" || k == "(" || k == "["
    then (let d = dclr sp.s sp.v false false; in { inherit (d) s; v = d.t; })
    else { inherit (sp) s; inherit (sp) v; };

  # --- statements --------------------------------------------------------
  definept = s: (sy.code s "Defpoint" { }).s;

  statement = s0: loop: lev:
    let
      ref = s0.refinc;
      k = tk s0;
      r =
        if k == "IF" then
          let g = sy.genlabel s0 2; in ifstmt g.s g.v loop (lev + 1)
        else if k == "WHILE" then
          let g = sy.genlabel s0 3; in whilestmt g.s g.v (lev + 1)
        else if k == "DO" then
          let g = sy.genlabel s0 3; in expect (dostmt g.s g.v (lev + 1)) ";"
        else if k == "FOR" then
          let g = sy.genlabel s0 4; in forstmt g.s g.v (lev + 1)
        else if k == "BREAK" then
          let
            s1 = definept (dag.walk s0 null 0 0);
            s2 = if loop != 0 then dag.branch s1 (loop + 2)
            else sy.err s1 "illegal break statement\n";
          in
          expect (advance s2) ";"
        else if k == "CONTINUE" then
          let
            s1 = definept (dag.walk s0 null 0 0);
            s2 = if loop != 0 then dag.branch s1 (loop + 1)
            else sy.err s1 "illegal continue statement\n";
          in
          expect (advance s2) ";"
        else if k == "SWITCH" || k == "CASE" || k == "DEFAULT" || k == "GOTO"
        then sy.refuse s0 "parse: `${k}' statements are outside slice 1"
        else if k == "RETURN" then
          let
            rty = ty.freturn (ty.unqual (sy.getsym s0 s0.cfunc).type);
            s1 = definept (advance s0);
            a =
              if tk s1 != ";" then
                (if rty == ty.voidtype
                then sy.refuse s1 "parse: extraneous return value"
                else let e = expr s1 null; in retcode e.s e.v)
              else if rty != ty.voidtype
              then
                let
                  w = sy.warn s1 "missing return value\n";
                  c = tr.cnsttree w ty.inttype 0;
                in
                retcode c.s c.v
              else s1;
            s2 = dag.branch a (sy.getsym a s0.cfunc).flabel;
          in
          expect s2 ";"
        else if k == "{" then compound s0 loop (lev + 1)
        else if k == ";" then advance (definept s0)
        else if k == "ID" && (peek s0).kind == ":"
        then sy.refuse s0 "parse: statement labels are outside slice 1"
        else
          let
            s1 = definept s0;
            e = expr0 s1 null;
            l = dag.listnodes e.s e.v 0 0;
            s2 = if l.s.nodecount == 0 || l.s.nodecount > 200 then dag.walk l.s null 0 0 else l.s;
          in
          expect s2 ";";
    in
    r // { refinc = ref; };

  ifstmt = s0: lab: loop: lev:
    let
      s1 = expect (advance s0) "(";
      s2 = definept s1;
      c = conditional s2 ")";
      s3 = dag.walk c.s c.v 0 lab;
      s4 = statement (s3 // { refinc = s3.refinc / 2.0; }) loop lev;
    in
    if tk s4 == "ELSE" then
      let
        s5 = dag.branch s4 (lab + 1);
        s6 = dag.definelab (advance s5) lab;
        s7 = statement s6 loop lev;
        f = sy.findlabel s7 (lab + 1);
      in
      if (sy.getsym f.s f.v).ref != 0.0 then dag.definelab f.s (lab + 1) else f.s
    else dag.definelab s4 lab;

  conditional = s0: tok:
    let p = expr s0 tok; in tr.cond p.s p.v;

  whilestmt = s0: lab: lev:
    let
      s1 = expect (advance (s0 // { refinc = s0.refinc * 10.0; })) "(";
      s2 = dag.walk s1 null 0 0;
      c = conditional s2 ")";
      s3 = dag.branch c.s (lab + 1);
      s4 = dag.definelab s3 lab;
      s5 = statement s4 lab lev;
      s6 = dag.definelab s5 (lab + 1);
      s7 = definept s6;
      s8 = dag.walk s7 c.v lab 0;
      f = sy.findlabel s8 (lab + 2);
    in
    if (sy.getsym f.s f.v).ref != 0.0 then dag.definelab f.s (lab + 2) else f.s;

  dostmt = s0: lab: lev:
    let
      s1 = dag.definelab (advance (s0 // { refinc = s0.refinc * 10.0; })) lab;
      s2 = statement s1 lab lev;
      s3 = dag.definelab s2 (lab + 1);
      s4 = expect (expect s3 "WHILE") "(";
      s5 = definept s4;
      c = conditional s5 ")";
      s6 = dag.walk c.s c.v lab 0;
      f = sy.findlabel s6 (lab + 2);
    in
    if (sy.getsym f.s f.v).ref != 0.0 then dag.definelab f.s (lab + 2) else f.s;

  forstmt = s0: lab: lev:
    let
      s1 = expect (advance s0) "(";
      s2 = definept s1;
      e1 = if kindOf (tk s2) == "ID" then expr0 s2 ";" else { s = expect s2 ";"; v = null; };
      s3 = dag.walk e1.s e1.v 0 0;
      s4 = s3 // { refinc = s3.refinc * 10.0; };
      e2 = if kindOf (tk s4) == "ID" then conditional s4 ";" else { s = expect s4 ";"; v = null; };
      e3 = if kindOf (tk e2.s) == "ID" then expr0 e2.s ")" else { s = expect e2.s ")"; v = null; };
      # stmt.c's foldcond: when the initialiser is `v = C' and the test is
      # `v <op> C2' with both constants, the entry test is decided at compile
      # time and the branch over the body is not emitted at all. Skipping this
      # leaves a dead JUMP and a dead label in every counted for-loop.
      once = if e2.v == null then { inherit (e3) s; v = 0; } else foldcond e3.s e1.v e2.v;
      s5 = if e2.v != null && once.v == 0 then dag.branch once.s (lab + 3) else once.s;
      s6 = dag.definelab s5 lab;
      s7 = statement s6 lab lev;
      s8 = dag.definelab s7 (lab + 1);
      s9 = definept s8;
      s10 = if e3.v != null then dag.walk s9 e3.v 0 0 else s9;
      s11 =
        if e2.v != null
        then dag.walk (definept (if once.v == 0 then dag.definelab s10 (lab + 3) else s10)) e2.v lab 0
        else dag.branch (definept s10) lab;
      f = sy.findlabel s11 (lab + 2);
    in
    if (sy.getsym f.s f.v).ref != 0.0 then dag.definelab f.s (lab + 2) else f.s;

  # stmt.c's foldcond, returning { s; v } where a non-zero v means the loop is
  # known to run at least once.
  foldcond = s0: e1: e2:
    let
      t1 = if e1 == null then null else tr.get s0 e1;
      ok1 = e1 != null && e2 != null && t1.op.gen == "ASGN"
        && ops.isaddrop (tr.get s0 (b.elemAt t1.kids 0)).op
        && (tr.get s0 (b.elemAt t1.kids 1)).op.gen == "CNST";
    in
    if !ok1 then { s = s0; v = 0; }
    else
      let
        v = (tr.get s0 (b.elemAt t1.kids 0)).sym;
        c1 = b.elemAt t1.kids 1;
        t2 = tr.get s0 e2;
        k0 = b.elemAt t2.kids 0;
        k1 = b.elemAt t2.kids 1;
        ok2 = b.elem t2.op.gen [ "LE" "LT" "EQ" "NE" "GT" "GE" ]
          && k0 != null && (tr.get s0 k0).op.gen == "INDIR"
          && (tr.get s0 (b.elemAt (tr.get s0 k0).kids 0)).sym == v
          && k1 != null && (tr.get s0 k1).op == (tr.get s0 c1).op;
      in
      if !ok2 then { s = s0; v = 0; }
      else
        let r = simp.simplify s0 (ops.bare t2.op.gen) t2.type c1 k1; in
        if (tr.get r.s r.v).op.gen == "CNST" && (tr.get r.s r.v).op.kind == "I"
        then { inherit (r) s; v = (tr.get r.s r.v).value; }
        else { inherit (r) s; v = 0; };

  retcode = s0: p0:
    if p0 == null then s0
    else
      let
        a = tr.pointer s0 p0;
        rty = ty.freturn (ty.unqual (sy.getsym a.s a.s.cfunc).type);
        at = tr.assignType a.s rty a.v;
      in
      if at == null then sy.err a.s "illegal return type; found `${
        ty.outtype (tr.get a.s a.v).type}' expected `${ty.outtype rty}'\n"
      else
        let
          c = tr.cast a.s a.v at;
          d = tr.cast c.s c.v (ty.promote (tr.get c.s c.v).type);
          t = (tr.get d.s d.v).type;
          r = tr.tree d.s (ops.mkop "RET" t) t d.v null;
        in
        dag.walk r.s r.v 0 0;

  # --- compound ----------------------------------------------------------
  compound = s0: loop: lev:
    let
      s1 = dag.walk s0 null 0 0;
      cp = sy.code s1 "Blockbeg" { locals = [ ]; level = 0; };
      blockIdx = cp.v;
      s2 = sy.enterscope cp.s;
      s3 = definept s2;
      s4 = expect s3 "{";
      s5 = s4 // { autos = [ ]; registers = [ ]; };
      declLoop = s:
        if kindOf (tk s) == "CHAR" || kindOf (tk s) == "STATIC"
          || (isTypename s && (peek s).kind != ":")
        then declLoop (decl s "local")
        else s;
      s6 = declLoop s5;
      nregs = b.length s6.registers;
      locals = s6.registers ++ s6.autos;
      s7 = setBlockLocals s6 blockIdx locals;
      stmtLoop = s:
        if kindOf (tk s) == "IF" || kindOf (tk s) == "ID"
        then stmtLoop (statement s loop lev)
        else s;
      s8 = stmtLoop s7;
      s9 = dag.walk s8 null 0 0;
      s10 = checkrefScope s9 s9.level;
      # The locals are sorted by reference count, descending and stable, from
      # the first AUTO onward. That order IS the frame layout: symbolic.c's
      # I(local) assigns offsets in the order it sees them.
      sorted = sortByRef s10 locals nregs;
      s11 = setBlockLocals s10 blockIdx sorted;
      s12 =
        if s11.level == sy.LOCAL then
          let
            i = dag.scanBack s11 (b.length s11.code - 1) (it: sy.kindNum it.kind >= sy.kindNum "Label");
            last = if i == null then null else b.elemAt s11.code i;
            rty = ty.freturn (ty.unqual (sy.getsym s11 s11.cfunc).type);
          in
          if last != null && last.kind == "Jump" then s11
          else if rty != ty.voidtype then
            let
              w = sy.warn s11 "missing return value\n";
              c = tr.cnsttree w ty.inttype 0;
            in
            retcode c.s c.v
          else s11
        else s11;
      s13 = setBlockLevel s12 blockIdx s12.level;
      s14 = (sy.code s13 "Blockend" { begin = blockIdx; }).s;
      s15 = if sy.reachable s14 "Gen" then definept s14 else s14;
    in
    if s15.level > sy.LOCAL then expect (sy.exitscope s15) "}" else s15;

  setBlockLocals = s: i: v: s // {
    code = b.genList (j: if j == i then (b.elemAt s.code j) // { locals = v; } else b.elemAt s.code j)
      (b.length s.code);
  };
  setBlockLevel = s: i: v: s // {
    code = b.genList (j: if j == i then (b.elemAt s.code j) // { level = v; } else b.elemAt s.code j)
      (b.length s.code);
  };

  # decl.c's insertion sort: move each entry left past everything with a
  # SMALLER ref, which sorts descending and keeps equal refs in declaration
  # order.
  sortByRef = s: xs: from:
    let
      # The reference counts are read ONCE, not once per comparison: they go
      # through the chunked store, and an insertion sort that looks each one up
      # again for every element it steps over measured n^1.6 rather than n^2 in
      # the worst case but with a constant nobody wants -- 800 locals in one
      # block cost 2.14 s and 317 MB.
      withRef = map (p: let q = sy.getsym s p; in { id = p; inherit (q) ref; }) xs;
      # decl.c's inner loop STOPS at the first element that is not smaller.
      insert = acc: p:
        let
          n = b.length acc;
          go = j: if j > from && (b.elemAt acc (j - 1)).ref < p.ref then go (j - 1) else j;
          at = go n;
        in
        b.genList (i: if i < at then b.elemAt acc i else if i == at then p else b.elemAt acc (i - 1)) (n + 1);
      head = b.genList (i: b.elemAt withRef i) from;
      rest = b.genList (i: b.elemAt withRef (from + i)) (b.length withRef - from);
    in
    map (x: x.id) (b.foldl' insert head rest);

  checkrefScope = s: lev:
    let
      hit = b.filter (sc: sc.level == lev) s.scopes;
      ids = if hit == [ ] then [ ] else b.attrValues (b.head hit).tbl;
    in
    b.foldl' checkref s ids;

  checkref = s: p:
    let
      q = sy.getsym s p;
      s1 = if q.scope >= sy.PARAM && (ty.isvolatile q.type || ty.isfunc q.type)
      then sy.modsym s p (x: x // { addressed = true; }) else s;
      r = sy.getsym s1 p;
    in
    if r.sclass == sy.sclasses.auto
      && ((r.scope == sy.PARAM && s1.regcount == 0) || r.scope >= sy.LOCAL)
      && !r.addressed && ty.isscalar r.type && r.ref >= 3.0
    then sy.modsym s1 p (x: x // { sclass = sy.sclasses.register; })
    else s1;

  # --- declarations at file and block scope ------------------------------
  decl = s0: where:
    let
      sp = specifier s0 true;
      k = tk sp.s;
    in
    if k == "ID" || k == "*" || k == "(" || k == "[" then
      let
        atGlobal = where == "global";
        # decl.c takes `pos = src' here, BEFORE the declarator is parsed, so a
        # diagnostic about this declaration names the line the declarator
        # started on rather than the line the parser happened to reach.
        pos = (cur sp.s).line;
        d = dclr sp.s sp.v true atGlobal;
        isDefn = atGlobal && d.params != null && d.id != null && ty.isfunc d.t
          && (tk d.s == "{" || isTypename d.s || (kindOf (tk d.s) == "STATIC" && tk d.s != "TYPEDEF"));
      in
      if isDefn then funcdefn d.s sp.sclass d.id d.t d.params pos
      else
        let
          s1 = if d.params != null then exitparams d.s else d.s;
          loop = s: id: t:
            let
              s2 =
                if id == null then sy.refuse s "parse: missing identifier"
                else if sp.sclass == sy.sclasses.typedef then installTypedef s id t
                else (if where == "global"
                then dclglobal s sp.sclass id t pos
                else dcllocal s sp.sclass id t pos).s;
            in
            if tk s2 != "," then s2
            else
              let d2 = dclr (advance s2) sp.v true false; in
              loop d2.s d2.id d2.t;
          s3 = loop s1 d.id d.t;
        in
        expect s3 ";"
    # decl.c: a specifier with no declarator after it is an error unless it
    # declared a struct, union or enum tag -- none of which slice 1 has. So
    # here it is always one.
    else sy.refuse sp.s "parse: empty declaration";

  installTypedef = s: id: t:
    let r = sy.install s id s.level { type = t; sclass = sy.sclasses.typedef; }; in r.s;

  dclglobal = s0: sclass0: id: t: pos:
    let
      sclass = if sclass0 == "" then sy.sclasses.auto else sclass0;
      existing = sy.lookupIn s0 id sy.GLOBAL;
      # decl.c warns when a name's linkage changes between declarations.
      # These programs COMPILE -- both frontends accept them and emit the same
      # IR -- so the only way the difference is visible is lcc's stderr, which
      # is precisely what criterion #7 compares.
      sAfterLinkage =
        if existing != null then
          let prev = (sy.getsym s0 existing).sclass; in
          if (prev == sy.sclasses.extern && sclass == sy.sclasses.static)
            || (prev == sy.sclasses.static && sclass == sy.sclasses.auto)
            || (prev == sy.sclasses.auto && sclass == sy.sclasses.static)
          then sy.warn s0 "inconsistent linkage for `${id}' previously declared at ${
            toString (sy.getsym s0 existing).srcline}\n"
          else s0
        else s0;
      r =
        if existing != null then { s = sAfterLinkage; v = existing; }
        else
          let q = sy.lookupExternal sAfterLinkage id; in
          if q != null then
            # relocate(): the symbol moves from `externals' to `globals'.
            let
              qs = sy.getsym sAfterLinkage q;
              warned =
                if sclass == sy.sclasses.static || !(ty.eqtype qs.type t true)
                then sy.warn sAfterLinkage "declaration of `${id}' does not match previous declaration at ${
                  toString qs.srcline}\n"
                else sAfterLinkage;
            in
            {
              s = warned // {
                externals = b.removeAttrs warned.externals [ id ];
                globals = warned.globals // { ${id} = q; };
                globalOrder = warned.globalOrder ++ [ q ];
                externalOrder = b.filter (x: x != q) warned.externalOrder;
              };
              v = q;
            }
          else sy.install sAfterLinkage id sy.GLOBAL { };
      s1 = sy.modsym r.s r.v (x: x // {
        sclass = if existing != null && x.sclass == sy.sclasses.extern then sclass
        else if existing != null then x.sclass
        else sclass;
        type = t;
        scope = sy.GLOBAL;
        srcline = pos;
      });
    in
    if tk s1 == "=" then sy.refuse s1 "parse: global initialisers belong to slice 3 (task-029)"
    else { s = s1; inherit (r) v; };

  dcllocal = s00: sclass00: id: t: pos:
    let
      # decl.c: `register' on a volatile, struct or array object is IGNORED,
      # with a warning. Both frontends then compile the same thing, so the
      # warning is the only trace it leaves -- criterion #7's territory.
      ignoreRegister = sclass00 == sy.sclasses.register && (ty.isvolatile t || ty.isarray t);
      s0 = if ignoreRegister
      then sy.warn s00 "register declaration ignored for `${ty.outtype t} ${id}'\n"
      else s00;
      sclass0 = if ignoreRegister then "" else sclass00;
      sclass =
        if sclass0 == "" then (if ty.isfunc t then sy.sclasses.extern else sy.sclasses.auto)
        else sclass0;
      dup = sy.lookupIn s0 id s0.level;
      dupParam = if s0.level == sy.LOCAL then sy.lookupIn s0 id sy.PARAM else null;
      r =
        if dup != null || dupParam != null
        then sy.refuse s0 "parse: redeclaration of `${id}'"
        else sy.install s0 id s0.level { };
      s1 = sy.modsym r.s r.v (x: x // { inherit sclass; type = t; srcline = pos; });
      s2 =
        if sclass == sy.sclasses.extern then
          let
            q = sy.lookupExternal s1 id;
            g = sy.lookupIn s1 id sy.GLOBAL;
            e =
              if g != null && (sy.getsym s1 g).sclass != sy.sclasses.typedef then { s = s1; v = g; }
              else if q != null then { s = s1; v = q; }
              else sy.installExternal s1 id { type = t; sclass = sy.sclasses.extern; srcline = pos; };
            es = sy.getsym e.s e.v;
            warned = if !(ty.eqtype es.type t true)
            then sy.warn e.s "declaration of `${id}' does not match previous declaration at ${
              toString es.srcline}\n"
            else e.s;
          in
          sy.modsym warned r.v (x: x // { alias = e.v; })
        else if sclass == sy.sclasses.static then sy.refuse s1 "parse: local statics belong to slice 3 (task-029)"
        else if sclass == sy.sclasses.register then
          s1 // { registers = s1.registers ++ [ r.v ]; regcount = s1.regcount + 1; }
        else s1;
      s3 =
        if sclass == sy.sclasses.register then sy.modsym s2 r.v (x: x // { defined = true; })
        else if sclass == sy.sclasses.auto then
          sy.modsym (s2 // { autos = s2.autos ++ [ r.v ]; }) r.v
            (x: x // { defined = true; addressed = ty.isarray t || x.addressed; })
        else s2;
      s4 =
        if tk s3 == "=" then
          let
            s5 = definept (advance s3);
            e = expr1 s5 null;
            a = tr.asgn e.s r.v e.v;
            rt = tr.root a.s a.v;
            s6 = dag.walk rt.s rt.v 0 0;
          in
          sy.modsym s6 r.v (x: x // { ref = 1.0; })
        else s3;
    in
    { s = s4; inherit (r) v; };

  # --- funcdefn ----------------------------------------------------------
  funcdefn = s0: sclass: id: fty: params: pos:
    let
      callee = params;
      # The caller symbols are COPIES: same name, sclass AUTO, integer types
      # promoted. That is why `ADDRFP4 b' can appear twice in one forest
      # without CSE merging the two -- they are different symbols.
      mkcaller = st: p:
        let
          q = sy.getsym st.s p;
          r = sy.newsym st.s (q // {
            sclass = sy.sclasses.auto;
            type = if ty.isint q.type then ty.promote q.type else q.type;
          });
        in
        { inherit (r) s; v = st.v ++ [ r.v ]; };
      cs = b.foldl' mkcaller { s = s0; v = [ ]; } callee;
      # decl.c names this: a parameter whose declarator had no identifier gets
      # the position number as its name, and a DEFINITION may not do that.
      # Without the check we install a parameter literally called `1' and print
      # `caller 1 type=int'.
      unnamed = b.filter
        (p: let n = (sy.getsym cs.s p).name; in n != "" && b.match "[1-9][0-9]*" n != null)
        callee;
      # decl.c checks for a previous DEFINITION before dclglobal installs this
      # one, because dclglobal itself does not distinguish a declaration from a
      # definition.
      prior = sy.lookup cs.s id;
      g =
        if unnamed != [ ]
        then sy.refuse cs.s "parse: missing name for a parameter of function `${id}'"
        else if prior != null && ty.isfunc ((sy.getsym cs.s prior).type or ty.inttype)
          && (sy.getsym cs.s prior).defined
        then sy.refuse cs.s "parse: redefinition of `${id}'"
        else dclglobal cs.s sclass id fty pos;
      lab = sy.genlabel g.s 1;
      s1 = sy.modsym lab.s g.v (x: x // {
        flabel = lab.v;
        defined = true;
        ncalls = 0;
      });

      s2 = s1 // {
        cfunc = g.v;
        labels = { };
        refinc = 1.0;
        regcount = 0;
        code = [ ];
      };
      s3 = compound s2 0 0;
      s4 = dag.definelab s3 lab.v;
      s5 = dag.walk s4 null 0 0;
      s6 = sy.exitscope s5;
      s7 = checkrefScope s6 s6.level;
      s8 = if (sy.getsym s7 g.v).sclass != sy.sclasses.static then self.listing.export s7 g.v else s7;
      s9 = self.listing.swtoseg s8 1;
      s10 = self.listing.emitFunction s9 g.v cs.v callee;
      s11 = sy.exitscope s10;
      # lcc frees its FUNC arena here, and this is the equivalent: by the time
      # emitFunction has returned, the function's listing text is in `buf' and
      # nothing reads its trees or dag nodes again. Without the release they
      # accumulate for the whole translation unit -- measured at 763 MB against
      # 472 MB for a hundred functions, a 38% difference in peak RSS for one
      # line, and the only lever of that size available. The SYMBOLS stay:
      # globals, externals and interned constants outlive the function.
      #
      # The id counters are NOT reset. Reusing ids would be correct, since the
      # tables are empty, and it would also make two nodes from two functions
      # compare equal in any future check that held both.
      s12 = s11 // {
        trees = self.store.empty;
        nodes = self.store.empty;
        buckets = { };
        nodecount = 0;
      };
    in
    expect (s12 // { cfunc = null; }) "}";

  # --- decl.c's program() ------------------------------------------------
  program = s0:
    let
      loop = s: n:
        if tk s == "EOI" then { inherit s n; }
        else
          let k = tk s; in
          if kindOf k == "CHAR" || kindOf k == "STATIC" || k == "ID" || k == "*" || k == "("
          then loop (decl s "global") (n + 1)
          else if k == ";" then loop (advance (sy.warn s "empty declaration\n")) (n + 1)
          else if tk s == "#"
          then sy.refuse s "parse: `#' -- this frontend is fed raw C and has no preprocessor yet; decision-005 chose to write one in Nix and task-013 is where it lives"
          else sy.refuse s "parse: unrecognised declaration at ${found s}";
      r = loop s0 0;
    in
    if r.n == 0 then sy.warn r.s "empty input file\n" else r.s;
}
