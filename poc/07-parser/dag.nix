# lcc/src/dag.c, plus the node numbering from lcc/src/symbolic.c's visit().
#
# This is the file decision-002 singled out as a rewrite rather than a port,
# and here is why, concretely. lcc's CSE table hashes a MACHINE ADDRESS --
# `(opindex(op) ^ ((unsigned long)sym>>2)) & 15' -- and its bucket comparison
# tests `p->node.kids[0] == l', a pointer against a pointer. Nix has neither,
# so nodes and symbols are interned to integer ids first and the hash becomes a
# structural key over (op, sym id, kid ids). The EFFECT is identical because
# lcc's pointers are themselves interned: a symbol is one Symbol and a subtree
# is one Node, so pointer equality was already value equality.
#
# THE ORACLE RUNS wants_dag = 1 (lcc/src/symbolic.c's Interface record), which
# takes three whole passes out of this file: undag(), prune() and the CSE
# temporaries in visit() are all `!IR->wants_dag' paths. What survives is
# listnodes, the node table, and symbolic.c's own two-line numbering walk.
#
# NUMBERING, since criterion #3 turns on it. symbolic.c's visit() assigns
# `x.inst = ++n' on the way DOWN (parent before kids) and appends to the node
# list on the way UP (kids before parent). So `1'' is always the root and the
# printed order is post-order. A node already numbered is skipped, which is
# what makes a shared subexpression appear once with `count=k'.
let
  b = builtins;
in
self:
let
  ty = self.types;
  inherit (self) ops;
  sy = self.sym;
  tr = self.trees;
  st = self.store;
in
rec {
  getnode = s: id:
    if id == null then throw "dag: null node dereferenced"
    else st.get "node" s.nodes id;

  modnode = s: id: f: s // { nodes = st.set s.nodes id (f (getnode s id)); };

  emptyNode = {
    op = null;
    kids = [ null null ];
    syms = [ null null ];
    count = 0;
    listed = false; # x.listed: on the forest's root list
    linked = false; # lcc's `p->link != NULL' -- already in this forest
    inst = 0; # x.inst: the printed node number
  };

  # dagnode(): a fresh node, and one more reference on each kid it takes.
  newnode = s0: op: l: r: symid:
    let
      id = s0.nextnode;
      bump = s: k: if k == null then s else modnode s k (n: n // { count = n.count + 1; });
      s1 = s0 // {
        nextnode = id + 1;
        nodes = st.set s0.nodes id (emptyNode // {
          inherit id;
          op = ops.check op;
          kids = [ l r ];
          syms = [ symid null ];
        });
      };
      s2 = bump (bump s1 l) r;
    in
    { s = s2; v = id; };

  cseKey = op: l: r: symid:
    "${op.gen}${op.kind}${toString (op.size or 0)}|${toString symid}|${toString l}|${toString r}";

  # node(): the CSE'ing constructor. Every arithmetic and address node goes
  # through this; ASGN, ARG, CALL, RET, JUMP and LABEL go through newnode,
  # because a statement is never a common subexpression.
  node = s: op: l: r: symid:
    let key = cseKey op l r symid; in
    if s.buckets ? ${key} then { inherit s; v = s.buckets.${key}; }
    else
      let n = newnode s op l r symid; in
      {
        s = n.s // {
          buckets = n.s.buckets // { ${key} = n.v; };
          nodecount = n.s.nodecount + 1;
        };
        inherit (n) v;
      };

  # An assignment through a pointer, or to `p', invalidates every cached load:
  # loads through a computed address unconditionally, and loads of `p' itself.
  killnodes = s: symid:
    let
      dead = b.filter
        (k:
          let
            n = getnode s s.buckets.${k};
            k0 = b.elemAt n.kids 0;
          in
          n.op.gen == "INDIR"
          && (!(ops.isaddrop (getnode s k0).op)
          || b.elemAt (getnode s k0).syms 0 == symid))
        (b.attrNames s.buckets);
    in
    s // {
      buckets = b.removeAttrs s.buckets dead;
      nodecount = s.nodecount - b.length dead;
    };

  reset = s: if s.nodecount > 0 then s // { buckets = { }; nodecount = 0; } else s // { nodecount = 0; };

  # list(): append to the forest, once. lcc's guard is `p->link == NULL', which
  # is "not already in this forest"; `linked' is that bit by another name.
  listN = s: p:
    if p == null || (getnode s p).linked then s
    else (modnode s p (n: n // { linked = true; })) // { forest = s.forest ++ [ p ]; };

  forestLast = s: if s.forest == [ ] then null else b.elemAt s.forest (b.length s.forest - 1);

  setForestSyms = s: i: symid:
    let p = forestLast s; in
    modnode s p (n: n // { syms = b.genList (j: if j == i then symid else b.elemAt n.syms j) 2; });

  unlist = s: s // { forest = b.genList (i: b.elemAt s.forest i) (b.length s.forest - 1); };

  equatelab = s: old: new:
    let s1 = sy.modsym s old (q: q // { equatedto = new; }); in
    sy.modsym s1 new (q: q // { ref = q.ref + 1.0; });

  equated = s: p:
    let q = sy.getsym s p; in
    if q.equatedto == null then p else equated s q.equatedto;

  labelnode = s0: lab:
    let
      last = forestLast s0;
      s1 =
        if last != null && (getnode s0 last).op.gen == "LABEL" then
          let f = sy.findlabel s0 lab; in
          equatelab f.s f.v (b.elemAt (getnode f.s last).syms 0)
        else
          let
            f = sy.findlabel s0 lab;
            n = newnode f.s (ops.mk "LABEL" "V") null null f.v;
          in
          listN n.s n.v;
    in
    reset s1;

  # stmt.c's addlocal, which now lives in sym.nix: simp.c's addrtree calls it
  # too, and reaching it through dag.nix from there would be a layer backwards.
  inherit (sy) addlocal;

  jump = s0: lab:
    let
      f = sy.findlabel s0 lab;
      s1 = sy.modsym f.s f.v (q: q // { ref = q.ref + 1.0; });
      a = newnode s1 (ops.sized (ops.mk "ADDRG" "P") ty.voidptype.size) null null f.v;
    in
    newnode a.s (ops.mk "JUMP" "V") a.v null null;

  # --- listnodes ---------------------------------------------------------
  listnodes = s0: tp: tlab: flab:
    if tp == null then { s = s0; v = null; }
    else if (tr.get s0 tp).node != null then { s = s0; v = (tr.get s0 tp).node; }
    else
      let
        t = tr.get s0 tp;
        g = t.op.gen;
        k0 = b.elemAt t.kids 0;
        k1 = b.elemAt t.kids 1;
        # listnodes' first two lines: the node op is the tree op plus the width
        # of the tree's own type -- except for an array, which decays.
        op = ops.sized t.op (if ty.isarray t.type then ty.voidptype.size else t.type.size);
        r = dispatch s0 tp t g k0 k1 op tlab flab;
      in
      { s = tr.setnode r.s tp r.v; inherit (r) v; };

  dispatch = s0: _tp: t: g: k0: k1: op: tlab: flab:
    if g == "AND" then
      let
        s1 = if s0.dagdepth == 0 then reset (s0 // { dagdepth = 1; }) else s0 // { dagdepth = s0.dagdepth + 1; };
      in
      if flab != 0 then
        let
          a = listnodes s1 k0 0 flab;
          c = listnodes a.s k1 0 flab;
        in
        { s = c.s // { dagdepth = c.s.dagdepth - 1; }; v = null; }
      else
        let
          gl = sy.genlabel s1 1;
          a = listnodes gl.s k0 0 gl.v;
          c = listnodes a.s k1 tlab 0;
          d = labelnode c.s gl.v;
        in
        { s = d // { dagdepth = d.dagdepth - 1; }; v = null; }
    else if g == "OR" then
      let
        s1 = if s0.dagdepth == 0 then reset (s0 // { dagdepth = 1; }) else s0 // { dagdepth = s0.dagdepth + 1; };
      in
      if tlab != 0 then
        let
          a = listnodes s1 k0 tlab 0;
          c = listnodes a.s k1 tlab 0;
        in
        { s = c.s // { dagdepth = c.s.dagdepth - 1; }; v = null; }
      else
        let
          gl = sy.genlabel s1 1;
          a = listnodes gl.s k0 gl.v 0;
          c = listnodes a.s k1 0 flab;
          d = labelnode c.s gl.v;
        in
        { s = d // { dagdepth = d.dagdepth - 1; }; v = null; }
    else if g == "NOT" then listnodes s0 k0 flab tlab
    else if g == "COND" then
      let
        q = k1;
        s1 = if t.sym != null then addlocal s0 t.sym else s0;
        gl = sy.genlabel s1 2;
        fl = gl.v;
        a = listnodes gl.s k0 0 fl;
        qt = tr.get a.s q;
        s2 = reset a.s;
        c = listnodes s2 (b.elemAt qt.kids 0) 0 0;
        # An arm that ended in a label can be merged into the join label
        # rather than jumped over -- dag.c does this twice, once per arm.
        s3 =
          let last = forestLast c.s; in
          if last != null && (getnode c.s last).op.gen == "LABEL"
          then
            let f = sy.findlabel c.s (fl + 1); in
            unlist (equatelab f.s (b.elemAt (getnode f.s last).syms 0) f.v)
          else c.s;
        j = jump s3 (fl + 1);
        s4 = listN j.s j.v;
        s5 = labelnode s4 fl;
        d = listnodes s5 (b.elemAt qt.kids 1) 0 0;
        s6 =
          let last = forestLast d.s; in
          if last != null && (getnode d.s last).op.gen == "LABEL"
          then
            let f = sy.findlabel d.s (fl + 1); in
            unlist (equatelab f.s (b.elemAt (getnode f.s last).syms 0) f.v)
          else d.s;
        s7 = labelnode s6 (fl + 1);
      in
      if t.sym != null then
        let i = tr.idtree s7 t.sym; in listnodes i.s i.v 0 0
      else { s = s7; v = null; }
    else if g == "CNST" then
      (
        if tlab != 0 || flab != 0 then
          (
            if tlab != 0 && t.value != 0 then
              let j = jump s0 tlab; in { s = listN j.s j.v; v = null; }
            else if flab != 0 && t.value == 0 then
              let j = jump s0 flab; in { s = listN j.s j.v; v = null; }
            else { s = s0; v = null; }
          )
        else
          let c = sy.constantSym s0 (ty.unqual t.type) t.value; in
          node c.s op null null c.v
      )
    else if g == "RIGHT" then
      (
        # The `*p = e' / `e++' shape: lcc lists the load itself so the store
        # cannot be reordered past it.
        # lcc's test is on the INDIR's KID, not on the INDIR itself:
        # `tp->kids[0]->kids[0] == tp->kids[1]->kids[0]'. Comparing the INDIR
        # never fires, and the load then stops being a listed root -- which
        # renumbers the whole forest from that point on.
        if k0 != null && k1 != null && tr.gen s0 k1 == "ASGN"
          && tr.gen s0 k0 == "INDIR" && tr.kid s0 k0 0 == tr.kid s0 k1 0
        then
          let
            a = listnodes s0 k0 0 0;
            s1 = listN a.s a.v;
            c = listnodes s1 k1 0 0;
          in
          { inherit (c) s; inherit (a) v; }
        else if k1 != null then
          let a = listnodes s0 k0 0 0; in listnodes a.s k1 tlab flab
        else listnodes s0 k0 tlab flab
      )
    else if g == "JUMP" then
      let
        a = listnodes s0 k0 0 0;
        n = newnode a.s (ops.mk "JUMP" "V") a.v null null;
        s1 = listN n.s n.v;
      in
      { s = reset s1; v = null; }
    else if g == "CALL" then
      let
        a = listnodes s0 k0 0 0;
        c = listnodes a.s k1 0 0;
        n = newnode c.s op a.v c.v null;
        # The callee's TYPE is what symbolic.c prints in braces, carried on a
        # symbol invented for the purpose.
        # `tp->kids[0]->type->type' is the FUNCTION type, not the return
        # type: symbolic.c prints it whole, as `{int function(int,int)}'.
        fty = ty.unqual (tr.get c.s k0).type;
        cs = sy.newsym n.s { inherit (fty) type; };
        s1 = modnode cs.s n.v (x: x // { syms = [ cs.v null ]; });
        s2 = listN s1 n.v;
        s3 = reset s2;
      in
      { s = sy.modsym s3 s3.cfunc (f: f // { ncalls = (f.ncalls or 0) + 1; }); inherit (n) v; }
    else if g == "ARG" then
      let
        a = listnodes s0 k1 0 0; # left_to_right = 1: the rest of the list first
        c = listnodes a.s k0 0 0;
        n = newnode c.s op c.v null null;
        s1 = listN n.s n.v;
        sz = sy.intconst s1 t.type.size;
        s2 = setForestSyms sz.s 0 sz.v;
        al = sy.intconst s2 t.type.align;
        s3 = setForestSyms al.s 1 al.v;
      in
      { s = s3; v = null; }
    else if b.elem g [ "EQ" "NE" "GT" "GE" "LE" "LT" ] then
      let
        a = listnodes s0 k0 0 0;
        c = listnodes a.s k1 0 0;
        # `opkind(l->op)' is the LEFT OPERAND's kind AND width, not the
        # comparison's own: a pointer compare is U4 even though the tree's
        # type is int.
        lop = (getnode c.s a.v).op;
        cmpop = kind: { gen = kind; inherit (lop) kind; inherit (lop) size; };
        flip = { EQ = "NE"; NE = "EQ"; GT = "LE"; LT = "GE"; GE = "LT"; LE = "GT"; };
        r =
          if tlab != 0 then
            let
              f = sy.findlabel c.s tlab;
              n = newnode f.s (cmpop g) a.v c.v f.v;
            in
            { s = listN n.s n.v; }
          else if flab != 0 then
            let
              f = sy.findlabel c.s flab;
              n = newnode f.s (cmpop flip.${g}) a.v c.v f.v;
            in
            { s = listN n.s n.v; }
          # dag.c asserts here. A comparison with neither label is a tree lcc
          # would never have built, and listing it would emit a node no rule
          # can select.
          else sy.refuse c.s "dag: a comparison reached listnodes with neither a true nor a false label";
        last = forestLast r.s;
        s1 =
          if last != null && b.elemAt (getnode r.s last).syms 0 != null
          then sy.modsym r.s (b.elemAt (getnode r.s last).syms 0) (q: q // { ref = q.ref + 1.0; })
          else r.s;
      in
      { s = s1; v = null; }
    else if g == "ASGN" then
      let
        a = listnodes s0 k0 0 0;
        c = listnodes a.s k1 0 0;
        n = newnode c.s op a.v c.v null;
        s1 = listN n.s n.v;
        rty = (tr.get s1 k1).type;
        sz = sy.intconst s1 rty.size;
        s2 = setForestSyms sz.s 0 sz.v;
        al = sy.intconst s2 rty.align;
        s3 = setForestSyms al.s 1 al.v;
        lsym = (tr.get s3 k0).sym;
        s4 =
          if ops.isaddrop (tr.get s3 k0).op && !(sy.getsym s3 lsym).computed
          then killnodes s3 lsym
          else reset s3;
      in
      listnodes s4 k1 0 0
    else if b.elem g [ "BOR" "BAND" "BXOR" "ADD" "SUB" "RSH" "LSH" ] then
      let
        a = listnodes s0 k0 0 0;
        c = listnodes a.s k1 0 0;
      in
      node c.s op a.v c.v null
    else if b.elem g [ "DIV" "MUL" "MOD" ] then
      let
        a = listnodes s0 k0 0 0;
        c = listnodes a.s k1 0 0;
      in
      # IR->mulops_calls is 0 for the oracle (decision-004), so these stay
      # expression nodes rather than being promoted to forest roots.
      node c.s op a.v c.v null
    else if g == "RET" then
      let
        a = listnodes s0 k0 0 0;
        n = newnode a.s op a.v null null;
      in
      { s = listN n.s n.v; v = null; }
    else if b.elem g [ "CVI" "CVU" "CVP" "CVF" ] then
      let
        a = listnodes s0 k0 0 0;
        # The SOURCE width, as a symbol. lcc puts the destination width in the
        # opcode and the source width here, so CVII4 from a char and CVII4
        # from a short are the same opcode and different instructions.
        c = sy.intconst a.s (tr.get a.s k0).type.size;
      in
      node c.s op a.v null c.v
    else if g == "BCOM" || g == "NEG" then
      let a = listnodes s0 k0 0 0; in node a.s op a.v null null
    else if g == "INDIR" then
      let
        a = listnodes s0 k0 0 0;
        kty0 = (tr.get s0 k0).type;
        kty = if ty.isptr kty0 then (ty.unqual kty0).type else kty0;
      in
      if ty.isvolatile kty then newnode a.s op a.v null null
      else node a.s op a.v null null
    else if g == "FIELD" then sy.refuse s0 "dag: bit fields are outside slice 1"
    else if g == "ADDRG" || g == "ADDRF" then
      node s0 (ops.sized t.op ty.voidptype.size) null null t.sym
    else if g == "ADDRL" then
      let s1 = if (sy.getsym s0 t.sym).generated then addlocal s0 t.sym else s0; in
      node s1 (ops.sized t.op ty.voidptype.size) null null t.sym
    else sy.refuse s0 "dag: listnodes has no rule for `${g}'";

  # --- walk --------------------------------------------------------------
  walk = s0: tp: tlab: flab:
    let
      a = listnodes s0 tp tlab flab;
      s1 =
        if a.s.forest != [ ]
        then (sy.code (a.s // { forest = [ ]; }) "Gen" { inherit (a.s) forest; }).s
        else a.s;
    in
    reset s1;

  # --- stmt.c's definelab / branch ---------------------------------------
  # Both walk BACKWARDS over the code list and DELETE items. That is the one
  # place lcc's doubly-linked list shows through; here the list is a Nix list
  # and deletion rebuilds it, which is fine because a function's code list is
  # tens of items, not thousands.
  dropAt = s: i: s // {
    code = b.genList (j: b.elemAt s.code (if j < i then j else j + 1)) (b.length s.code - 1);
  };

  # The index of the last code item at or before `from' whose kind passes.
  scanBack = s: from: pred:
    let
      go = i: if i < 0 then null else if pred (b.elemAt s.code i) then i else go (i - 1);
    in
    go from;

  definelab = s0: lab:
    let
      f = sy.findlabel s0 lab;
      s1 = walk f.s null 0 0;
      n = newnode s1 (ops.mk "LABEL" "V") null null f.v;
      c = sy.code n.s "Label" { forest = [ n.v ]; };
      # Delete every jump to this label that is immediately in front of it.
      loop = s:
        let
          i = scanBack s (b.length s.code - 2) (it: sy.kindNum it.kind > sy.kindNum "Label");
        in
        if i == null then s
        else
          let
            it = b.elemAt s.code i;
            tgt = if it.kind != "Jump" then null
            else b.elemAt (getnode s (b.head it.forest)).kids 0;
          in
          if tgt != null
            && ops.isaddrop (getnode s tgt).op
            && b.elemAt (getnode s tgt).syms 0 == f.v
          then loop (dropAt (sy.modsym s f.v (q: q // { ref = q.ref - 1.0; })) i)
          else s;
    in
    loop c.s;

  branch = s0: lab:
    let
      f = sy.findlabel s0 lab;
      s1 = walk f.s null 0 0;
      j = jump s1 lab;
      c = sy.code j.s "Label" { forest = [ j.v ]; };
      # Fold every label immediately in front of this jump into its target.
      loop = s:
        let
          i = scanBack s (b.length s.code - 2) (it: sy.kindNum it.kind >= sy.kindNum "Label");
        in
        if i == null then { inherit s; at = null; }
        else
          let it = b.elemAt s.code i; in
          if it.kind == "Label"
            && (getnode s (b.head it.forest)).op.gen == "LABEL"
            && !(labelEqual s (b.elemAt (getnode s (b.head it.forest)).syms 0) f.v)
          then loop (dropAt (equatelab s (b.elemAt (getnode s (b.head it.forest)).syms 0) f.v) i)
          else { inherit s; at = i; };
      r = loop c.s;
      s2 = r.s;
      here = if r.at == null then null else b.elemAt s2.code r.at;
    in
    if here != null && (here.kind == "Jump" || here.kind == "Switch")
    then dropAt (sy.modsym s2 f.v (q: q // { ref = q.ref - 1.0; })) (b.length s2.code - 1)
    else
      let
        n = b.length s2.code - 1;
        s3 = s2 // {
          code = b.genList (i: if i == n then (b.elemAt s2.code i) // { kind = "Jump"; } else b.elemAt s2.code i) (n + 1);
        };
      in
      if here != null && here.kind == "Label"
        && (getnode s3 (b.head here.forest)).op.gen == "LABEL"
        && labelEqual s3 (b.elemAt (getnode s3 (b.head here.forest)).syms 0) f.v
      then sy.warn s3 "source code specifies an infinite loop\n"
      else s3;

  # stmt.c's equal(): is lprime somewhere on dst's equated-to chain?
  labelEqual = s: lprime: dst:
    if dst == null then false
    else if lprime == dst then true
    else labelEqual s lprime (sy.getsym s dst).equatedto;

  # --- dag.c's fixup -----------------------------------------------------
  fixup = s0: forest:
    b.foldl'
      (s: p:
        let n = getnode s p; in
        if n.op.gen == "JUMP" then
          let k = b.elemAt n.kids 0; in
          if ops.isaddrop (getnode s k).op
          then modnode s k (x: x // { syms = [ (equated s (b.elemAt x.syms 0)) null ]; })
          else s
        else if b.elem n.op.gen [ "EQ" "GE" "GT" "LE" "LT" "NE" ] then
          modnode s p (x: x // {
            syms = [ (equated s (b.elemAt x.syms 0)) (b.elemAt x.syms 1) ];
          })
        else s)
      s0
      forest;

  # --- symbolic.c's I(gen): number the forest and order it post-order ----
  genForest = s0: forest:
    let
      visit = st: p: n:
        if p == null || (getnode st.s p).inst != 0 then st // { inherit n; }
        else
          let
            s1 = modnode st.s p (x: x // { inst = n + 1; });
            a = visit (st // { s = s1; }) (b.elemAt (getnode s1 p).kids 0) (n + 1);
            c = visit a (b.elemAt (getnode a.s p).kids 1) a.n;
          in
          c // { order = c.order ++ [ p ]; };
      start = { s = s0; order = [ ]; n = 0; };
      r = b.foldl'
        (st: p:
          let st1 = st // { s = modnode st.s p (x: x // { listed = true; }); }; in
          visit st1 p st.n)
        start
        forest;
    in
    { inherit (r) s; v = r.order; };
}
