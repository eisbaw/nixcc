# A bottom-up rewrite matcher in the shape of lcc's lburg: dynamic-programming
# labelling followed by reduction.
#
# Nothing here knows about RISC-V. It takes a rule table (rules.nix) and a
# target's naming conventions, and it can be aimed at a different machine by
# swapping the table. That is the claim the whole PoC is testing, so the
# nonterminal names, the opcodes that cost an argument register and the
# predicate vocabulary all come out of the table rather than being written
# here -- an earlier draft hardcoded "reg", "stmt" and a list of call opcodes,
# and the list had already drifted out of step with the rules beside it.
#
# Two passes, exactly as in lburg:
#
#   LABEL   Walk the DAG bottom-up. For every node and every nonterminal,
#           record the cheapest rule that can produce that nonterminal there
#           and the total cost of doing so. A rule's cost is its own plus the
#           cost of its kids at the nonterminals the rule demands, so the
#           cheapest cover of the whole tree falls out of local choices.
#
#   REDUCE  Walk back down from the start nonterminal, following the winning
#           rule at each node, and expand its template.
#
# The Nix-specific bit worth knowing: the label table is a SELF-REFERENTIAL
# attrset built with listToAttrs. Each entry's value refers to entries for the
# node's kids, which are also in the same attrset. Nix's laziness resolves
# that in dependency order for free, so there is no fold, no `//` accumulator
# copying the table once per node (decision-001), and lookup stays O(1).
# Forests are independent -- lcc's node numbering restarts at every emit() --
# so labelling and reduction are a plain `map` over forests with no loop
# carrying state between them at all. Every other traversal over a DAG here is
# memoised the same way, because a DAG walked as if it were a tree is
# exponential in the sharing.
{ table, target }:
let
  b = builtins;

  # --- rule table validation ---------------------------------------------
  # The table is data, so it is also data that can be wrong. Everything
  # checkable about it is checked once, here, rather than surfacing as a
  # missing match or an `attribute 'cost' missing' from inside the labeller.
  # The table's own shape, before any of its rules. Reading `table.callMarkers'
  # out of a table that has not got it throws `attribute missing' from wherever
  # the first argument happens to be reduced; worse, an EMPTY callMarkers makes
  # every call invisible and silently disables the argument guard, which is the
  # same "a list emptied turns a check into a no-op" shape the rest of this PoC
  # guards against.
  tableFields = [ "start" "regNt" "nonterminals" "callMarkers" "rules" ];
  absentField = b.filter (f: !(table ? ${f})) tableFields;
  emptyField = b.filter (f: table.${f} == [ ]) [ "nonterminals" "callMarkers" "rules" ];

  nts = table.nonterminals;
  ntSet = b.listToAttrs (map (n: { name = n; value = true; }) nts);
  required = [ "id" "nt" "kids" "cost" "tmpl" ];
  incomplete = b.filter (r: b.any (f: !(r ? ${f})) required) table.rules;
  missingField = r: b.head (b.filter (f: !(r ? ${f})) required);
  badNt = b.filter
    (r: !(ntSet ? ${r.nt}) || b.any (k: !(ntSet ? ${k})) r.kids)
    table.rules;
  badChain = b.filter (r: b.length r.kids != 1) (b.filter (r: !(r ? op)) table.rules);
  producible = b.listToAttrs (map (r: { name = r.nt; value = true; }) table.rules);
  deadNt = b.filter (n: !(producible ? ${n})) nts;
  ids = map (r: r.id) table.rules;
  dupIds = b.filter (n: b.length (b.filter (i: i == n) ids) > 1) ids;
  # A negative rule cost would make the chain closure below diverge. Checking
  # it once on the table is what lets the closure run a fixed number of passes
  # per node instead of re-verifying convergence at every one of them.
  negative = b.filter (r: r.cost < 0) table.rules;
  undeclared = b.filter (n: !(ntSet ? ${n})) [ table.start table.regNt ];

  # The predicate vocabulary, declared rather than discovered. `holds' used to
  # be an if/else-if chain ending in a throw, which was total while there was
  # one predicate and stopped being total the moment there were two: a `when'
  # carrying both `range' and a typo applied the first and ignored the rest,
  # silently. Checking it on the TABLE also honours what this file says about
  # itself forty lines up -- everything checkable about the table is checked
  # here, not from inside the labeller.
  predicates = [ "range" "srcSize" ];
  # `when = null' means the same as no `when' at all -- that is what the
  # labeller's own `r.when or null' already says -- so it is not a rule with
  # zero predicates, it is a rule without one.
  withWhen = b.filter (r: (r.when or null) != null) table.rules;
  multiWhen = b.filter (r: b.length (b.attrNames r.when) != 1) withWhen;
  unknownWhen = b.filter
    (r: b.any (k: !(b.elem k predicates)) (b.attrNames r.when))
    withWhen;

  # A FRAGMENT rule -- no newline in its template -- produces its expansion as
  # the result TEXT rather than a register it wrote into. If such a rule
  # produces the REGISTER nonterminal and its text is a kid's (`%0' or `%1'),
  # every later use of this node reads whatever register the KID happened to
  # be reduced into, and the evaluation registers are reused between
  # statements: a silently clobbered value, which is the one failure mode this
  # file exists to make loud. `reg: CNSTI4 "zero"' is safe because `zero' is a
  # register that is always what it says. `reg: CVIU4(reg) "%0"' is not, which
  # is why rules.nix pays a `mv' for a conversion that changes no bits.
  isFragment = r: b.length (b.split "\n" r.tmpl) == 1;
  aliasing = b.filter
    (r: r.nt == table.regNt && isFragment r && b.match ".*%[01].*" r.tmpl != null)
    table.rules;

  opRules = b.groupBy (r: r.op) (b.filter (r: r ? op) table.rules);
  chainRules = b.filter (r: !(r ? op)) table.rules;

  ruleName = r:
    let
      pat =
        if r ? op then
          "${r.op}${if r.kids == [ ] then "" else "(${b.concatStringsSep "," r.kids})"}"
        else b.head r.kids;
    in "${r.id} = ${r.nt}: ${pat}";

  # Does this text call something, and therefore destroy the argument registers
  # and every caller-saved one? Asked of EMITTED CODE rather than of a list of
  # opcodes, so it cannot fall out of step with the rules: on a target with a
  # hardware multiplier, MULI4's template stops saying `call' and stops being a
  # call, with nothing else to edit. The markers are regular expressions.
  mentionsCall = text: b.any (m: b.length (b.split m text) > 1) table.callMarkers;

  # --- predicates ---------------------------------------------------------
  # lburg writes these as C cost expressions (`range(a, 0, 0)` in mips.md).
  # Here they stay data so the table can be printed, diffed and tested.
  holds = node: when:
    if when == null then true
    else if when ? range then
      let
        v = target.constValue node;
        lo = b.elemAt when.range 0;
        hi = b.elemAt when.range 1;
      in v != null && v >= lo && v <= hi
    # A conversion's SOURCE width. lcc puts a conversion's destination width
    # in the opcode (CVII4 converts TO a 4-byte int) and its source width in
    # the node's first symbol, so CVII4 with `1' and CVII4 with `2' are the
    # same opcode and different instructions on any target without a
    # sign-extend. That is frontend vocabulary -- lcc/src/ops.h, shared by
    # every machine description -- which is why it can live here, next to
    # `isCall' and `isArg', without this file learning anything about RISC-V.
    else if when ? srcSize then
      let m = if node.syms == [ ] then null else b.match "([0-9]+)" (b.head node.syms); in
      m != null && b.fromJSON (b.head m) == when.srcSize
    else throw "burg: internal error -- predicate `${
      b.head (b.attrNames when)}' passed the table's own validation but has no implementation here";

  # --- labelling ----------------------------------------------------------
  # `labelForest f` -> { "<node id>" = { "<nt>" = { cost; rule; }; }; }
  labelForest = forest:
    let
      labels = b.listToAttrs (map
        (id: { name = id; value = labelNode id; })
        forest.order);

      labelNode = id:
        let
          node = forest.byId.${id};
          nkids = b.length node.kids;

          # Cost of producing nonterminal `nt` at kid position i, or null if
          # that kid cannot produce it at all.
          kidCost = i: nt:
            let e = labels.${b.elemAt node.kids i}.${nt} or null; in
            if e == null then null else e.cost;

          fromOp = b.filter (c: c != null) (map
            (r:
              if b.length r.kids != nkids || !(holds node (r.when or null)) then null
              else
                let costs = b.genList (i: kidCost i (b.elemAt r.kids i)) nkids; in
                if b.any (c: c == null) costs then null
                else { inherit (r) nt; cost = r.cost + b.foldl' (a: c: a + c) 0 costs; rule = r; })
            (opRules.${node.op} or [ ]));

          keepCheaper = m: c:
            if !(m ? ${c.nt}) || c.cost < m.${c.nt}.cost then m // { ${c.nt} = c; } else m;
          cheapestPerNt = b.foldl' keepCheaper { };

          # Chain closure. Each pass rewrites what is already reachable through
          # the unit rules. As many passes as there are nonterminals suffice: a
          # chain longer than that would have to repeat a nonterminal, and with
          # no negative costs (checked on the table above) repeating one can
          # only raise the cost.
          step = m: b.foldl'
            (acc: r:
              let from = m.${b.head r.kids} or null; in
              if from == null then acc
              else keepCheaper acc { inherit (r) nt; cost = r.cost + from.cost; rule = r; })
            m
            chainRules;
        in
        b.foldl' (m: _: step m) (cheapestPerNt fromOp) (b.genList (i: i) (b.length nts));
    in
    labels;

  # --- reduction ----------------------------------------------------------
  # Registers are assigned by evaluation depth: a node reduced at depth d puts
  # its value in depthRegs[d] and gives its kids depths d, d+1, ... This is the
  # textbook tree-code assignment, NOT register allocation -- lcc does that in
  # a separate pass (gen.c's ralloc), and so will we (task-016). It is enough
  # to emit assembly that assembles and runs, and it fails loudly rather than
  # silently when it runs out.
  expand = { tmpl, kidTexts, dst, node, argReg, fnName }:
    let
      parts = b.split "%(.)" tmpl;
      piece = p:
        if b.isString p then p
        else
          let c = b.head p; in
          if c == "0" || c == "1" then
            let i = if c == "0" then 0 else 1; in
            if i >= b.length kidTexts
            then throw "burg: template `${tmpl}' uses %${c} but the rule has ${
              toString (b.length kidTexts)} kid(s)"
            else b.elemAt kidTexts i
          else if c == "c" then
            (if dst == null then throw "burg: template `${tmpl}' uses %c outside an instruction" else dst)
          else if c == "a" then target.operand node
          else if c == "A" then
            (if argReg == null then throw "burg: template `${tmpl}' uses %A outside an argument" else argReg)
          else if c == "E" then target.epilogue fnName
          else if c == "%" then "%"
          else throw "burg: template `${tmpl}' has unknown escape %${c}";
    in
    b.concatStringsSep "" (map piece parts);

  # A template with a newline in it is an instruction and gets emitted; one
  # without is a fragment whose expansion IS the result text. lcc's own
  # convention, and what makes an addressing mode fold into its parent.
  isInstruction = r: b.length (b.split "\n" r.tmpl) > 1;

  # Split an expanded instruction template into lines, dropping the trailing
  # empty piece the final newline leaves behind.
  asLines = s: b.filter (x: b.isString x && x != "") (b.split "\n" s);

  inherit (target) depthRegs cseRegs;
  depthReg = forest: node: d:
    if d < b.length depthRegs then b.elemAt depthRegs d
    else throw "burg: expression nesting needs more than ${
      toString (b.length depthRegs)} evaluation registers at ${node.op} in forest ${
      toString forest.index} -- this PoC assigns registers by depth, it does not allocate them (task-016)";

  # lcc's operator names carry their generic operator as a prefix
  # (lcc/src/ops.h): CALLI4, CALLV and CALLP4 are all calls, ARGI4 and ARGP4
  # are all arguments. That is frontend vocabulary shared by every target,
  # which is why it can live here and the target-specific "does this CALL
  # something" question above cannot.
  isCall = node: b.match "CALL.*" node.op != null;
  isArg = node: b.match "ARG.*" node.op != null;

  reduceForest = { forest, labels, fnName }:
    let
      # reduce: returns { st; code; text; }
      #   st.cse       node id -> the text its value is already available as
      #   st.nextCse   the allocation cursor: how many registers are held RIGHT
      #                NOW. Resets at a label, because the table does.
      #   st.cseHigh   how many were ever held at once. A running maximum, kept
      #                separately from the cursor precisely because the cursor
      #                is not monotone: the prologue reads this to decide which
      #                registers to save, and reading the cursor instead meant a
      #                forest that held more before a label than after it saved
      #                too few -- a clobbered callee-saved register, silently.
      #   st.depthHigh deepest evaluation register reached, for the same reason
      #
      # An attrset argument rather than seven positional ones, two of them
      # booleans: `reduce st id goal depth dst true true` said nothing about
      # which `true` was which.
      reduce = { st, id, goal, depth, dst, atOwnPosition ? false, mustHold ? false }:
        let
          node = forest.byId.${id};
          entry = labels.${id}.${goal} or null;
          inherit (entry) rule;
          instr = isInstruction rule;

          # A listed node reached as somebody's kid must already have been
          # computed at its own position in the list. Re-reducing it here would
          # duplicate whatever lcc pinned there, most often a call. Refuse.
          #
          # There are two ways to get here and they want different answers. If
          # no label has been passed, the listing really is not in the order
          # the emitter assumes -- a parser or format problem. If one has, the
          # value was dropped at that label (see the label branch below) and
          # the honest statement is that this emitter cannot prove the code
          # that computed it runs on every path reaching the join. Saying the
          # first when the second is true sends the reader to the wrong file.
          reachedOutOfOrder = !atOwnPosition && node.listed && goal == table.regNt;

          # Hold this node's value for the rest of the forest? Only the
          # register nonterminal is held: an addressing-mode fragment is free
          # to rebuild, and that is the whole reason `addr: ADDRLP4` beats
          # materialising a pointer.
          wantTemp = goal == table.regNt && !(st.cse ? ${id}) && (node.count > 1 || mustHold);
          needsReg = wantTemp && instr;
          cseReg =
            if st.nextCse >= b.length cseRegs
            then throw "burg: forest ${toString forest.index} needs more than ${
              toString (b.length cseRegs)} registers to hold common subexpressions across ${
              node.op} #${id} -- this PoC never frees one, and does not spill (task-016)"
            else b.elemAt cseRegs st.nextCse;
          # Claim the register BEFORE descending, or a nested common
          # subexpression is handed the same one.
          stDown =
            if needsReg then st // {
              nextCse = st.nextCse + 1;
              cseHigh = if st.nextCse + 1 > st.cseHigh then st.nextCse + 1 else st.cseHigh;
            } else st;
          dstDown = if needsReg then cseReg else dst;

          # Chain rule: the same node under a different nonterminal, so the
          # destination passes straight through. That is what lets `addr: reg`
          # produce the register directly where its user wants it.
          chainRes = reduce {
            st = stDown;
            inherit id depth atOwnPosition;
            goal = b.head rule.kids;
            dst = dstDown;
          };

          kidRes = b.genList
            (i:
              let prev = if i == 0 then { st = stDown; code = [ ]; } else b.elemAt kidRes (i - 1); in
              reduce {
                inherit (prev) st;
                id = b.elemAt node.kids i;
                goal = b.elemAt rule.kids i;
                depth = depth + i;
                dst = depthReg forest node (depth + i);
              })
            (b.length node.kids);
          lastKid = if kidRes == [ ] then { st = stDown; } else b.elemAt kidRes (b.length kidRes - 1);

          sub =
            if !(rule ? op) then { inherit (chainRes) st code; texts = [ chainRes.text ]; }
            else {
              inherit (lastKid) st;
              code = b.concatLists (map (r: r.code) kidRes);
              texts = map (r: r.text) kidRes;
            };

          argReg = if isArg node then target.argReg sub.st.argIdx else null;
          text = expand {
            inherit (rule) tmpl;
            kidTexts = sub.texts;
            dst = dstDown;
            inherit node argReg fnName;
          };
          result = if instr then dstDown else text;
          bumped = if argReg == null then sub.st else sub.st // { argIdx = sub.st.argIdx + 1; };
          plain = {
            st = bumped // {
              depthHigh = if depth > bumped.depthHigh then depth else bumped.depthHigh;
              cse = if wantTemp then bumped.cse // { ${id} = result; } else bumped.cse;
            };
            code = sub.code ++ (if instr then asLines text else [ ]);
            text = result;
          };
        in
        if entry == null then
          let
            # The node reported here is the one whose GOAL became unreachable,
            # and that is usually a PARENT of the node the table actually has
            # no row for: labelling is bottom-up, so a kid that produces no
            # nonterminal at all makes every ancestor unreachable too. Walk
            # down to the deepest such kid and name it, or the reader is sent
            # to a row of the table that is perfectly fine.
            #
            # This terminates for a reason that is upstream of here, not
            # because of nesting depth: parse.nix refuses a forest with a
            # dangling kid reference or a repeated node number, and a cycle
            # would already have died as "infinite recursion" inside the
            # self-referential label table during LABELLING, long before any
            # of this ran. One path down, not a fan-out, so a shared DAG
            # cannot make it exponential either.
            describe = nd: "${nd.op}${
              if nd.kids == [ ] then "" else "(${b.concatStringsSep "," (map (k: forest.byId.${k}.op) nd.kids)})"
            }";
            deepestBarren = nd:
              let below = b.filter (k: labels.${k} == { }) nd.kids; in
              if below == [ ] then nd else deepestBarren forest.byId.${b.head below};
            barren = deepestBarren node;
          in
          throw ("burg: no rule produces `${goal}' from ${describe node} in forest ${
            toString forest.index}"
          + (if barren.id == node.id then ""
          else "; the node with no rule at all is ${describe barren} (#${barren.id})"))
        else if goal == table.regNt && (st.cse ? ${id}) then
          { inherit st; code = [ ]; text = st.cse.${id}; }
        else if reachedOutOfOrder then
          throw (
            if st.clearedAt != null then
              "burg: node #${id} (${node.op}) in forest ${toString forest.index} is used after label ${
                st.clearedAt}, where its register was released because this emitter cannot prove every path to that label computed it. It is a value lcc pinned in the node list, so it cannot be recomputed either (task-016)"
            else
              "burg: node #${id} (${node.op}) is listed but reached as a kid before its own position in forest ${
                toString forest.index}; the node list is not in the order the emitter assumes")
        else plain;

      # The argument registers are numbered per call, so the counter restarts
      # once the call that consumed them has been emitted.
      resetArgs = node: st: if isCall node then st // { argIdx = 0; } else st;

      reduceRoot = st: id:
        let
          node = forest.byId.${id};
          # A listed node something else references is a value pinned at this
          # point in the list -- most often a call, whose result the next root
          # consumes. Reduce it for its value and hold it; everything else is a
          # statement.
          wantsValue = forest.usedAsKid ? ${id};
          r = reduce ({
            inherit st id;
            depth = 0;
            atOwnPosition = true;
          } // (if wantsValue
          then { goal = table.regNt; dst = b.head depthRegs; mustHold = true; }
          else { goal = table.start; dst = null; }));
        in
        # The argument registers are set up one root at a time, so an argument
        # that CALLS something while earlier arguments are already sitting in
        # a0-a7 destroys them. Both halves of that matter:
        #
        #   * `argIdx > 0', because a call clobbers only a0-a7 -- everything
        #     else in flight is in an s-register. lcc hoists a call in argument
        #     position to its own listed root, so `h(g(), a)' has finished the
        #     call and reset the counter before any ARG runs.
        #   * what this argument EMITS, not what sits under it in the DAG. In
        #     `h(a, g())' the second ARG's kid IS the call node, but it was
        #     computed at its own root and is now a register reference that
        #     emits nothing. Asking the DAG refused both of these correct
        #     programs, and told the reader argument registers had been placed
        #     when none had.
        #
        # lcc's back ends handle the real case by evaluating arguments into
        # temporaries first (task-017); refuse it rather than emit code that
        # looks right.
        if isArg node && st.argIdx > 0 && b.any mentionsCall r.code then
          throw "burg: argument #${id} in forest ${toString forest.index} emits a call, and ${
            toString st.argIdx} argument register(s) are already placed for this call (task-017)"
        else { st = resetArgs node r.st; inherit (r) code; };

      init = { cse = { }; nextCse = 0; cseHigh = 0; argIdx = 0; depthHigh = 0; clearedAt = null; };

      # Sequential scan over the forest's emit order. Self-referential genList:
      # its depth is the number of roots in ONE forest, which lcc's own corpus
      # puts in the single digits, not the length of the program. Forests carry
      # nothing between them -- node numbering restarts at each one -- so the
      # outer walk over a whole function is a plain `map`, with no long-running
      # accumulator to get wrong (decision-001).
      steps = b.genList
        (i:
          let
            prev = if i == 0 then { st = init; code = [ ]; } else b.elemAt steps (i - 1);
            item = b.elemAt forest.emitOrder i;
          in
          if item.kind == "label" then
          # A label is a branch target, and this emitter has no control-flow
          # analysis: it cannot know whether the code that filled a
          # common-subexpression register runs on every path that reaches here.
          # So the table is cleared and anything still wanted is recomputed --
          # sound, because a reload reads what the arriving path actually left
          # in memory, whereas a register might hold a value from a path that
          # was jumped over.
          #
          # This is not hypothetical. lcc emits labels INSIDE a forest (56 of
          # the 4800 forests in its own tst/ corpus), and in 35 of those places
          # a node is referenced from both sides of one. ir/cond.c is the
          # smallest C that produces it. `nextCse` resets with the table:
          # every register it was tracking is dead, because any later use now
          # re-reduces the node instead of reading it.
            if prev.st.argIdx != 0 then
              throw "burg: label ${item.name} falls between a call's arguments and the call in forest ${
                toString forest.index}, so the argument registers cannot be tracked across it"
            else {
              st = prev.st // { cse = { }; nextCse = 0; clearedAt = item.name; };
              code = [ "${target.label fnName item.name}:" ];
            }
          else
            let r = reduceRoot prev.st item.name; in
            # Force the item: a lazy state chain as long as the loop is the
            # failure mode decision-001 warns about, and it surfaces as a stack
            # overflow rather than as anything readable.
            b.deepSeq r r)
        (b.length forest.emitOrder);
      final = if steps == [ ] then { st = init; } else b.elemAt steps (b.length steps - 1);
    in
    {
      code = b.concatLists (map (s: s.code) steps);
      inherit (final) st;
    };

  selectForest = fnName: forest:
    let labels = labelForest forest; in
    (reduceForest { inherit forest labels fnName; }) // { inherit labels; };

  select = fn: map (selectForest fn.name) fn.forests;

  # What `target` must provide. Checked here rather than left to surface as
  # `attribute 'operand' missing' from inside a template expansion.
  targetApi = [ "depthRegs" "cseRegs" "argReg" "label" "epilogue" "operand" "constValue" ];
  missingApi = b.filter (k: !(target ? ${k})) targetApi;
in
if absentField != [ ] then
  throw "burg: the rule table has no `${b.head absentField}'"
else if emptyField != [ ] then
  throw "burg: the rule table's `${b.head emptyField}' is empty"
else if incomplete != [ ] then
  throw "burg: a rule for `${(b.head incomplete).nt or "?"}' is missing its `${missingField (b.head incomplete)}'"
else if dupIds != [ ] then
  throw "burg: rule id `${b.head dupIds}' is used twice"
else if badNt != [ ] then
  throw "burg: rule `${ruleName (b.head badNt)}' names a nonterminal that is not declared"
else if badChain != [ ] then
  throw "burg: chain rule `${ruleName (b.head badChain)}' must have exactly one nonterminal on the right"
else if deadNt != [ ] then
  throw "burg: nonterminal `${b.head deadNt}' is declared but no rule produces it"
else if undeclared != [ ] then
  throw "burg: the table's start or register nonterminal `${b.head undeclared}' is not declared"
else if unknownWhen != [ ] then
  throw "burg: rule `${ruleName (b.head unknownWhen)}' carries an unknown rule predicate; this matcher implements ${
    b.concatStringsSep ", " (map (p: "`${p}'") predicates)}"
else if multiWhen != [ ] then
  throw "burg: rule `${ruleName (b.head multiWhen)}' has ${
    toString (b.length (b.attrNames (b.head multiWhen).when))} predicates in one `when'; exactly one predicate is allowed, because they are not combined"
else if aliasing != [ ] then
  throw "burg: rule `${ruleName (b.head aliasing)}' produces `${table.regNt}' from a template with no instruction in it, so this node's value would be whatever register its kid was reduced into -- and the evaluation registers are reused between statements"
else if negative != [ ] then
  throw "burg: rule `${ruleName (b.head negative)}' has a negative cost, which the chain closure cannot converge on"
else if missingApi != [ ] then
  throw "burg: the target does not provide `${b.head missingApi}'"
else {
  # Only what the rest of the PoC uses. burg.nix is a two-function interface.
  inherit labelForest select;
}
