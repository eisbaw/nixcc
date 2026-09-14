# Parser for lcc's `-target=symbolic` listing, as produced by the rcc-rv32
# wrapper (never raw rcc: decision-004).
#
# This exists so the DAG the matcher is tested against is REAL lcc output
# rather than something invented to suit the rules. run.sh regenerates every
# .sym file under ir/ from its .c and diffs it against the checked-in copy, so
# "this DAG came from lcc" is a property the suite re-proves on every run, not
# a claim in a comment.
#
# Format, from lcc/src/symbolic.c's I(emit):
#
#   * One leading space starts a new *forest* -- one call to emit(), one node
#     list, and its own node numbering. Back-references `#n` are forest-local,
#     so node identity is (forest index, n) and NOTHING may be shared across
#     forests.
#   * `n. OP [count=k] [#kid]* [sym]*`   an interior node
#   * `n' OP ...`                        a node on the forest's root list
#     (`x.listed`): a statement, or a value lcc wants computed right here.
#   * `name:`                            a label definition.
#   * For CALL nodes the syms field is the callee type in braces, e.g.
#     `{int function(int,int)}`, not a symbol.
#
# Everything outside the forests -- segment/export/global/space/defconst/... --
# is directive noise this PoC does not need, but it is matched against an
# explicit allowlist rather than skipped: an unrecognised line is a throw, so a
# format we have not seen cannot be silently dropped.
let
  b = builtins;

  lines = text: b.filter b.isString (b.split "\n" text);

  words = s: b.filter (x: b.isString x && x != "") (b.split "[ \t]+" s);

  # Directive lines we knowingly ignore. Anything else throws.
  ignoredDirectives = [
    "segment" "export" "import" "global" "space" "defconst" "defstring"
    "defaddress" "blockbeg" "blockend" "progend" "temporary" "address"
  ];

  # `k=v` in a directive line. A FIELD, not a word: symbolic.c prints
  # `type=long long int sclass=auto ...`, so the value runs to the next `k='
  # word. Returning only the first word made `long long int' read as `long',
  # which is on emit.nix's list of four-byte types -- the guard whose whole job
  # is to refuse what this PoC cannot lay out did not fire.
  isFieldStart = w: b.match "[A-Za-z_.]+=.*" w != null;
  fieldOf = ws: key:
    let
      n = b.length ws;
      idx = b.genList (i: i) n;
      at = b.filter (i: b.match "${key}=.*" (b.elemAt ws i) != null) idx;
      from = b.head at;
      later = b.filter (i: i > from && isFieldStart (b.elemAt ws i)) idx;
      upto = if later == [ ] then n else b.head later;
      word = b.elemAt ws from;
      firstWord = b.substring (b.stringLength key + 1) (b.stringLength word) word;
      restWords = b.genList (i: b.elemAt ws (from + 1 + i)) (upto - from - 1);
    in
    if at == [ ] then null
    else b.concatStringsSep " " ([ firstWord ] ++ restWords);

  toIntOr = fallback: s: if s == null then fallback else
  let m = b.match "(-?[0-9]+)" s; in
  if m == null then throw "parse: `${s}' is not an integer" else
  b.fromJSON (b.head m);

  # --- node lines ---------------------------------------------------------
  parseNode = line: raw:
    let
      m = b.match "([0-9]+)([.'])[ ](.*)" line;
    in
    if m == null then throw "parse: malformed node line `${raw}'" else
    let
      id = b.elemAt m 0;
      listed = b.elemAt m 1 == "'";
      ws = words (b.elemAt m 2);
      op = b.head ws;
      afterOp = b.tail ws;
      hasCount = afterOp != [ ] && b.match "count=[0-9]+" (b.head afterOp) != null;
      count = if hasCount then toIntOr 1 (fieldOf [ (b.head afterOp) ] "count") else 1;
      afterCount = if hasCount then b.tail afterOp else afterOp;
      kidWords = b.filter (w: b.match "#[0-9]+" w != null) afterCount;
      # Kids are always the leading `#n` words; a `#n` appearing after a sym
      # would mean the format is not what symbolic.c documents.
      leading = b.genList (i: b.elemAt afterCount i) (b.length kidWords);
    in
    if leading != kidWords then
      throw "parse: kid references are not contiguous in `${raw}'"
    else
      let
        symWords = b.genList (i: b.elemAt afterCount (b.length kidWords + i))
          (b.length afterCount - b.length kidWords);
      in
      {
        inherit id op count listed;
        kids = map (w: b.substring 1 (b.stringLength w) w) kidWords;
        # A CALL node's sym field is a type in braces, and a C type contains
        # spaces -- `{int function(int,int)}`. Rejoin it so `syms` always holds
        # operands rather than word fragments.
        syms =
          if symWords != [ ] && b.substring 0 1 (b.head symWords) == "{"
          then [ (b.concatStringsSep " " symWords) ]
          else symWords;
      };

  # --- one .sym listing ---------------------------------------------------
  # Two passes, both linear and both over the already-split line list: first
  # classify every line, then group the forest lines into forests. Nothing
  # slices the original text (decision-001: substring copies its haystack).
  classify = raw:
    let
      newForest = b.substring 0 1 raw == " ";
      line = if newForest then b.substring 1 (b.stringLength raw) raw else raw;
      ws = words line;
      head = if ws == [ ] then "" else b.head ws;
    in
    if line == "" then { kind = "blank"; }
    else if b.match "[0-9]+[.'] .*" line != null then
      { kind = "node"; inherit newForest raw; node = parseNode line raw; }
    else if b.match "[^ ]+:" line != null then
      { kind = "label"; inherit newForest raw; name = b.substring 0 (b.stringLength line - 1) line; }
    else if head == "function" then
      { kind = "function"; inherit raw; name = b.elemAt ws 1; }
    else if head == "caller" || head == "callee" || head == "local" then
      {
        kind = head;
        inherit raw;
        name = b.elemAt ws 1;
        offset = toIntOr null (fieldOf ws "offset");
        type = fieldOf ws "type";
      }
    else if b.match "maxoff=[0-9]+" line != null then
      { kind = "maxoff"; value = toIntOr 0 (fieldOf ws "maxoff"); }
    else if b.elem head ignoredDirectives then { kind = "ignored"; }
    else throw "parse: unrecognised line `${raw}'";

  # Group classified items into forests. Each `newForest` item opens one.
  # Driven by index rather than by an accumulating fold, because `acc ++ [x]`
  # is quadratic (decision-001).
  forestsOf = items:
    let
      n = b.length items;
      starts = b.filter (i: (b.elemAt items i).newForest or false) (b.genList (i: i) n);
      bound = k: if k + 1 < b.length starts then b.elemAt starts (k + 1) else n;
      slice = k:
        let
          from = b.elemAt starts k;
          upto = bound k;
          own = b.filter
            (it: it.kind == "node" || it.kind == "label")
            (b.genList (i: b.elemAt items (from + i)) (upto - from));
          nodeItems = b.filter (it: it.kind == "node") own;
          nodes = map (it: it.node) nodeItems;
          byId = b.listToAttrs (map (nd: { name = nd.id; value = nd; }) nodes);

          # `count' drives every decision about which value gets a register of
          # its own, and nothing else in the listing repeats it, so a format
          # change there would alter register allocation silently. It is lcc's
          # own reference count, so it must equal the references actually
          # present -- plus one for a listed node, which the forest's root list
          # references as well.
          # Checked before anything that reads `byId', which silently keeps one
          # of a repeated pair -- so a duplicate looks like a dangling
          # reference downstream, and that is the wrong thing to say.
          repeated = b.length (b.attrNames byId) != b.length nodes;

          refs = b.concatLists (map (nd: nd.kids) nodes);
          dangling = b.filter (k2: !(byId ? ${k2})) refs;
          countOf = id: b.length (b.filter (k2: k2 == id) refs);
          miscounted = b.filter
            (nd: nd.count != countOf nd.id && !(nd.listed && nd.count == countOf nd.id + 1))
            nodes;

          # Every kid must appear EARLIER in the node list than the node that
          # references it. symbolic.c's visit() guarantees it -- the list is a
          # post-order walk -- and both the label table and the emitter rely on
          # it: labelling is a self-referential attrset, so a forward reference
          # would not be diagnosed, it would be "infinite recursion".
          #
          # This also subsumes an unreachable-node check. A node no root walks
          # to is one nothing references, and `miscounted` above already
          # catches that: an unreferenced node that is not listed has zero
          # references and a count of at least one.
          ids = map (nd: nd.id) nodes;
          position = b.listToAttrs (b.genList
            (i: { name = b.elemAt ids i; value = i; })
            (b.length nodes));
          outOfOrder = b.filter
            (nd: b.any (k2: position.${k2} >= position.${nd.id}) nd.kids)
            nodes;
        in
        # Ordered so the most direct diagnosis wins: a repeated number is that
        # and not the dangling reference it causes; a dangling reference is
        # that and not the count discrepancy it causes.
        if repeated then
          throw "parse: forest ${toString k} repeats a node number"
        else if dangling != [ ] then
          throw "parse: a node references #${b.head dangling}, which its forest does not define"
        else if miscounted != [ ] then
          throw "parse: node #${(b.head miscounted).id} says count=${
            toString (b.head miscounted).count} but the forest references it ${
            toString (countOf (b.head miscounted).id)} time(s)"
        else if outOfOrder != [ ] then
          throw "parse: node #${(b.head outOfOrder).id} (${(b.head outOfOrder).op}) references a node that comes AFTER it in the list; the listing is not the post-order walk the label table assumes"
        else {
          index = k;
          order = map (nd: nd.id) nodes;
          inherit byId;
          # Labels are interleaved with the root nodes rather than always
          # sitting in a forest of their own -- measured: 58 forests across
          # lcc's own tst/ corpus mix the two. So the emitter is driven by this
          # positional sequence, not by `roots` and `labels` separately.
          # Tagged explicitly rather than distinguished by which attribute is
          # present: a typo in a tag is then a throw at the consumer instead of
          # quietly falling into the other branch.
          emitOrder = map
            (it: if it.kind == "label" then { kind = "label"; inherit (it) name; }
            else { kind = "root"; name = it.node.id; })
            (b.filter (it: it.kind == "label" || it.node.listed) own);
          # Every node reachable as somebody's kid, so the emitter can tell a
          # listed node that is only a statement from one whose value is used.
          usedAsKid = b.listToAttrs
            (map (k2: { name = k2; value = true; })
              (b.concatLists (map (nd: nd.kids) nodes)));
        };
    in
    b.genList slice (b.length starts);

  # --- one .sym listing ---------------------------------------------------
  # A listing holds one function per `function' line, so the item stream is cut
  # at those boundaries and each slice parsed on its own. Forests and symbols
  # belong to the function whose span they fall in.
  parseAll = text:
    let
      items = map classify (lines text);
      n = b.length items;
      heads = b.filter (i: (b.elemAt items i).kind == "function") (b.genList (i: i) n);
      spanOf = k:
        let
          from = b.elemAt heads k;
          upto = if k + 1 < b.length heads then b.elemAt heads (k + 1) else n;
        in
        b.genList (i: b.elemAt items (from + i)) (upto - from);
      one = k:
        let
          span = spanOf k;
          symsOf = kind: map
            (it: { inherit (it) name offset type; scope = kind; })
            (b.filter (it: it.kind == kind) span);
          maxoffs = b.filter (it: it.kind == "maxoff") span;
          forests = forestsOf span;
        in
        {
          inherit ((b.head span)) name;
          maxoff = if maxoffs == [ ] then 0 else (b.head maxoffs).value;
          params = symsOf "callee";
          locals = symsOf "local";
          inherit forests;
        };
    in
    b.genList one (b.length heads);

  # The PoC's own corpus is one function per file, so that a case's expected
  # assembly is the whole of what the matcher produced for it.
  parse = text:
    let fns = parseAll text; in
    if b.length fns != 1 then
      throw "parse: expected exactly one function in this listing, found ${toString (b.length fns)}"
    else b.head fns;

in
{ inherit parse parseAll; }
