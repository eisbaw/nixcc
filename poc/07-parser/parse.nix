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
  }.${name};

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

  # expr3's `*cp != '='': the raw character after the current token.
  nextIsEq = s:
    let i = s.ti + 1; in
    i < b.length s.toks
    && (b.elemAt s.toks i).ws == ""
    && b.substring 0 1 (b.elemAt s.toks i).text == "=";

  expect = s: k:
    if tk s == k then advance s
    else sy.err s "syntax error; found `${text s}' expecting `${k}'\n";

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
            info = binops.${k};
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
            info = binops.${tk st};
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
          if (sy.getsym c.s sym).sclass == "register"
          then { s = sy.err c.s "invalid operand of unary &; `${(sy.getsym c.s sym).name}' is declared register\n"; inherit (c) v; }
          else { s = sy.modsym c.s sym (q: q // { addressed = true; }); inherit (c) v; }
        )
      else c
    else if k == "+" then
      let
        a = unary (advance s0);
        c = tr.pointer a.s a.v;
      in
      if ty.isarith (tr.get c.s c.v).type
      then tr.cast c.s c.v (ty.promote (tr.get c.s c.v).type)
      else { s = tr.typeerror c.s "+" c.v null; inherit (c) v; }
    else if k == "-" then
      let
        a = unary (advance s0);
        c = tr.pointer a.s a.v;
        t0 = (tr.get c.s c.v).type;
      in
      if ty.isarith t0 then
        let
          t = ty.promote t0;
          d = tr.cast c.s c.v t;
        in
        if ty.isunsigned t then
          let
            s1 = sy.warn d.s "unsigned operand of unary -\n";
            n = simp.simplify s1 (ops.bare "BCOM") t d.v null;
            one = tr.cnsttree n.s t 1;
          in
          simp.simplify one.s (ops.bare "ADD") t n.v one.v
        else simp.simplify d.s (ops.bare "NEG") t d.v null
      else { s = tr.typeerror c.s "-" c.v null; inherit (c) v; }
    else if k == "~" then
      let
        a = unary (advance s0);
        c = tr.pointer a.s a.v;
        t0 = (tr.get c.s c.v).type;
      in
      if ty.isint t0 then
        let
          t = ty.promote t0;
          d = tr.cast c.s c.v t;
        in
        simp.simplify d.s (ops.bare "BCOM") t d.v null
      else { s = tr.typeerror c.s "~" c.v null; inherit (c) v; }
    else if k == "!" then
      let
        a = unary (advance s0);
        c = tr.pointer a.s a.v;
      in
      if ty.isscalar (tr.get c.s c.v).type then
        let d = tr.cond c.s c.v; in
        simp.simplify d.s (ops.bare "NOT") ty.inttype d.v null
      else { s = tr.typeerror c.s "!" c.v null; inherit (c) v; }
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
    else if k == "(" && isTypename (advance s0) then
      let
        n = typename (advance s0);
        s1 = expect n.s ")";
        t1 = n.v;
        t = ty.unqual t1;
        u = unary s1;
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
    else if k == "(" then
      let e = expr (advance s0) ")"; in postfix e.s e.v
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
        else if k == "[" then throw "parse: subscripting belongs to slice 2/3 (task-028, task-029)"
        else if k == "." || k == "DEREF" then throw "parse: struct members are outside slice 1"
        else if k == "(" then
          let
            pp = tr.pointer s p;
            t = (tr.get pp.s pp.v).type;
          in
          if ty.isptr t && ty.isfunc (ty.unqual t).type then
            let c = call (advance pp.s) pp.v (ty.unqual t).type; in
            loop c.s c.v
          else throw "parse: `${ty.outtype t}' is not a function"
        else { inherit s; v = p; };
    in
    loop s0 p0;

  primary = s0:
    let k = tk s0; in
    if k == "ICON" then
      let
        r = const.evalICON (text s0);
        t = {
          "int" = ty.inttype;
          "long" = ty.longtype;
          "unsigned int" = ty.unsignedtype;
          "unsigned long" = ty.unsignedlong;
          "unsigned short" = ty.widechar;
        }.${r.type} or (throw "parse: the constant evaluator returned an unknown type `${r.type}'");
        # task-011's evaluator RECORDS its warnings and prints nothing. Dropping
        # them here would compile a silently clamped constant, which is the
        # regression criterion #7 exists to catch -- so they are replayed at the
        # position of the token that produced them.
        s1 = b.foldl' (st: w: sy.warn st (w + "\n")) s0 r.warnings;
        c = tr.cnsttree s1 t r.value;
      in
      { s = advance c.s; inherit (c) v; }
    else if k == "FCON" then
      throw "parse: floating-point constant `${text s0}' on line ${
        toString (cur s0).line}: float support is deferred (decision-006, task-015)"
    else if k == "SCON" then
      throw "parse: string literal on line ${toString (cur s0).line}: string constants belong to slice 2 (task-028)"
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
    else throw "parse: illegal expression at `${text s0}' on line ${toString (cur s0).line}";

  # An undeclared identifier. lcc guesses `int f()' when a `(' follows and
  # errors otherwise; both paths install a symbol so the rest of the parse has
  # something to hang on.
  implicitId = s0: name:
    if (b.elemAt s0.toks (s0.ti + 1)).kind == "(" then
      let
        fty = ty.func ty.inttype null 1;
        p = sy.install s0 name s0.level { type = fty; sclass = "extern"; };
        q = sy.lookupExternal p.s name;
        e =
          if q != null then { inherit (p) s; v = q; }
          else sy.installExternal p.s name { type = fty; sclass = "extern"; };
        s1 = sy.modsym e.s p.v (x: x // { alias = e.v; });
        i = tr.idtree s1 p.v;
      in
      { s = advance i.s; inherit (i) v; }
    else throw "parse: undeclared identifier `${name}' on line ${toString (cur s0).line}";

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
          conv =
            if hasProtoArg then
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
    || (k == "ID" && (let p = sy.lookup s (text s); in p != null && (sy.getsym s p).sclass == "typedef"));

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
        then throw "parse: struct, union and enum types are outside slice 1"
        else if k == "ID" && isTypename st && acc.type == null && acc.sign == null && acc.size == null
        then
          let p = sy.lookup st (text st); in
          set st (acc // { base = (sy.getsym st p).type; }) "type" k
        else { s = st; inherit acc; };
      set = st: acc: field: v:
        if acc.${field} != null
        then throw "parse: invalid use of `${v}' on line ${toString (cur st).line}"
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
      t0 =
        if a.type == "CHAR" && a.sign != null
        then (if a.sign == "UNSIGNED" then ty.unsignedchar else ty.signedchar)
        else if a.size == "SHORT" then (if a.sign == "UNSIGNED" then ty.unsignedshort else ty.shorttype)
        else if a.size == "LONG" && a.type == "DOUBLE" then ty.longdouble
        else if a.size == "LONGLONG" then throw "parse: `long long' is outside slice 1"
        else if a.size == "LONG" then (if a.sign == "UNSIGNED" then ty.unsignedlong else ty.longtype)
        else if a.sign == "UNSIGNED" && a.type == "INT" then ty.unsignedtype
        else base;
      t1 = if a.cons != null then qualify "CONST" t0 else t0;
      t2 = if a.vol != null then qualify "VOLATILE" t1 else t1;
    in
    {
      inherit (r) s;
      v = t2;
      sclass = if a.cls == null then "" else sclassName.${a.cls};
    };

  # token.h's `%k' spelling for the storage classes symbolic.c prints.
  sclassName = {
    AUTO = "auto"; EXTERN = "extern"; REGISTER = "register";
    STATIC = "static"; TYPEDEF = "typedef";
  };

  basicOf = k: {
    VOID = ty.voidtype;
    CHAR = ty.chartype;
    INT = ty.inttype;
    FLOAT = ty.floattype;
    DOUBLE = ty.doubletype;
  }.${k};

  qualify = q: t:
    if t.op == "CONST" && q == "VOLATILE" then t // { op = "CONST+VOLATILE"; }
    else if t.op == "VOLATILE" && q == "CONST" then t // { op = "CONST+VOLATILE"; }
    else { op = q; type = t; inherit (t) size align; };

  # dclr1 builds the declarator's type CHAIN, outermost first; dclr then folds
  # the chain onto the base type. Kept as two functions because that split is
  # what makes `int *f(void)' and `int (*f)(void)' come out different.
  dclr1 = s0: wantId: wantParams: abstract:
    let
      k = tk s0;
      head =
        if k == "ID" then
          (if wantId then { s = advance s0; id = text s0; t = null; params = null; }
          else throw "parse: extraneous identifier `${text s0}'")
        else if k == "*" then
          let inner = dclr1 (advance s0) wantId wantParams abstract; in
          inner // { t = { op = "POINTER"; type = inner.t; }; }
        else if k == "(" then
          let inner = dclr1 (advance s0) wantId wantParams abstract; in
          inner // { s = expect inner.s ")"; }
        else { s = s0; id = null; t = null; params = null; };
      suffix = st: t: id: params:
        let k2 = tk st; in
        if k2 == "(" then
          let
            e = sy.enterscope (advance st);
            e2 = if e.level > sy.PARAM then sy.enterscope e else e;
            ps = parameters e2;
            t2 = { op = "FUNCTION"; type = t; inherit (ps) proto; inherit (ps) oldstyle; };
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
          suffix n.s { op = "ARRAY"; type = t; count = n.v; } id params
        else { s = st; inherit t id params; };
    in
    suffix head.s head.t head.id head.params;

  exitparams = s: if s.level > sy.PARAM then sy.exitscope (sy.exitscope s) else sy.exitscope s;

  dclr = s0: basety: wantId: wantParams:
    let
      r = dclr1 s0 wantId wantParams false;
      # The chain runs outermost-first, so it is applied innermost-first.
      apply = base: chain:
        if chain == null then base
        else apply (step base chain) chain.type;
      step = base: chain:
        if chain.op == "POINTER" then ty.ptr base
        else if chain.op == "FUNCTION" then ty.func base chain.proto chain.oldstyle
        else if chain.op == "ARRAY" then ty.array base chain.count 0
        else qualify chain.op base;
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
        then throw "parse: variadic functions are outside slice 1"
        else loop (advance p.s) (n + 1) acc';
      r =
        if prototyped then loop s0 0 [ ]
        else if tk s0 == "ID" then throw "parse: old-style parameter lists are outside slice 1"
        else { s = s0; v = [ ]; };
      s1 = if tk r.s == ")" then advance r.s else expect r.s ")";
    in
    {
      s = s1;
      inherit (r) v;
      proto = if prototyped then map (p: (sy.getsym r.s p).type) r.v else null;
      oldstyle = !prototyped;
    };

  dclparam = s0: sclass: id: t0:
    let
      t = if ty.isfunc t0 then ty.ptr t0 else if ty.isarray t0 then ty.atop t0 else t0;
      cls = if sclass == "" then "auto" else sclass;
      dup = sy.lookupIn s0 id s0.level;
      r =
        if dup != null then throw "parse: duplicate declaration for `${id}'"
        else sy.install s0 id s0.level { };
      s1 = sy.modsym r.s r.v (q: q // { sclass = cls; type = t; defined = true; });
      s2 = if cls == "register" then s1 // { regcount = s1.regcount + 1; } else s1;
    in
    { s = s2; inherit (r) v; };

  intexpr = s0: tok:
    let
      s1 = s0 // { needconst = s0.needconst + 1; };
      e = expr1 s1 tok;
      g = tr.get e.s e.v;
    in
    if g.op.gen == "CNST" && (g.op.kind == "I" || g.op.kind == "U")
    then { s = e.s // { inherit (s0) needconst; }; v = g.value; }
    else throw "parse: integer expression must be constant";

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
        then throw "parse: `${k}' statements are outside slice 1"
        else if k == "RETURN" then
          let
            rty = ty.freturn (ty.unqual (sy.getsym s0 s0.cfunc).type);
            s1 = definept (advance s0);
            a =
              if tk s1 != ";" then
                (if rty == ty.voidtype
                then throw "parse: extraneous return value on line ${toString (cur s1).line}"
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
        else if k == "ID" && (b.elemAt s0.toks (s0.ti + 1)).kind == ":"
        then throw "parse: statement labels are outside slice 1"
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
          || (isTypename s && (b.elemAt s.toks (s.ti + 1)).kind != ":")
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
      refOf = p: (sy.getsym s p).ref;
      insert = acc: p:
        let
          n = b.length acc;
          js = b.filter (j: j >= from && refOf (b.elemAt acc j) < refOf p) (b.genList (i: i) n);
          at = if js == [ ] then n else b.head js;
        in
        b.genList (i: if i < at then b.elemAt acc i else if i == at then p else b.elemAt acc (i - 1)) (n + 1);
      head = b.genList (i: b.elemAt xs i) from;
      rest = b.genList (i: b.elemAt xs (from + i)) (b.length xs - from);
    in
    b.foldl' insert head rest;

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
    if r.sclass == "auto"
      && ((r.scope == sy.PARAM && s1.regcount == 0) || r.scope >= sy.LOCAL)
      && !r.addressed && ty.isscalar r.type && r.ref >= 3.0
    then sy.modsym s1 p (x: x // { sclass = "register"; })
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
        d = dclr sp.s sp.v true atGlobal;
        isDefn = atGlobal && d.params != null && d.id != null && ty.isfunc d.t
          && (tk d.s == "{" || isTypename d.s || (kindOf (tk d.s) == "STATIC" && tk d.s != "TYPEDEF"));
      in
      if isDefn then funcdefn d.s sp.sclass d.id d.t d.params
      else
        let
          s1 = if d.params != null then exitparams d.s else d.s;
          loop = s: id: t:
            let
              s2 =
                if id == null then throw "parse: missing identifier"
                else if sp.sclass == "typedef" then installTypedef s id t
                else (if where == "global" then dclglobal s sp.sclass id t else dcllocal s sp.sclass id t).s;
            in
            if tk s2 != "," then s2
            else
              let d2 = dclr (advance s2) sp.v true false; in
              loop d2.s d2.id d2.t;
          s3 = loop s1 d.id d.t;
        in
        expect s3 ";"
    else expect sp.s ";";

  installTypedef = s: id: t:
    let r = sy.install s id s.level { type = t; sclass = "typedef"; }; in r.s;

  dclglobal = s0: sclass0: id: t:
    let
      sclass = if sclass0 == "" then "auto" else sclass0;
      existing = sy.lookupIn s0 id sy.GLOBAL;
      r =
        if existing != null then { s = s0; v = existing; }
        else
          let q = sy.lookupExternal s0 id; in
          if q != null then
            # relocate(): the symbol moves from `externals' to `globals'.
            {
              s = s0 // {
                externals = b.removeAttrs s0.externals [ id ];
                globals = s0.globals // { ${id} = q; };
                globalOrder = s0.globalOrder ++ [ q ];
                externalOrder = b.filter (x: x != q) s0.externalOrder;
              };
              v = q;
            }
          else sy.install s0 id sy.GLOBAL { };
      s1 = sy.modsym r.s r.v (x: x // {
        sclass = if existing != null && x.sclass == "extern" then sclass
        else if existing != null then x.sclass
        else sclass;
        type = t;
        scope = sy.GLOBAL;
      });
    in
    if tk s1 == "=" then throw "parse: global initialisers belong to slice 3 (task-029)"
    else { s = s1; inherit (r) v; };

  dcllocal = s0: sclass0: id: t:
    let
      sclass =
        if sclass0 == "" then (if ty.isfunc t then "extern" else "auto")
        else sclass0;
      dup = sy.lookupIn s0 id s0.level;
      dupParam = if s0.level == sy.LOCAL then sy.lookupIn s0 id sy.PARAM else null;
      r =
        if dup != null || dupParam != null
        then throw "parse: redeclaration of `${id}'"
        else sy.install s0 id s0.level { };
      s1 = sy.modsym r.s r.v (x: x // { inherit sclass; type = t; });
      s2 =
        if sclass == "extern" then
          let
            q = sy.lookupExternal s1 id;
            g = sy.lookupIn s1 id sy.GLOBAL;
            e =
              if g != null && (sy.getsym s1 g).sclass != "typedef" then { s = s1; v = g; }
              else if q != null then { s = s1; v = q; }
              else sy.installExternal s1 id { type = t; sclass = "extern"; };
          in
          sy.modsym e.s r.v (x: x // { alias = e.v; })
        else if sclass == "static" then throw "parse: local statics belong to slice 3 (task-029)"
        else if sclass == "register" then
          s1 // { registers = s1.registers ++ [ r.v ]; regcount = s1.regcount + 1; }
        else s1;
      s3 =
        if sclass == "register" then sy.modsym s2 r.v (x: x // { defined = true; })
        else if sclass == "auto" then
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
  funcdefn = s0: sclass: id: fty: params:
    let
      callee = params;
      # The caller symbols are COPIES: same name, sclass AUTO, integer types
      # promoted. That is why `ADDRFP4 b' can appear twice in one forest
      # without CSE merging the two -- they are different symbols.
      mkcaller = st: p:
        let
          q = sy.getsym st.s p;
          r = sy.newsym st.s (q // {
            sclass = "auto";
            type = if ty.isint q.type then ty.promote q.type else q.type;
          });
        in
        { inherit (r) s; v = st.v ++ [ r.v ]; };
      cs = b.foldl' mkcaller { s = s0; v = [ ]; } callee;
      g = dclglobal cs.s sclass id fty;
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
      s8 = if (sy.getsym s7 g.v).sclass != "static" then self.listing.export s7 g.v else s7;
      s9 = self.listing.swtoseg s8 1;
      s10 = self.listing.emitFunction s9 g.v cs.v callee;
      s11 = sy.exitscope s10;
    in
    expect (s11 // { cfunc = null; }) "}";

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
          else throw "parse: unrecognised declaration at `${text s}' on line ${toString (cur s).line}";
      r = loop s0 0;
    in
    if r.n == 0 then sy.warn r.s "empty input file\n" else r.s;
}
