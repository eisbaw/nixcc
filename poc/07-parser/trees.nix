# lcc/src/tree.c and lcc/src/enode.c, plus the tree-shaped half of expr.c
# (idtree, rvalue, lvalue, retype, pointer, cond, value, cast).
#
# These three files are one thing -- the typed expression tree and the
# conversions the standard requires -- so they are one module here. Splitting
# them the way lcc does would buy nothing: lcc's split is along "who calls the
# parser" lines, and our parser calls all of it.
#
# TREES HAVE IDENTITY. Every tree gets an integer id, because lcc compares tree
# POINTERS in three places that matter: tree.c's root1 de-constructs `e++' by
# testing `p->kids[1] == p->kids[0]->kids[0]', enode.c's addrof tests `p == q',
# and dag.c memoises `tp->node' per tree. Structural equality would fire on
# trees lcc would have treated as distinct, and the difference is a wrong DAG.
let
  b = builtins;
in
self:
let
  ty = self.types;
  inherit (self) ops;
  sy = self.sym;
  inherit (self) simp;
  st = self.store;
in
rec {
  get = s: id:
    if id == null then throw "trees: null tree dereferenced"
    else st.get "tree" s.trees id;

  tree = s: op: t: l: r:
    let id = s.nexttree; in
    {
      s = s // {
        nexttree = id + 1;
        trees = st.set s.trees id {
          inherit id;
          op = ops.check op;
          type = t;
          kids = [ l r ];
          sym = null;
          value = null;
          node = null;
        };
      };
      v = id;
    };

  # expr.c's retype: the same tree wearing a different type. lcc copies the
  # `node' field too, so a retyped tree that has already been given a dag node
  # keeps it; dropping that would make listnodes build the node twice.
  retype = s: p: t:
    let pt = get s p; in
    if pt.type == t then { inherit s; v = p; }
    else
      let id = s.nexttree; in
      {
        s = s // {
          nexttree = id + 1;
          trees = st.set s.trees id (pt // { inherit id; type = t; });
        };
        v = id;
      };

  setnode = s: p: n: s // { trees = st.set s.trees p ((get s p) // { node = n; }); };

  setsym = s: p: symid: s // { trees = st.set s.trees p ((get s p) // { sym = symid; }); };

  setkid = s: p: i: k:
    let pt = get s p; in
    s // {
      trees = st.set s.trees p
        (pt // { kids = b.genList (j: if j == i then k else b.elemAt pt.kids j) 2; });
    };

  kid = s: p: i: b.elemAt (get s p).kids i;
  gen = s: p: (get s p).op.gen;
  kindOf = s: p: (get s p).op.kind;

  rightkid = s: p:
    if p != null && (get s p).op.gen == "RIGHT" then
      (if kid s p 1 != null then rightkid s (kid s p 1)
      else if kid s p 0 != null then rightkid s (kid s p 0)
      else throw "trees: a RIGHT tree with no kids")
    else p;

  # --- constants ---------------------------------------------------------
  cnsttree = s: t: v:
    let
      u = ty.unqual t;
      val =
        if u.op == "INT" then v
        else if u.op == "UNSIGNED" then b.bitAnd v (ty.ones (8 * u.size))
        # A POINTER constant is stored verbatim, as lcc's `p->u.v.p = va_arg'
        # does: it is a null pointer constant or an integer someone cast, and
        # simp.c's CVU+P has already checked it against the pointer limits.
        # Unmasked, deliberately -- masking here would hide an out-of-range
        # value that the conversion refused to fold.
        else if u.op == "POINTER" then v
        else sy.refuse s "trees: a `${u.op}' constant needs float support, which is deferred (decision-006, task-015)";
      r = tree s (ops.mkop "CNST" t) t null null;
    in
    { s = r.s // { trees = st.set r.s.trees r.v ((get r.s r.v) // { value = val; }); }; inherit (r) v; };

  consttree = s: n: t:
    if ty.isarray t then cnsttree s (ty.atop t) n
    else if ty.isint t then cnsttree s t n
    else sy.refuse s "trees: consttree wants an integer or array type, got `${ty.outtype t}'";

  # --- tree.c's root / root1 ---------------------------------------------
  # "expression with no effect elided" is warned at most ONCE per root(), which
  # is what `warn++ == 0' buys. Getting that wrong shows up in the stderr diff
  # rather than in the IR, which is exactly why criterion #7 exists.
  root = s: p: let r = root1 (s // { warncount = 0; }) p; in r;

  elide = s: if s.warncount == 0
  then (sy.warn s "expression with no effect elided\n") // { warncount = s.warncount + 1; }
  else s // { warncount = s.warncount + 1; };

  root1 = s0: p:
    if p == null then { s = s0; v = null; }
    else
      let
        pt = get s0 p;
        g = pt.op.gen;
        k = pt.op.kind;
        s = if pt.type == ty.voidtype then s0 // { warncount = s0.warncount + 1; } else s0;
        k0 = b.elemAt pt.kids 0;
        k1 = b.elemAt pt.kids 1;

        # Both binary shapes below build RIGHT(root1 l, root1 r) and vanish if
        # both halves vanished.
        pair = st: warnFirst:
          let
            s1 = if warnFirst then elide st else st;
            a = root1 s1 k0;
            c = root1 a.s k1;
          in
          if a.v == null && c.v == null then { inherit (c) s; v = null; }
          else tree c.s (ops.bare "RIGHT") pt.type a.v c.v;

        unary = st: let s1 = elide st; in root1 s1 k0;
      in
      if g == "COND" then
        let
          q = k1;
          qt = get s q;
          qk0 = b.elemAt qt.kids 0;
          qk1 = b.elemAt qt.kids 1;
          a =
            if pt.sym != null && qk0 != null && gen s qk0 == "ASGN"
            then root1 s (kid s qk0 1) else root1 s qk0;
          c =
            if pt.sym != null && qk1 != null && gen a.s qk1 == "ASGN"
            then root1 a.s (kid a.s qk1 1) else root1 a.s qk1;
          s1 = setsym (setkid (setkid c.s q 0 a.v) q 1 c.v) p null;
        in
        if a.v == null && c.v == null then root1 s1 k0 else { s = s1; v = p; }
      else if g == "AND" || g == "OR" then
        let a = root1 s k1; s1 = setkid a.s p 1 a.v; in
        if a.v == null then root1 s1 k0 else { s = s1; v = p; }
      else if g == "NOT" then unary s
      else if g == "RIGHT" then
        (
          if k1 == null then root1 s k0
          else if k0 != null && gen s k0 == "RIGHT" && k1 == kid s k0 0
          # de-construct the `e++' shape enode.c's postfix built
          then { inherit s; v = kid s k0 1; }
          else pair s false
        )
      else if b.elem g [ "EQ" "NE" "GT" "GE" "LE" "LT" "ADD" "SUB" "MUL" "DIV" "MOD" "LSH" "RSH" "BAND" "BOR" "BXOR" ]
      then pair s true
      else if g == "INDIR" || g == "NEG" || g == "BCOM" || g == "FIELD" then unary s
      else if g == "ADDRL" || g == "ADDRG" || g == "ADDRF" || g == "CNST" then
        (if s.needconst > 0 then { inherit s; v = p; } else { s = elide s; v = null; })
      else if g == "CVI" then
        let
          s1 = if (k == "U" || k == "I") && pt.type.size < (get s k0).type.size
            && !(gen s k0 == "CALL" && kindOf s k0 == "I")
          then elide s else s;
        in
        root1 s1 k0
      else if g == "CVU" || g == "CVP" then
        let
          s1 = if (k == "U" && pt.type.size < (get s k0).type.size)
            || (k == "I" && pt.type.size <= (get s k0).type.size)
          then elide s else s;
        in
        root1 s1 k0
      else if g == "CVF" then sy.refuse s "trees: float conversions are deferred (decision-006, task-015)"
      else if b.elem g [ "ARG" "ASGN" "CALL" "JUMP" "LABEL" ] then { inherit s; v = p; }
      else sy.refuse s "trees: root1 has no rule for `${g}'";

  # --- expr.c's lvalue / rvalue / pointer / cond / value ------------------
  rvalue = s: p:
    let t = ty.unqual (ty.deref (get s p).type); in
    tree s (ops.mkop "INDIR" t) t p null;

  lvalue = s: p:
    if gen s p != "INDIR" then
      let s1 = sy.err s "lvalue required\n"; in value s1 p
    else { inherit s; v = kid s p 0; };

  pointer = s: p:
    let t = (get s p).type; in
    if ty.isarray t then retype s p (ty.atop t)
    else if ty.isfunc t then retype s p (ty.ptr t)
    else { inherit s; v = p; };

  condOps = [ "AND" "OR" "NOT" "EQ" "NE" "LE" "LT" "GE" "GT" ];

  cond = s: p:
    if b.elem (gen s (rightkid s p)) condOps then { inherit s; v = p; }
    else
      let
        a = pointer s p;
        c = consttree a.s 0 ty.inttype;
      in
      eqtree c.s (ops.bare "NE") a.v c.v;

  value = s: p:
    if (get s p).type != ty.voidtype && b.elem (gen s (rightkid s p)) condOps
    then
      let
        one = consttree s 1 ty.inttype;
        zero = consttree one.s 0 ty.inttype;
      in
      condtree zero.s p one.v zero.v
    else { inherit s; v = p; };

  # --- expr.c's cast -----------------------------------------------------
  cast = s0: p0: t:
    let
      v0 = value s0 p0;
    in
    if (get v0.s v0.v).type == t then v0
    else
      let
        step1 =
          let
            dst0 = ty.unqual t;
            src0 = ty.unqual (get v0.s v0.v).type;
          in
          if src0.op == dst0.op && src0.size == dst0.size then v0
          else
            let
              a =
                if src0.op == "INT" then
                  (if src0.size < ty.inttype.size
                  then simp.simplify v0.s (ops.bare "CVI") ty.inttype v0.v null
                  else v0)
                else if src0.op == "UNSIGNED" then
                  (if src0.size < ty.inttype.size
                  then simp.simplify v0.s (ops.bare "CVU") ty.inttype v0.v null
                  else if src0.size < ty.unsignedtype.size
                  then simp.simplify v0.s (ops.bare "CVU") ty.unsignedtype v0.v null
                  else v0)
                else if src0.op == "ENUM" then retype v0.s v0.v ty.inttype
                else if src0.op == "POINTER" then
                  simp.simplify v0.s (ops.bare "CVP") (ty.super src0) v0.v null
                else if src0.op == "FLOAT" then v0
                else sy.refuse v0.s "trees: cast has no rule for source `${src0.op}'";
              src1 = ty.unqual (get a.s a.v).type;
              dst1 = ty.super dst0;
            in
            if src1.op == dst1.op then a
            else if src1.op == "INT" then simp.simplify a.s (ops.bare "CVI") dst1 a.v null
            else if src1.op == "UNSIGNED" then simp.simplify a.s (ops.bare "CVU") dst1 a.v null
            else if src1.op == "FLOAT" then
              sy.refuse a.s "trees: float conversions are deferred (decision-006, task-015)"
            else sy.refuse a.s "trees: cast has no widening rule for `${src1.op}'";

        dst = ty.unqual t;
        src = ty.unqual (get step1.s step1.v).type;
        step2 =
          if src.op == "INT" then
            (if src.op != dst.op || src.size != dst.size
            then simp.simplify step1.s (ops.bare "CVI") dst step1.v null else step1)
          else if src.op == "UNSIGNED" then
            (if src.op != dst.op || src.size != dst.size
            then simp.simplify step1.s (ops.bare "CVU") dst step1.v null else step1)
          else if src.op == "FLOAT" then
            sy.refuse step1.s "trees: float conversions are deferred (decision-006, task-015)"
          else if src.op == "POINTER" then
            (if src.op != dst.op || src.size != dst.size
            then simp.simplify step1.s (ops.bare "CVP") dst step1.v null else step1)
          else sy.refuse step1.s "trees: cast has no narrowing rule for `${src.op}'";
      in
      retype step2.s step2.v t;

  # --- enode.c -----------------------------------------------------------
  isnullptr = s: e:
    let
      t = ty.unqual (get s e).type;
      pt = get s e;
    in
    pt.op.gen == "CNST"
    && ((t.op == "INT" && pt.value == 0) || (t.op == "UNSIGNED" && pt.value == 0));

  isvoidptr = t: ty.isptr t && ty.unqual t.type == ty.voidtype;

  compatible = ty1: ty2:
    let a = ty.unqual ty1; c = ty.unqual ty2; in
    ty.isptr a && !(ty.isfunc a.type)
    && ty.isptr c && !(ty.isfunc c.type)
    && ty.unqual a.type == ty.unqual c.type;

  # enode.c's assign(): the type the right-hand side must be converted to, or
  # null if the assignment is illegal.
  assignType = s: xty0: e:
    let
      yty = ty.unqual (get s e).type;
      xty1 = ty.unqual xty0;
      xty = if ty.isenum xty1 then xty1.type else xty1;
    in
    if xty.size == 0 || yty.size == 0 then null
    else if ty.isarith xty && ty.isarith yty then xty
    else if ty.isptr xty && isnullptr s e then xty
    else if ((isvoidptr xty && ty.isptr yty) || (ty.isptr xty && isvoidptr yty))
      && ((ty.isconst xty.type || !(ty.isconst yty.type))
      && (ty.isvolatile xty.type || !(ty.isvolatile yty.type)))
    then xty
    else if ty.isptr xty && ty.isptr yty && ty.unqual xty.type == ty.unqual yty.type
      && ((ty.isconst xty.type || !(ty.isconst yty.type))
      && (ty.isvolatile xty.type || !(ty.isvolatile yty.type)))
    then xty
    else null;

  # enode.c's typeerror() takes the OP, not its spelling, and looks the
  # spelling up itself. Taking the spelling meant every caller wrote a string
  # literal, so the table below had a dozen shadow copies scattered across two
  # files -- and each `opText.${g}' was a bare select that builtins.tryEval
  # cannot catch (task-037).
  typeerror = s: g: l: r:
    let
      opname = opText.${g} or (throw "trees: typeerror has no spelling for `${g}'");
    in
    if r == null
    then sy.err s "operand of unary ${opname} has illegal type `${ty.outtype (get s l).type}'\n"
    else sy.err s "operands of ${opname} have illegal types `${ty.outtype (get s l).type}' and `${
      ty.outtype (get s r).type}'\n";

  opText = {
    ASGN = "="; INDIR = "*"; NEG = "-"; ADD = "+"; SUB = "-"; LSH = "<<";
    MOD = "%"; RSH = ">>"; BAND = "&"; BCOM = "~"; BOR = "|"; BXOR = "^";
    DIV = "/"; MUL = "*"; EQ = "=="; GE = ">="; GT = ">"; LE = "<="; LT = "<";
    NE = "!="; AND = "&&"; NOT = "!"; OR = "||"; COND = "?:";
  };

  asgntree = s0: op: l0: r0:
    let
      a = pointer s0 r0;
      at = assignType a.s (get a.s l0).type a.v;
      c =
        if at != null then cast a.s a.v at
        else
          let
            e = typeerror a.s "ASGN" l0 a.v;
            f = if (get e a.v).type == ty.voidtype then retype e a.v ty.inttype else { s = e; inherit (a) v; };
          in
          f;
      t = if at != null then at else (get c.s c.v).type;
      lv = if gen c.s l0 == "FIELD" then { inherit (c) s; v = l0; } else lvalue c.s l0;
      aty0 = (get lv.s lv.v).type;
      aty = if ty.isptr aty0 then (ty.unqual aty0).type else aty0;
      s1 =
        if ty.isconst aty then
          (if ops.isaddrop (get lv.s lv.v).op
            && !(sy.getsym lv.s (get lv.s lv.v).sym).computed
            && !(sy.getsym lv.s (get lv.s lv.v).sym).generated
          then sy.err lv.s "assignment to const identifier `${
            (sy.getsym lv.s (get lv.s lv.v).sym).name}'\n"
          else sy.err lv.s "assignment to const location\n")
        else lv.s;
    in
    if gen s1 l0 == "FIELD" then sy.refuse s1 "trees: bit-field assignment is outside slice 1"
    else tree s1 (ops.mkop op.gen t) t lv.v c.v;

  # enode.c's asgn(). The qualifier dance is not decoration: lcc temporarily
  # sets `p->type = unqual(p->type)' around the assignment, and that is the
  # ONLY thing that lets `const int c = 7;' compile -- asgntree errors on an
  # assignment to a const identifier, and an initialiser goes through exactly
  # that path. Without it the frontend refuses a declaration C requires it to
  # accept, and there is no other hint that the strip is load-bearing.
  asgn = s0: p: e:
    let
      psym = sy.getsym s0 p;
      s1 = sy.modsym s0 p (q: q // { type = ty.unqual q.type; });
      i = idtree s1 p;
      a = asgntree i.s (ops.bare "ASGN") i.v e;
    in
    if ty.isarray psym.type then sy.refuse s0 "trees: array assignment is slice 2/3 (task-028)"
    else { s = sy.modsym a.s p (q: q // { inherit (psym) type; }); inherit (a) v; };

  condtree = s0: e: l: r:
    let
      xty = (get s0 l).type;
      yty = (get s0 r).type;
      t =
        if ty.isarith xty && ty.isarith yty then ty.binaryType xty yty
        else if xty == yty then ty.unqual xty
        else if ty.isptr xty && isnullptr s0 r then xty
        else if isnullptr s0 l && ty.isptr yty then yty
        else null;
      eg = get s0 e;
    in
    if t == null then
      let s1 = typeerror s0 "COND" l r; in consttree s1 0 ty.inttype
    else if eg.op.gen == "CNST" && (eg.op.kind == "I" || eg.op.kind == "U")
    then cast s0 (if eg.value != 0 then l else r) t
    else
      let
        g = if t != ty.voidtype && t.size > 0
          then sy.genident s0 sy.sclasses.register (ty.unqual t) s0.level
          else { s = s0; v = null; };
        la = if g.v == null then { inherit (g) s; v = l; } else asgn g.s g.v l;
        ra = if g.v == null then { inherit (la) s; v = r; } else asgn la.s g.v r;
        lc = root ra.s la.v;
        rc = root lc.s ra.v;
        c = cond rc.s e;
        rt = tree c.s (ops.bare "RIGHT") t lc.v rc.v;
        p = tree rt.s (ops.bare "COND") t c.v rt.v;
      in
      { s = setsym p.s p.v g.v; inherit (p) v; };

  # --- the binary-operator constructors ----------------------------------
  arith2 = gname: s0: op: l0: r0:
    let
      lt = (get s0 l0).type;
      rt = (get s0 r0).type;
    in
    if ty.isarith lt && ty.isarith rt then
      let
        t = ty.binaryType lt rt;
        a = cast s0 l0 t;
        c = cast a.s r0 t;
      in
      simp.simplify c.s op t a.v c.v
    else
      let s1 = typeerror s0 gname l0 r0; in
      simp.simplify s1 op ty.inttype l0 r0;

  # enode.c's addtree/subtree. The pointer arms are what make `p + 1' step by
  # the pointee's size and `a[i]' mean anything: the INTEGER operand is scaled
  # by that size before the ADD, and the scaling is done here rather than in
  # the backend because it is a property of the C type and not of the machine.
  #
  # THE ORDER OF THE THREE ARMS IS LOAD-BEARING. `isptr(l) && isint(r)' does
  # not do the work; it RECURSES with the operands swapped, so there is exactly
  # one copy of the scaling and the pointer always ends up on the right of the
  # ADD+P that simp.nix then looks at. simp.c's ADD+P chain tests `l' for an
  # address op after commuting the constant to the right, and it only ever sees
  # the shape this swap produces.
  scaleIndex = s0: n: e0:
    let
      et = (get s0 e0).type;
      c0 = cast s0 e0 (ty.promote et);
      m =
        if n > 1 then
          let k = cnsttree c0.s ty.signedptr n; in
          multree k.s (ops.bare "MUL") k.v c0.v
        else c0;
      mt = (get m.s m.v).type;
    in
    cast m.s m.v (if ty.isunsigned mt then ty.unsignedptr else ty.signedptr);

  # "unknown size for type `%t'" is lcc's error for `void *p; p + 1'. It is an
  # ERROR and not a refusal, so it throws the way every other lcc error does
  # here (sym.nix's `err' says why), and the arithmetic below never runs on a
  # zero-sized element.
  elemSize = s: t:
    let n = (ty.unqual t.type).size; in
    if n == 0 then sy.err s "unknown size for type `${ty.outtype t.type}'\n" else n;

  addtree = s: op: l: r:
    let lt = (get s l).type; rt = (get s r).type; in
    if ty.isarith lt && ty.isarith rt then arith2 "ADD" s op l r
    else if ty.isptr lt && ty.isint rt then addtree s (ops.bare "ADD") r l
    else if ty.isptr rt && ty.isint lt && !(ty.isfunc (ty.unqual rt).type) then
      let
        t = ty.unqual rt;
        n = elemSize s t;
        x = scaleIndex s n l;
      in
      simp.simplify x.s (ops.bare "ADD") t x.v r
    else
      let s1 = typeerror s "ADD" l r; in
      simp.simplify s1 op ty.inttype l r;

  subtree = s: op: l: r:
    let lt = (get s l).type; rt = (get s r).type; in
    if ty.isarith lt && ty.isarith rt then arith2 "SUB" s op l r
    else if ty.isptr lt && !(ty.isfunc (ty.unqual lt).type) && ty.isint rt then
      let
        t = ty.unqual lt;
        n = elemSize s t;
        x = scaleIndex s n r;
      in
      simp.simplify x.s (ops.bare "SUB") t l x.v
    # `p - q' between compatible pointers: the byte difference, divided by the
    # element size. The division is a LONG one and the subtraction an UNSIGNED
    # one, both of which are lcc's choice and neither of which is obvious.
    else if compatiblePtr lt rt then
      let
        t = ty.unqual lt;
        n = elemSize s t;
        a = cast s l ty.unsignedptr;
        c = cast a.s r ty.unsignedptr;
        d = simp.simplify c.s (ops.mk "SUB" "U") ty.unsignedptr a.v c.v;
        e = cast d.s d.v ty.longtype;
        k = cnsttree e.s ty.longtype n;
      in
      simp.simplify k.s (ops.mk "DIV" "I") ty.longtype e.v k.v
    else
      let s1 = typeerror s "SUB" l r; in
      simp.simplify s1 op ty.inttype l r;

  # enode.c's compatible(): two object pointers whose pointees are eqtype.
  compatiblePtr = ty1: ty2:
    let
      a = ty.unqual ty1;
      c = ty.unqual ty2;
    in
    ty.isptr a && !(ty.isfunc a.type)
    && ty.isptr c && !(ty.isfunc c.type)
    && ty.eqtype (ty.unqual a.type) (ty.unqual c.type) false;

  multree = s: op: l: r: arith2 op.gen s op l r;

  bittree = s0: op: l0: r0:
    let lt = (get s0 l0).type; rt = (get s0 r0).type; in
    if ty.isint lt && ty.isint rt then
      let
        t = ty.binaryType lt rt;
        a = cast s0 l0 t;
        c = cast a.s r0 t;
      in
      simp.simplify c.s op t a.v c.v
    else
      let s1 = typeerror s0 op.gen l0 r0; in
      simp.simplify s1 op ty.inttype l0 r0;

  shtree = s0: op: l0: r0:
    let lt = (get s0 l0).type; rt = (get s0 r0).type; in
    if ty.isint lt && ty.isint rt then
      let
        t = ty.promote lt;
        a = cast s0 l0 t;
        c = cast a.s r0 ty.inttype;
      in
      simp.simplify c.s op t a.v c.v
    else
      let s1 = typeerror s0 op.gen l0 r0; in
      simp.simplify s1 op ty.inttype l0 r0;

  cmptree = s0: op: l0: r0:
    let lt = (get s0 l0).type; rt = (get s0 r0).type; in
    if ty.isarith lt && ty.isarith rt then
      let
        t = ty.binaryType lt rt;
        a = cast s0 l0 t;
        c = cast a.s r0 t;
      in
      simp.simplify c.s (ops.mkop op.gen t) ty.inttype a.v c.v
    else if compatible lt rt then
      let
        t = ty.unsignedptr;
        a = cast s0 l0 t;
        c = cast a.s r0 t;
      in
      simp.simplify c.s (ops.mkop op.gen t) ty.inttype a.v c.v
    else
      let s1 = typeerror s0 op.gen l0 r0; in
      simp.simplify s1 (ops.mkop op.gen ty.unsignedtype) ty.inttype l0 r0;

  eqtree = s0: op: l0: r0:
    let
      xty = ty.unqual (get s0 l0).type;
      yty = ty.unqual (get s0 r0).type;
    in
    if (ty.isptr xty && isnullptr s0 r0)
      || (ty.isptr xty && !(ty.isfunc xty.type) && isvoidptr yty)
      || (ty.isptr xty && ty.isptr yty && ty.unqual xty.type == ty.unqual yty.type)
    then
      let
        t = ty.unsignedptr;
        a = cast s0 l0 t;
        c = cast a.s r0 t;
      in
      simp.simplify c.s (ops.mkop op.gen t) ty.inttype a.v c.v
    else if (ty.isptr yty && isnullptr s0 l0)
      || (ty.isptr yty && !(ty.isfunc yty.type) && isvoidptr xty)
    then eqtree s0 op r0 l0
    else cmptree s0 op l0 r0;

  andtree = s0: op: l0: r0:
    let
      lt = (get s0 l0).type;
      rt = (get s0 r0).type;
      s1 = if !(ty.isscalar lt) || !(ty.isscalar rt)
        then typeerror s0 op.gen l0 r0 else s0;
      a = cond s1 l0;
      c = cond a.s r0;
    in
    simp.simplify c.s op ty.inttype a.v c.v;

  # --- calls -------------------------------------------------------------
  hascall = s: p:
    if p == null then false
    else if gen s p == "CALL" then true
    else hascall s (kid s p 0) || hascall s (kid s p 1);

  calltree = s0: f: t: args:
    let
      a = if args != null
        then tree s0 (ops.bare "RIGHT") (get s0 f).type args f
        else { s = s0; v = f; };
      rty0 = if ty.isenum t then (ty.unqual t).type else t;
      rty = if ty.isfloat rty0 then rty0 else ty.promote rty0;
      c = tree a.s (ops.mkop "CALL" rty) rty a.v null;
    in
    if ty.isptr t || rty.size > t.size then cast c.s c.v t else c;

  # --- expr.c's idtree ---------------------------------------------------
  idtree = s0: p0:
    let
      sym0 = sy.getsym s0 p0;
      t = if sym0.type != null then ty.unqual sym0.type else ty.voidptype;
      # lcc's chain, in order, because only the EXTERN arm substitutes the
      # alias and only that arm is reached when the first three miss.
      chosen =
        if sym0.scope == sy.GLOBAL || sym0.sclass == sy.sclasses.static then { op = "ADDRG"; sym = p0; }
        else if sym0.scope == sy.PARAM then { op = "ADDRF"; sym = p0; }
        else if sym0.sclass == sy.sclasses.extern then {
          op = "ADDRG";
          sym = if sym0.alias == null
          then sy.refuse s0 "trees: extern `${sym0.name}' has no alias in the externals table"
          else sym0.alias;
        }
        else { op = "ADDRL"; sym = p0; };
      opg = chosen.op;
      p = chosen.sym;
      s1 = sy.modsym s0 p (q: q // { ref = q.ref + s0.refinc; });
      sym = sy.getsym s1 p;
      e =
        if ty.isarray t then tree s1 (ops.mkop opg ty.voidptype) sym.type null null
        else if ty.isfunc t then tree s1 (ops.mkop opg ty.funcptype) sym.type null null
        else tree s1 (ops.mkop opg ty.voidptype) (ty.ptr sym.type) null null;
      e1 = { s = setsym e.s e.v p; inherit (e) v; };
    in
    if ty.isptr (get e1.s e1.v).type then rvalue e1.s e1.v else e1;

  incr = s: opgen: ctor: v: e:
    let a = ctor s (ops.bare opgen) v e; in
    asgntree a.s (ops.bare "ASGN") v a.v;
}
