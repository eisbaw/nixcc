# lcc/src/symbolic.c: the `-target=symbolic' listing, byte for byte.
#
# This is the half of the port that the oracle diff actually compares, so it is
# written against symbolic.c's print statements rather than against the .sym
# files under poc/03-matcher/ir/ -- reading the format off examples is how you
# get `count=1' printed (symbolic.c prints it only when count > 1) or the
# leading space wrong (emit() prints ONE space per forest, not per line).
#
# Also here: dag.c's gencode() and emitcode(), because they are the two passes
# that turn the code list into this text and neither has any other caller.
# gencode assigns frame offsets and numbers the forests; emitcode prints them.
# That split is why every `blockbeg'/`local'/`blockend' line in a listing comes
# out BEFORE every node line, which reading the .sym files would suggest was an
# accident of the examples.
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
in
rec {
  # Output accumulates in a per-function BUFFER and is moved into `out' as one
  # chunk when the function is done. `out ++ [ line ]' copies the whole list on
  # every line, which is decision-001's quadratic accumulator wearing a
  # different hat: it cost 67 MB of churn on a 1700-line translation unit.
  # `buf' is tens of lines long, so appending to it is free, and `out' is a
  # list of chunks that listingOf concatenates once.
  emit = s: line: s // { buf = s.buf ++ [ line ]; };

  flush = s: s // { out = s.out ++ [ s.buf ]; buf = [ ]; };

  roundup = x: n: if n <= 1 then x else ((x + n - 1) / n) * n;

  # c.h's `enum { CODE = 1, BSS, DATA, LIT }', and symbolic.c's names for them.
  segName = { "1" = "text"; "2" = "bss"; "3" = "data"; "4" = "lit"; };

  swtoseg = s: seg:
    let
      name = segName.${toString seg} or (throw "listing: there is no segment ${toString seg}");
    in
    if s.curseg == seg then s
    else (emit s "segment ${name}") // { curseg = seg; };

  # symbolic.c's I(address). The generated symbol is RENAMED here, to the
  # addressing expression it stands for -- `msg+8' -- and that name is what
  # ends up in the node line and in the assembly, so poc/04-assembler is what
  # finally resolves the displacement (task-023).
  #
  # lcc's format string is `"%s%s%D"' with the `+' supplied only when n > 0, so
  # a NEGATIVE displacement comes out as `msg-4' from %D's own sign and a ZERO
  # one would come out as `msg0'. Zero never arrives: simp.c's identity rule
  # removes `p + 0' before addrtree can be reached.
  address = s0: q: p: n:
    let
      nm = "${(sy.getsym s0 p).name}${if n > 0 then "+" else ""}${toString n}";
      s1 = sy.modsym s0 q (x: x // { name = nm; });
    in
    emit s1 "address ${symbolText s1 q}";

  export = s: p: emit s "export ${(sy.getsym s p).name}";
  importSym = s: p: emit s "import ${(sy.getsym s p).name}";
  progend = s: emit s "progend";

  # symbolic.c's emitSymbol: name, then one `field=value' per attribute, each
  # preceded by a space. `offset' appears only for PARAM-or-deeper non-statics,
  # and `flags' is a `|'-joined list that prints `0' when empty.
  symbolText = s: p:
    let
      q = sy.getsym s p;
      scope =
        if q.scope == sy.CONSTANTS then "CONSTANTS"
        else if q.scope == sy.LABELS then "LABELS"
        else if q.scope == sy.GLOBAL then "GLOBAL"
        else if q.scope == sy.PARAM then "PARAM"
        else if q.scope == sy.LOCAL then "LOCAL"
        else if q.scope > sy.LOCAL then "LOCAL+${toString (q.scope - sy.LOCAL)}"
        else toString q.scope;
      flagNames = b.filter (x: x != null) [
        (if q.structarg then "structarg" else null)
        (if q.addressed then "addressed" else null)
        (if q.computed then "computed" else null)
        (if q.temporary then "temporary" else null)
        (if q.generated then "generated" else null)
      ];
      flags = if flagNames == [ ] then "0" else b.concatStringsSep "|" flagNames;
      offset = if q.scope >= sy.PARAM && q.sclass != sy.sclasses.static then " offset=${toString q.offset}" else "";
    in
    "${q.name} type=${ty.outtype q.type} sclass=${q.sclass} scope=${scope}"
    + " flags=${flags}${offset} ref=${toString (q.ref + 0.0)}";

  # --- the node lines ----------------------------------------------------
  nodeLine = s: p:
    let
      n = dag.getnode s p;
      head = "${toString n.inst}${if n.listed then "'" else "."} ${ops.opname n.op}";
      cnt = if n.count > 1 then " count=${toString n.count}" else "";
      kids = b.concatStringsSep ""
        (map (k: " #${toString (dag.getnode s k).inst}") (b.filter (k: k != null) n.kids));
      syms =
        if n.op.gen == "CALL" && b.elemAt n.syms 0 != null
          && (sy.getsym s (b.elemAt n.syms 0)).type != null
        then " {${ty.outtype (sy.getsym s (b.elemAt n.syms 0)).type}}"
        else b.concatStringsSep ""
          (map (x: " ${(sy.getsym s x).name}") (b.filter (x: x != null) n.syms));
    in
    if n.op.gen == "LABEL" then "${(sy.getsym s (b.elemAt n.syms 0)).name}:"
    else head + cnt + kids + syms;

  # emit(): one leading space for the whole forest, then one line per node.
  forestLines = s: order:
    b.genList (i: (if i == 0 then " " else "") + nodeLine s (b.elemAt order i)) (b.length order);

  # --- gencode -----------------------------------------------------------
  # Walks the code list twice over, as dag.c does: this pass assigns frame
  # offsets, prints the block directives and hands each forest to I(gen) for
  # numbering; emitcode below prints what I(gen) produced.
  localLine = st: p:
    let
      q = sy.getsym st.s p;
      off = roundup st.off q.type.align;
      s1 = sy.modsym st.s p (x: x // { offset = off; });
    in
    st // {
      s = emit s1 "${if q.temporary then "temporary" else "local"} ${symbolText s1 p}";
      off = off + q.type.size;
    };

  gencode = st0: callers: callees:
    let
      # assignargs: a parameter whose callee symbol differs from its caller
      # symbol -- in storage class or in type -- is copied on entry. That copy
      # is SPLICED IN after the first code item, which is the Blockbeg, so it
      # becomes the function's first forest.
      argcopies = b.foldl'
        (acc: i:
          let
            p = b.elemAt callees i;
            q = b.elemAt callers i;
            ps = sy.getsym acc.s p;
            qs = sy.getsym acc.s q;
          in
          if ps.sclass != qs.sclass || ps.type != qs.type then
            let
              idt = tr.idtree (acc.s // { code = [ ]; }) q;
              asg = tr.asgn idt.s p idt.v;
              w = dag.walk asg.s asg.v 0 0;
            in
            { s = w // { inherit (acc.s) code; }; items = acc.items ++ w.code; }
          else acc)
        { inherit (st0) s; items = [ ]; }
        (b.genList (i: i) (b.length callees));
      spliced =
        if argcopies.items == [ ] then argcopies.s
        else argcopies.s // {
          code = [ (b.head argcopies.s.code) ] ++ argcopies.items
            ++ b.genList (i: b.elemAt argcopies.s.code (i + 1)) (b.length argcopies.s.code - 1);
        };
      step = acc: cp:
        if cp.kind == "Blockbeg" then
          let
            a = acc // { s = emit acc.s "blockbeg off=${toString acc.off}"; saved = acc.saved ++ [ acc.off ]; };
            withLocals = b.foldl'
              (st: p: if (sy.getsym st.s p).ref != 0.0 then localLine st p else st)
              a
              cp.locals;
          in
          withLocals
        else if cp.kind == "Blockend" then
          let
            mx = if acc.off > acc.maxoff then acc.off else acc.maxoff;
            n = b.length acc.saved;
          in
          acc // {
            s = emit acc.s "blockend off=${toString acc.off}";
            maxoff = mx;
            off = b.elemAt acc.saved (n - 1);
            saved = b.genList (i: b.elemAt acc.saved i) (n - 1);
          }
        else if cp.kind == "Local" then localLine acc cp.var
        # A base on the FRAME cannot be named when simp.c's addrtree runs,
        # because the frame is laid out here. So it arrives as a code item and
        # is named in code order, which is why `address buf+3' sits between two
        # `blockend' lines rather than above the function like `address msg+8'.
        else if cp.kind == "Address" then
          acc // { s = address acc.s cp.sym cp.base cp.offset; }
        else if cp.kind == "Gen" || cp.kind == "Jump" || cp.kind == "Label" then
          let
            s1 = dag.fixup acc.s cp.forest;
            g = dag.genForest s1 cp.forest;
          in
          acc // { inherit (g) s; gens = acc.gens ++ [ g.v ]; }
        # sym.kindOrder declares ten kinds and gencode handles five. The two
        # below carry nothing this slice emits; anything else is a hole, and a
        # hole that fell through to `acc' would drop a whole code item in
        # silence.
        else if cp.kind == "Defpoint" || cp.kind == "Start" then acc
        else throw "listing: gencode has no rule for a `${cp.kind}' code item";
      r = b.foldl' step
        { s = spliced; off = 0; maxoff = 0; saved = [ ]; gens = [ ]; }
        spliced.code;
    in
    r;

  emitcode = s: gens:
    b.foldl' (st: order: emitAll st order) s gens;

  emitAll = s: order:
    if order == [ ] then s
    else s // { buf = s.buf ++ forestLines s order; };

  # --- I(function) -------------------------------------------------------
  emitFunction = s0: f: callers: callees:
    let
      # Parameter offsets, assigned before anything is printed.
      place = acc: i:
        let
          q = sy.getsym acc.s (b.elemAt callers i);
          off = roundup acc.off q.type.align;
          s1 = sy.modsym acc.s (b.elemAt callers i) (x: x // { offset = off; });
          s2 = sy.modsym s1 (b.elemAt callees i) (x: x // { offset = off; });
        in
        { s = s2; off = off + q.type.size; };
      placed = b.foldl' place { s = s0; off = 0; } (b.genList (i: i) (b.length callers));
      s1 = emit placed.s "function ${symbolText placed.s f} ncalls=${
        toString (sy.getsym placed.s f).ncalls}";
      s2 = b.foldl' (s: p: emit s "caller ${symbolText s p}") s1 callers;
      s3 = b.foldl' (s: p: emit s "callee ${symbolText s p}") s2 callees;
      g = gencode { s = s3; } callers callees;
      s4 = emitcode g.s g.gens;
    in
    flush (emit s4 "maxoff=${toString g.maxoff}");

  # --- decl.c's finalize() ------------------------------------------------
  # `foreach' walks a table's `all' list, which install() PUSHES onto, so the
  # traversal is reverse installation order. That decides the order of the
  # `import' lines, so it is reproduced rather than approximated.
  finalize = s0:
    let
      rev = xs: b.genList (i: b.elemAt xs (b.length xs - 1 - i)) (b.length xs);
      s1 = b.foldl' importSym s0 (rev s0.externalOrder);
      s2 = b.foldl' doglobal s1 (rev s0.globalOrder);
      s3 = b.foldl' doconst s2 (rev s0.constOrder);
    in
    flush (progend s3);

  # decl.c's defglobal(): pick the segment, export it unless it is static, and
  # announce it. Only doconst uses it in this slice; slice 3's globals are the
  # other caller (task-029).
  defglobal = s: p: seg:
    let
      s1 = swtoseg s seg;
      s2 = if (sy.getsym s1 p).sclass != sy.sclasses.static then export s1 p else s1;
    in
    emit s2 "global ${symbolText s2 p}";

  # decl.c's doconst(). Every constant is walked and only the ones that were
  # given a location -- string literals -- lay anything down. An integer
  # constant is interned in the same table and has no `loc', which is why this
  # is a filter rather than a separate list.
  doconst = s: p:
    let q = sy.getsym s p; in
    if q.loc == null then s
    else
      let
        s1 = defglobal s q.loc 4; # LIT
        lt = (sy.getsym s1 q.loc).type;
      in
      if ty.isarray lt && (ty.unqual lt).type == ty.widechar
      then b.foldl' (st: u: emit st "defconst unsigned.${
        toString ty.widechar.size} ${toString u}") s1 q.value
      else if ty.isarray lt then emit s1 "defstring \"${defstringText q.value}\""
      else sy.refuse s1 "listing: a non-array constant was given a location, and only string literals get one";

  # symbolic.c's emitString. A byte is printed as itself when it is printable
  # ASCII, backslash-escaped when it is `"' or `\', and as a THREE-DIGIT OCTAL
  # escape otherwise -- lcc's `\%d%d%d' over the three bit fields, which for a
  # byte above 127 goes through a signed `char' and still comes out as that
  # byte's octal, because the masks put it back. `\000' is therefore what a NUL
  # looks like here, and a NUL is exactly the byte decision-001 says a Nix
  # string cannot hold, which is why the value this reads is a byte LIST.
  defstringText = units:
    b.concatStringsSep "" (map
      (u:
        if u == 34 || u == 92 then "\\" + self.const.asciiChar u
        else if u >= 32 && u < 127 then self.const.asciiChar u
        else "\\${toString (b.bitAnd (u / 64) 3)}${
          toString (b.bitAnd (u / 8) 7)}${toString (b.bitAnd u 7)}")
      units);

  doglobal = s: p:
    let q = sy.getsym s p; in
    if !q.defined && (q.sclass == sy.sclasses.extern || (ty.isfunc q.type && q.sclass == sy.sclasses.auto))
    then importSym s p
    else if !q.defined && !(ty.isfunc q.type) && (q.sclass == sy.sclasses.auto || q.sclass == sy.sclasses.static)
    then sy.refuse s "listing: tentative global `${q.name}' needs slice 3 (task-029)"
    else s;
}
