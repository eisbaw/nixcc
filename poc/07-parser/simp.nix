# lcc/src/simp.c: constant folding and the algebraic identities lcc applies
# while BUILDING the tree, before the dag ever sees it.
#
# This is a rewrite, not a port (decision-002), for one reason and one only:
# lcc's UNSIGNED folding is C's wrapping arithmetic on `unsigned long', and in
# Nix integer overflow THROWS. Every unsigned fold below therefore reduces mod
# 2^32 WITHOUT ever forming the full product -- `mulmod32' splits its left
# operand at bit 16 so no intermediate exceeds 2^48.
#
# The SIGNED folds, by contrast, port verbatim. lcc's addi/subi/muli/divi are
# written predicatively -- they ask "would this overflow?" using division and
# comparison rather than performing the operation and inspecting the result --
# because C's signed overflow is undefined and lcc refuses to rely on it. That
# makes them exactly the shape Nix needs. It is luck, not foresight, but it is
# load-bearing luck: rewriting them would be a second chance to get the
# boundary cases wrong, and lcc's are already right.
#
# WHAT IS NOT HERE. Every float case throws, naming decision-006. simp.c's
# zerofield -- the bit-field rewrite in the EQ and NE cases -- now THROWS,
# naming task-059, and the change is the point rather than tidiness. It used to
# be ABSENT, on the recorded grounds that a bit field could not reach
# simplify() at all because parse.nix refused `struct' before a field could be
# declared. task-058 lifted exactly that gate. A guard satisfied by a refusal
# in another file is a guard that can be un-gated by an edit that never reads
# this one, and this is the only place in the frontend where that was true; it
# is now the only place where it is not. simp.c's addrtree -- the rewrite that
# turns `msg[2]' into `ADDRGP4 msg+8' -- throws naming the slice that owns it.
# A missing case is a throw rather than a fallthrough to `tree(op,...)',
# because a silently unsimplified tree is a node-for-node diff failure whose
# cause is invisible in the diff.
let
  b = builtins;
in
self:
let
  ty = self.types;
  inherit (self) ops;
  tr = self.trees;
  sy = self.sym;

  inherit (ty) pow2;
  mask32 = 4294967295;

  # (x * y) mod 2^32 without forming x*y. Splitting x rather than y keeps both
  # partial products under 2^48, well inside Nix's 63-bit range.
  mulmod32 = x: y:
    let
      hi = x / 65536;
      lo = b.bitAnd x 65535;
    in
    b.bitAnd (b.bitAnd (hi * y) 65535 * 65536 + lo * y) mask32;

  # Arithmetic (floor) right shift. Nix's `/' truncates toward zero, so a
  # negative dividend needs the correction; C's `>>' on a signed value rounds
  # toward minus infinity on every machine lcc targets.
  asr = x: n:
    let d = pow2 n; in
    if x >= 0 then x / d else 0 - ((0 - x + d - 1) / d);

  # simp.c's ispow2: n such that u == 2^n, for u > 1; 0 otherwise.
  ispow2 = u:
    if u > 1 && b.bitAnd u (u - 1) == 0 then
      let
        go = x: n: if b.bitAnd x 1 == 1 then n else go (x / 2) (n + 1);
      in
      go u 0
    else 0;
in
rec {
  inherit mulmod32 asr ispow2;

  # --- lcc's overflow predicates, verbatim -------------------------------
  # `needconst' turns each of these from a refusal into a warning, which is
  # what makes `enum { X = INT_MAX + 1 }' diagnose rather than silently not
  # fold. The warning text is lcc's, so it can be diffed (criterion #7).
  guard = s: cond: if cond then { inherit s; v = true; }
  else if s.needconst > 0 then { s = sy.warn s "overflow in constant expression\n"; v = true; }
  else { inherit s; v = false; };

  addi = s: x: y: mn: mx:
    guard s (x == 0 || y == 0
      || (x < 0 && y < 0 && x >= mn - y)
      || (x < 0 && y > 0)
      || (x > 0 && y < 0)
      || (x > 0 && y > 0 && x <= mx - y));

  subi = s: x: y: mn: mx: addi s x (0 - y) mn mx;

  muli = s: x: y: mn: mx:
    guard s ((x > (0 - 1) && x <= 1) || (y > (0 - 1) && y <= 1)
      || (x < 0 && y < 0 && (0 - x) <= mx / (0 - y))
      || (x < 0 && y > 0 && x >= mn / y)
      || (x > 0 && y < 0 && y >= mn / x)
      || (x > 0 && y > 0 && x <= mx / y));

  divi = s: x: y: mn: _mx: guard s (y != 0 && !(x == mn && y == (0 - 1)));

  # --- the entry point ---------------------------------------------------
  # `op' may arrive without a kind letter, exactly as lcc's callers pass a bare
  # generic op and let simplify's first line supply `mkop(op, ty)'.
  simplify = s: op0: t: l: r:
    let
      op = if op0.kind == "" then ops.mkop op0.gen t else op0;
      key = "${op.gen}+${op.kind}";
      fn = cases.${key} or (sy.refuse s
        "simp: no rule for `${key}'; ${
          if op.kind == "F" || op.kind == "D"
          then "floating-point support is deferred (decision-006, task-015)"
          else "this opcode is outside slice 1"}");
    in
    fn s t l r;

  # --- helpers over tree ids ---------------------------------------------
  isCnst = s: p: k: p != null && (tr.get s p).op.gen == "CNST" && (tr.get s p).op.kind == k;
  cval = s: p: (tr.get s p).value;
  gen = s: p: (tr.get s p).op.gen;
  kindOf = s: p: (tr.get s p).op.kind;
  isOp = s: p: g: k: p != null && gen s p == g && kindOf s p == k;
  isCnstAny = s: p: p != null && gen s p == "CNST";
  isAddrop = s: p: p != null && ops.isaddrop (tr.get s p).op;

  # --- simp.c's addrtree --------------------------------------------------
  # `msg[8]' does not become an add. It becomes ONE node, `ADDRGP4 msg+8', over
  # a symbol this function invents -- so the displacement is carried by the
  # symbol table and resolved by the assembler (task-023), and the backend
  # never sees an addition it would have to fold back.
  #
  # The two branches are not a detail. A base at file scope gets its symbol
  # NAMED and PRINTED immediately, which is why `address msg+8' lines appear
  # before the `export' line of the function that produced them. A base on the
  # frame cannot be named yet -- its offset is not assigned until gencode lays
  # the frame out -- so it becomes an Address CODE ITEM instead, and the line
  # appears in the middle of the function body, in code order.
  addrtree = s0: e: n: t:
    let
      et = tr.get s0 e;
      p = et.sym;
      ps = sy.getsym s0 p;
      atGlobal = ps.scope == sy.GLOBAL
        || ps.sclass == sy.sclasses.static
        || ps.sclass == sy.sclasses.extern;
      g = sy.genlabel s0 1;
      r = sy.newsym g.s {
        # Overwritten by listing.address on the global path; on the local path
        # this generated number IS the name, until gencode renames it.
        name = toString g.v;
        sclass =
          if atGlobal && ps.sclass == sy.sclasses.auto
          then sy.sclasses.static else ps.sclass;
        inherit (ps) scope temporary generated addressed;
        type = if ty.isptr t then (ty.unqual t).type else t;
        computed = true;
        defined = true;
        ref = 1.0;
      };
      s1 =
        if atGlobal then self.listing.address r.s r.v p n
        else
          let a = sy.addlocal r.s p; in
          (sy.code a "Address" { sym = r.v; base = p; offset = n; }).s;
      nt = tr.tree s1 et.op t null null;
    in
    { s = tr.setsym nt.s nt.v r.v; inherit (nt) v; };

  # commute(L,R) in simp.c: if R is a constant and L is not, swap them. The
  # call sites read `commute(r,l)' (constant to the right) and `commute(l,r)'
  # (constant to the left), so the direction is the caller's, not ours.
  commuteRight = s: l: r:
    if gen s l == "CNST" && gen s r != "CNST" then { l = r; r = l; } else { inherit l r; };
  commuteLeft = s: l: r:
    if gen s r == "CNST" && gen s l != "CNST" then { l = r; r = l; } else { inherit l r; };

  # identity(X,Y,TYPE,VAR,VAL): X is a constant equal to VAL, so the operation
  # is the identity and Y is the answer.
  identity = s: x: y: k: v: if isCnst s x k && cval s x == v then y else null;

  cases =
    let
      # --- shorthands used by the case table ---------------------------
      fold2 = k: f: s: t: l: r:
        if isCnst s l k && isCnst s r k
        then tr.cnsttree s t (f (cval s l) (cval s r))
        else null;

      # A comparison folds to an `int', never to the operand type.
      cfold = k: f: s: _t: l: r:
        if isCnst s l k && isCnst s r k
        then tr.cnsttree s ty.inttype (if f (cval s l) (cval s r) then 1 else 0)
        else null;

      # Guarded signed fold: the predicate decides whether the fold happens.
      xfold = pred: f: s: t: l: r:
        if isCnst s l "I" && isCnst s r "I" then
          let
            lim = ty.limits t;
            g = pred s (cval s l) (cval s r) lim.min lim.max;
          in
          if g.v then tr.cnsttree g.s t (f (cval s l) (cval s r)) else { inherit (g) s; v = null; }
        else null;

      # Run a list of rules in order; the first that yields a tree wins, and
      # anything left over falls through to the unsimplified tree. A rule may
      # also return `stop', which is simp.c's `break' out of the case: no more
      # rules run and the unsimplified tree is the answer. Only the guard on a
      # generated symbol's displacement uses it, and without it that guard
      # would be indistinguishable from "this rule did not apply", which is a
      # different thing -- the rules after it WOULD have applied.
      chain = op: rules: s0: t: l0: r0:
        let
          go = st: l: r: rs:
            if rs == [ ] then tr.tree st op t l r
            else
              let x = (b.head rs) st t l r; in
              if x == null then go st l r (b.tail rs)
              else if x ? swap then go x.s x.l x.r (b.tail rs)
              else if x ? stop then tr.tree x.s op t l r
              else if x.v == null then go x.s l r (b.tail rs)
              else x;
        in
        go s0 l0 r0 rules;

      swapRight = s: _t: l: r:
        let c = commuteRight s l r; in
        if c.l == l then null else { inherit s; swap = true; inherit (c) l r; };
      swapLeft = s: _t: l: r:
        let c = commuteLeft s l r; in
        if c.l == l then null else { inherit s; swap = true; inherit (c) l r; };

      idR = k: v: s: _t: l: r: let x = identity s r l k v; in if x == null then null else { inherit s; v = x; };
      # `identity(r, l, T, v, ones(8*ty->size))' -- the all-ones mask, whose
      # width comes from the type rather than from a constant.
      idI = k: s: t: l: r: idR k (ty.ones (8 * (ty.unqual t).size)) s t l r;

      lift = f: s: t: l: r: f s t l r;

      # simp.c's zerofield(): `bitfield == 0' is rewritten into a mask and a
      # comparison against the whole word, because there is no compare that
      # takes a bit range. It is a REFUSAL here rather than a rewrite -- a bit
      # field has no `lsb' or `bitsize' in this frontend to build the mask out
      # of (task-059).
      #
      # It is UNREACHABLE today: parse.nix's `fields' refuses a `:' in a member
      # declaration, so no FIELD tree is ever built. That is the point of
      # having it anyway. Until task-058 the same argument was made one file
      # further away -- `struct' itself was refused -- and lifting that refusal
      # would have un-gated this rewrite silently, in an edit that never opened
      # simp.nix. The guard now sits where the rewrite would have gone.
      zerofield = k: s: _t: l: r:
        if l != null && gen s l == "FIELD" && isCnst s r k && cval s r == 0
        then sy.refuse s "simp: comparing a bit field against zero needs its mask (task-059)"
        else null;

      # `(l, C)' -- evaluate l for its side effects, yield the constant C.
      rightConst = mkc: s: t: l: _r:
        let
          rt = tr.root s l;
          c = mkc rt.s t;
        in
        tr.tree c.s (ops.bare "RIGHT") t rt.v c.v;

      # --- the ADD+P / SUB+P rules -------------------------------------
      # simp.c's four `foldaddp' lines: a pointer constant plus an integer
      # constant is a pointer constant. `(char *)0 + 3' is the whole of what
      # they fold, and a null pointer constant is the reason CNST+P exists at
      # all -- `p = 0' produces one, which is ordinary C and not a corner.
      foldaddp = k: flip: s: t: l: r:
        let
          a = if flip then r else l;
          c = if flip then l else r;
        in
        if isCnst s a "P" && isCnst s c k
        then tr.cnsttree s t (cval s a + cval s c)
        else null;

      # `identity(r, retype(l,ty), I, i, 0)': `p + 0' is p, wearing the type
      # the addition would have produced.
      idRetype = k: s: t: l: r:
        if isCnst s r k && cval s r == 0 then tr.retype s l t else null;

      # The displacement a generated base can carry. simp.c breaks out here
      # rather than calling addrtree, because an assembler may not be able to
      # spell a large offset from a compiler-generated symbol; the comment in
      # simp.c names the MIPS. Left in because dropping it would change which
      # shape reaches the backend, not merely how fast.
      tooFarFromGenerated = s: _t: l: r:
        if isOp s l "ADDRG" "P" && (sy.getsym s (tr.get s l).sym).generated
          && ((isCnst s r "I" && (cval s r > 32767 || cval s r < (0 - 32768)))
            || (isCnst s r "U" && cval s r > 65536))
        then { inherit s; v = null; stop = true; }
        else null;

      # `r' is a constant that fits a long: fold it into the base symbol.
      cnstFitsLong = s: r:
        let lim = ty.limits ty.longtype; in
        (isCnst s r "I" && cval s r <= lim.max && cval s r >= lim.min)
        || (isCnst s r "U" && cval s r <= lim.max);

      foldIntoAddr = s: t: l: r:
        if isAddrop s l && cnstFitsLong s r then addrtree s l (cval s r) t else null;

      # `(x + &a) + C' -- the address is the RIGHT kid of an inner ADD+P, so
      # the constant folds into it and the index survives outside.
      foldIntoInnerAddr = s: t: l: r:
        if isOp s l "ADD" "P" && isAddrop s (tr.kid s l 1) && cnstFitsLong s r
        then
          let a = addrtree s (tr.kid s l 1) (cval s r) t; in
          simplify a.s (ops.mk "ADD" "P") t (tr.kid a.s l 0) a.v
        else null;

      # `(i + C) + &a' -- reassociate so the constant meets the address.
      reassocIndex = s: t: l: r:
        if (isOp s l "ADD" "I" || isOp s l "SUB" "I")
          && isCnst s (tr.kid s l 1) "I" && isAddrop s r
        then
          let a = simplify s (ops.mk (gen s l) "P") t r (tr.kid s l 1); in
          simplify a.s (ops.mk "ADD" "P") t (tr.kid a.s l 0) a.v
        else null;

      # `(x + C1) + C2' over a pointer: add the two constants.
      foldTwoCnsts = s: t: l: r:
        if isOp s l "ADD" "P" && isCnstAny s (tr.kid s l 1) && isCnstAny s r
        then
          let
            k1 = tr.kid s l 1;
            a = simplify s (ops.bare "ADD") (tr.get s k1).type k1 r;
          in
          simplify a.s (ops.mk "ADD" "P") t (tr.kid a.s l 0) a.v
        else null;

      # `(i + C1) + (x + C2)' with both constants folded together.
      foldAcrossBoth = s: t: l: r:
        if isOp s l "ADD" "I" && isCnstAny s (tr.kid s l 1)
          && isOp s r "ADD" "P" && isCnstAny s (tr.kid s r 1)
        then
          let
            k1 = tr.kid s l 1;
            k2 = tr.kid s r 1;
            a = simplify s (ops.bare "ADD") (tr.get s k1).type k1 k2;
            c = simplify a.s (ops.mk "ADD" "P") t (tr.kid a.s r 0) a.v;
          in
          simplify c.s (ops.mk "ADD" "P") t (tr.kid c.s l 0) c.v
        else null;

      # `(e, p) + C' -- the addition belongs inside the comma, so that the
      # side effect stays on the left of the RIGHT tree it came in on.
      addThroughRight = s: t: l: r:
        if gen s l == "RIGHT" && tr.kid s l 1 != null then
          let a = simplify s (ops.mk "ADD" "P") t (tr.kid s l 1) r; in
          tr.tree a.s (ops.bare "RIGHT") t (tr.kid a.s l 0) a.v
        else if gen s l == "RIGHT" && tr.kid s l 0 != null then
          let a = simplify s (ops.mk "ADD" "P") t (tr.kid s l 0) r; in
          tr.tree a.s (ops.bare "RIGHT") t a.v null
        else null;

      # `p - C' is `p + (-C)', which is the only way a SUB+P ever reaches
      # addrtree: the whole displacement machinery is on the ADD side.
      # `(char *)8 - (char *)2'. The result is a POINTER constant holding the
      # byte difference, which is lcc's own choice and reads oddly; it is
      # ported rather than corrected, because the type the tree wears is what
      # the listing prints.
      subTwoCnsts = s: t: l: r:
        if isCnst s l "P" && isCnst s r "P"
        then tr.cnsttree s t (cval s l - cval s r)
        else null;

      # simp.c writes the two negations separately -- `-r->u.v.i' and
      # `-(long)r->u.v.u' -- because in C those are different expressions on
      # different members of a union. Here an unsigned value is already a
      # non-negative Nix integer, so there is one negation and this comment is
      # the record that the difference was looked at rather than missed.
      subCnstToAdd = s: t: l: r:
        if isCnst s r "I" || isCnst s r "U" then
          let c = tr.cnsttree s ty.inttype (0 - cval s r); in
          simplify c.s (ops.bare "ADD") t l c.v
        else null;

      # `l - (x + C)' => `(l - C) - x'.
      subThroughAdd = s: t: l: r:
        if isAddrop s l && isOp s r "ADD" "I" && isCnst s (tr.kid s r 1) "I"
        then
          let a = simplify s (ops.bare "SUB") t l (tr.kid s r 1); in
          simplify a.s (ops.bare "SUB") t a.v (tr.kid a.s r 0)
        else null;
    in
    {
      # ---- ADD ----
      "ADD+I" = chain (ops.mk "ADD" "I") [ (xfold addi (x: y: x + y)) swapRight (idR "I" 0) ];
      "ADD+U" = chain (ops.mk "ADD" "U") [ (fold2 "U" (x: y: b.bitAnd (x + y) mask32)) swapRight (idR "U" 0) ];
      # The order here is simp.c's line order and nothing else. Two of these
      # rules would fire on the same tree -- `foldIntoAddr' and
      # `foldIntoInnerAddr' both match `(&a + C)' once the first has run -- so
      # reordering them changes the IR rather than merely the route to it.
      "ADD+P" = chain (ops.mk "ADD" "P") [
        (foldaddp "I" false)
        (foldaddp "U" false)
        (foldaddp "I" true)
        (foldaddp "U" true)
        swapRight
        (idRetype "I")
        (idRetype "U")
        tooFarFromGenerated
        foldIntoAddr
        foldIntoInnerAddr
        reassocIndex
        foldTwoCnsts
        foldAcrossBoth
        addThroughRight
      ];

      # ---- SUB ----
      "SUB+I" = chain (ops.mk "SUB" "I") [ (xfold subi (x: y: x - y)) (idR "I" 0) ];
      "SUB+U" = chain (ops.mk "SUB" "U") [ (fold2 "U" (x: y: b.bitAnd (x - y) mask32)) (idR "U" 0) ];
      "SUB+P" = chain (ops.mk "SUB" "P") [ subTwoCnsts subCnstToAdd subThroughAdd ];

      # ---- MUL / DIV / MOD ----
      # The 2^n rewrites are why `x * 4' and `x / 4u' reach the backend as
      # shifts; task-010 records that MULI4/DIVI4/MODI4 are libcalls for us and
      # inline for the oracle, so the ones that survive matter.
      "MUL+I" = chain (ops.mk "MUL" "I") [
        swapLeft
        (xfold muli (x: y: x * y))
        (lift (s: t: l: r:
          if isCnst s l "I" && (tr.get s r).op.gen == "ADD" && (tr.get s r).op.kind == "I"
            && isCnst s (b.elemAt (tr.get s r).kids 1) "I"
          then
            let
              rk = (tr.get s r).kids;
              a = simplify s (ops.bare "MUL") t l (b.elemAt rk 0);
              c = simplify a.s (ops.bare "MUL") t l (b.elemAt rk 1);
            in
            simplify c.s (ops.bare "ADD") t a.v c.v
          else null))
        (lift (s: t: l: r:
          if isCnst s l "I" && (tr.get s r).op.gen == "SUB" && (tr.get s r).op.kind == "I"
            && isCnst s (b.elemAt (tr.get s r).kids 1) "I"
          then
            let
              rk = (tr.get s r).kids;
              a = simplify s (ops.bare "MUL") t l (b.elemAt rk 0);
              c = simplify a.s (ops.bare "MUL") t l (b.elemAt rk 1);
            in
            simplify c.s (ops.bare "SUB") t a.v c.v
          else null))
        (lift (s: t: l: r:
          if isCnst s l "I" && cval s l > 0 && ispow2 (cval s l) != 0
          then
            let n = tr.cnsttree s ty.inttype (ispow2 (cval s l)); in
            simplify n.s (ops.bare "LSH") t r n.v
          else null))
        (idR "I" 1)
      ];
      "MUL+U" = chain (ops.mk "MUL" "U") [
        swapLeft
        (lift (s: t: l: r:
          if isCnst s l "U" && ispow2 (cval s l) != 0
          then
            let n = tr.cnsttree s ty.inttype (ispow2 (cval s l)); in
            simplify n.s (ops.bare "LSH") t r n.v
          else null))
        (fold2 "U" mulmod32)
        (idR "U" 1)
      ];
      "DIV+I" = chain (ops.mk "DIV" "I") [
        (idR "I" 1)
        (lift (s: t: l: r:
          let lim = ty.limits t; in
          if (isCnst s r "I" && cval s r == 0)
            || (isCnst s l "I" && cval s l == lim.min && isCnst s r "I" && cval s r == (0 - 1))
          then tr.tree s (ops.mk "DIV" "I") t l r
          else null))
        (xfold divi (x: y: let q = x / y; in q))
      ];
      "DIV+U" = chain (ops.mk "DIV" "U") [
        (idR "U" 1)
        (lift (s: t: l: r:
          if isCnst s r "U" && cval s r == 0
          then tr.tree s (ops.mk "DIV" "U") t l r else null))
        (lift (s: t: l: r:
          if isCnst s r "U" && ispow2 (cval s r) != 0
          then
            let n = tr.cnsttree s ty.inttype (ispow2 (cval s r)); in
            simplify n.s (ops.bare "RSH") t l n.v
          else null))
        (fold2 "U" (x: y: x / y))
      ];
      "MOD+I" = chain (ops.mk "MOD" "I") [
        (lift (s: t: l: r:
          let lim = ty.limits t; in
          if (isCnst s r "I" && cval s r == 0)
            || (isCnst s l "I" && cval s l == lim.min && isCnst s r "I" && cval s r == (0 - 1))
          then tr.tree s (ops.mk "MOD" "I") t l r
          else null))
        (xfold divi (x: y: x - (x / y) * y))
        (lift (s: t: l: r:
          if isCnst s r "I" && cval s r == 1
          then (rightConst (st: tt: tr.cnsttree st tt 0)) s t l r
          else null))
      ];
      "MOD+U" = chain (ops.mk "MOD" "U") [
        (lift (s: t: l: r:
          if isCnst s r "U" && ispow2 (cval s r) != 0
          then
            let c = tr.cnsttree s t (cval s r - 1); in
            tr.bittree c.s (ops.bare "BAND") l c.v
          else null))
        (lift (s: t: l: r:
          if isCnst s r "U" && cval s r == 0
          then tr.tree s (ops.mk "MOD" "U") t l r else null))
        (fold2 "U" (x: y: x - (x / y) * y))
      ];

      # ---- shifts ----
      # The "shifting by N bits is undefined" warning is one of the few this
      # subset can actually emit, so it is spelled exactly as lcc spells it.
      "LSH+I" = chain (ops.mk "LSH" "I") [
        (idR "I" 0)
        (lift (s: t: l: r:
          if isCnst s l "I" && isCnst s r "I" && cval s r >= 0
            && cval s r < 8 * (ty.unqual (tr.get s l).type).size
          then
            let
              lim = ty.limits t;
              # simp.c's guard is `muli(l, 1<<r, ...)' where the literal 1 is an
              # `int', so at a shift of 31 the multiplier is INT_MIN and
              # SIGN-EXTENDS to -2147483648L. Passing the mathematical 2^31
              # instead lands in a different arm of muli and folds `-1 << 31'
              # that lcc leaves alone. The VALUE is still computed with the
              # mathematical power, because lcc computes it as a long.
              g = muli s (cval s l) (ty.extend (pow2 (cval s r)) ty.inttype) lim.min lim.max;
            in
            if g.v then tr.cnsttree g.s t (cval s l * pow2 (cval s r)) else { inherit (g) s; v = null; }
          else null))
        (shiftWarn (ops.mk "LSH" "I"))
      ];
      "LSH+U" = chain (ops.mk "LSH" "U") [
        (idR "I" 0)
        (lift (s: t: l: r:
          if isCnst s l "U" && isCnst s r "I" && cval s r >= 0
            && cval s r < 8 * (ty.unqual (tr.get s l).type).size
          then tr.cnsttree s t (mulmod32 (cval s l) (pow2 (cval s r)))
          else null))
        (shiftWarn (ops.mk "LSH" "U"))
      ];
      "RSH+I" = chain (ops.mk "RSH" "I") [
        (idR "I" 0)
        (lift (s: t: l: r:
          if isCnst s l "I" && isCnst s r "I" && cval s r >= 0
            && cval s r < 8 * (ty.unqual (tr.get s l).type).size
          then tr.cnsttree s t (asr (cval s l) (cval s r))
          else null))
        (shiftWarn (ops.mk "RSH" "I"))
      ];
      "RSH+U" = chain (ops.mk "RSH" "U") [
        (idR "I" 0)
        (lift (s: t: l: r:
          if isCnst s l "U" && isCnst s r "I" && cval s r >= 0
            && cval s r < 8 * (ty.unqual (tr.get s l).type).size
          then tr.cnsttree s t (cval s l / pow2 (cval s r))
          else null))
        (shiftWarn (ops.mk "RSH" "U"))
      ];

      # ---- bitwise ----
      # `ones(8*ty->size)', not a fixed 32: BCOM two cases down already writes
      # it that way, and the two disagreeing is how a sub-int type would pick
      # up the wrong identity if `binary' ever returned one.
      "BAND+I" = chain (ops.mk "BAND" "I") [
        (fold2 "I" b.bitAnd) swapRight (idI "I")
        (lift (s: t: l: r:
          if isCnst s r "I" && cval s r == 0
          then (rightConst (st: tt: tr.cnsttree st tt 0)) s t l r else null))
      ];
      "BAND+U" = chain (ops.mk "BAND" "U") [
        (fold2 "U" b.bitAnd) swapRight (idI "U")
        (lift (s: t: l: r:
          if isCnst s r "U" && cval s r == 0
          then (rightConst (st: tt: tr.cnsttree st tt 0)) s t l r else null))
      ];
      "BOR+I" = chain (ops.mk "BOR" "I") [ (fold2 "I" b.bitOr) swapRight (idR "I" 0) ];
      "BOR+U" = chain (ops.mk "BOR" "U") [ (fold2 "U" b.bitOr) swapRight (idR "U" 0) ];
      "BXOR+I" = chain (ops.mk "BXOR" "I") [ (fold2 "I" b.bitXor) swapRight (idR "I" 0) ];
      "BXOR+U" = chain (ops.mk "BXOR" "U") [ (fold2 "U" b.bitXor) swapRight (idR "U" 0) ];

      "BCOM+I" = chain (ops.mk "BCOM" "I") [
        (lift (s: t: l: _r:
          if isCnst s l "I"
          then tr.cnsttree s t (ty.extend (b.bitAnd (0 - cval s l - 1) (ty.ones (8 * (ty.unqual t).size))) t)
          else null))
        (idempotent "BCOM" "U")
      ];
      "BCOM+U" = chain (ops.mk "BCOM" "U") [
        (lift (s: t: l: _r:
          if isCnst s l "U"
          then tr.cnsttree s t (b.bitAnd (0 - cval s l - 1) (ty.ones (8 * (ty.unqual t).size)))
          else null))
        (idempotent "BCOM" "U")
      ];

      "NEG+I" = chain (ops.mk "NEG" "I") [
        (lift (s: t: l: _r:
          if isCnst s l "I" then
            let
              lim = ty.limits t;
              over = cval s l == lim.min;
              s1 = if s.needconst > 0 && over then sy.warn s "overflow in constant expression\n" else s;
            in
            if s.needconst > 0 || !over then tr.cnsttree s1 t (0 - cval s l) else { s = s1; v = null; }
          else null))
        (idempotent "NEG" "I")
      ];

      # ---- logical ----
      # AND/OR/NOT lose their type letter: lcc rewrites `op = AND' so the tree
      # op prints as a bare "AND", which is what tree.c's opname does for the
      # six ops whose opsize is zero.
      "AND+I" = chain (ops.bare "AND") [
        (lift (s: _t: l: r:
          if isCnst s l "I"
          then (if cval s l != 0 then tr.cond s r else { inherit s; v = l; })
          else null))
      ];
      "OR+I" = chain (ops.bare "OR") [
        (lift (s: t: l: r:
          if isCnst s l "I"
          then (if cval s l != 0 then tr.cnsttree s t 1 else tr.cond s r)
          else null))
      ];
      "NOT+I" = chain (ops.bare "NOT") [
        (lift (s: t: l: _r:
          if isCnst s l "I" then tr.cnsttree s t (if cval s l == 0 then 1 else 0) else null))
      ];

      # ---- comparisons ----
      # The four `zerofield' entries sit exactly where simp.c's macro does,
      # after the fold and the commute, because the rewrite it stands for reads
      # the LEFT operand and the commute is what put the constant on the right.
      "EQ+I" = chain (ops.mk "EQ" "I") [ (cfold "I" (x: y: x == y)) swapRight (zerofield "I") ];
      "EQ+U" = chain (ops.mk "EQ" "U") [ (cfold "U" (x: y: x == y)) swapRight (zerofield "U") ];
      "NE+I" = chain (ops.mk "NE" "I") [ (cfold "I" (x: y: x != y)) swapRight (zerofield "I") ];
      "NE+U" = chain (ops.mk "NE" "U") [ (cfold "U" (x: y: x != y)) swapRight (zerofield "U") ];
      "GE+I" = chain (ops.mk "GE" "I") [ (cfold "I" (x: y: x >= y)) ];
      "GT+I" = chain (ops.mk "GT" "I") [ (cfold "I" (x: y: x > y)) ];
      "LE+I" = chain (ops.mk "LE" "I") [ (cfold "I" (x: y: x <= y)) ];
      "LT+I" = chain (ops.mk "LT" "I") [ (cfold "I" (x: y: x < y)) ];

      # The unsigned comparisons carry lcc's four constant-result rewrites.
      # `u >= 0' is always true and lcc SAYS SO; dropping the warning would be
      # exactly the silent-diagnostic regression criterion #7 exists to catch.
      "GE+U" = chain (ops.mk "GE" "U") [
        (geu "l" 1) (cfold "U" (x: y: x >= y))
        (lift (s: _t: l: r:
          if isCnst s l "U" && cval s l == 0 then tr.eqtree s (ops.bare "EQ") r l else null))
      ];
      "GT+U" = chain (ops.mk "GT" "U") [
        (geu "r" 0) (cfold "U" (x: y: x > y))
        (lift (s: _t: l: r:
          if isCnst s r "U" && cval s r == 0 then tr.eqtree s (ops.bare "NE") l r else null))
      ];
      "LE+U" = chain (ops.mk "LE" "U") [
        (geu "r" 1) (cfold "U" (x: y: x <= y))
        (lift (s: _t: l: r:
          if isCnst s r "U" && cval s r == 0 then tr.eqtree s (ops.bare "EQ") l r else null))
      ];
      "LT+U" = chain (ops.mk "LT" "U") [
        (geu "l" 0) (cfold "U" (x: y: x < y))
        (lift (s: _t: l: r:
          if isCnst s l "U" && cval s l == 0 then tr.eqtree s (ops.bare "NE") r l else null))
      ];

      # ---- conversions ----
      "CVI+I" = chain (ops.mk "CVI" "I") [ (cvt "I" (_s: t: v: ty.extend v t)) ];
      "CVI+U" = chain (ops.mk "CVI" "U") [ (cvt "I" (_s: t: v: ty.lowBits v t)) ];
      "CVU+U" = chain (ops.mk "CVU" "U") [ (cvt "U" (_s: t: v: ty.lowBits v t)) ];
      "CVU+I" = chain (ops.mk "CVU" "I") [
        (lift (s: t: l: _r:
          if isCnst s l "U" then
            let
              over = cval s l > (ty.limits t).max;
              s1 = if s.explicitCast == 0 && over
                then sy.warn s "overflow in converting constant expression from `${
                  ty.outtype (tr.get s l).type}' to `${ty.outtype t}'\n"
                else s;
            in
            if s1.needconst > 0 || !over then tr.cnsttree s1 t (ty.extend (cval s l) t)
            else { s = s1; v = null; }
          else null))
      ];
      # The three conversions a pointer takes part in. Each folds only when
      # its operand is a constant and the value is inside the DESTINATION's
      # limits, which for a pointer are types.c's `T*' symbol: zero to
      # all-ones over the pointer width. `p - q' in trees.nix reaches CVP+U on
      # two ordinary pointers and gets the unfolded tree, which is the common
      # case and the one the fold must not disturb.
      "CVP+U" = chain (ops.mk "CVP" "U") [ (cvt "P" (_s: _t: v: v)) ];
      "CVP+P" = chain (ops.mk "CVP" "P") [ (cvt "P" (_s: _t: v: v)) ];
      "CVU+P" = chain (ops.mk "CVU" "P") [ (cvt "U" (_s: _t: v: v)) ];
    };

  # xcvtcnst: fold a constant conversion, warning when the value does not fit
  # and folding anyway when a constant expression is required.
  cvt = k: f: s: t: l: _r:
    if isCnst s l k then
      let
        lim = ty.limits t;
        v = cval s l;
        over = v < lim.min || v > lim.max;
        s1 = if s.explicitCast == 0 && over
          then sy.warn s "overflow in converting constant expression from `${
            ty.outtype (tr.get s l).type}' to `${ty.outtype t}'\n"
          else s;
      in
      if s1.needconst > 0 || !over then tr.cnsttree s1 t (f s1 t v) else { s = s1; v = null; }
    else null;

  # simp.c's idempotent(OP): ~~x is x, --x is x.
  idempotent = g: k: s: _t: l: _r:
    if (tr.get s l).op.gen == g && (tr.get s l).op.kind == k
    then { inherit s; v = b.elemAt (tr.get s l).kids 0; }
    else null;

  # simp.c's geu(L,R,V): an unsigned comparison whose other operand is the
  # constant 0, so the answer does not depend on the value -- but the operand
  # still has to be evaluated for its side effects, hence `(L, V)'.
  # `keep' names which operand survives; the OTHER one is the one that must be
  # the zero constant.
  geu = keep: v: s: _t: l: r:
    let
      surv = if keep == "l" then l else r;
      zero = if keep == "l" then r else l;
    in
    if isCnst s zero "U" && cval s zero == 0 then
      let
        s0 = sy.warn s "result of unsigned comparison is constant\n";
        rt = tr.root s0 surv;
        c = tr.cnsttree rt.s ty.inttype v;
      in
      tr.tree c.s (ops.bare "RIGHT") ty.inttype rt.v c.v
    else null;

  # The shift-count warning. Both of simp.c's arms `break', so this only
  # records the diagnostic and lets the chain fall through to the plain tree.
  shiftWarn = _op: s: t: _l: r:
    if isCnst s r "I" && (cval s r >= 8 * (ty.unqual t).size || cval s r < 0)
    then {
      s = sy.warn s "shifting an `${ty.outtype t}' by ${toString (cval s r)} bits is undefined\n";
      v = null;
    }
    else null;
}
