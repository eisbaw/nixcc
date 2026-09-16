# The matcher's verification, in one place so that run.sh and the flake's
# `checks.matcher` cannot drift apart. Forcing this either throws with a
# precise message or returns a summary of what was actually measured.
#
# The harness is as much on trial as the matcher. This project has already
# shipped two tests that printed PASS while comparing nothing -- one because
# zip() truncated, one because nothing ever looked at the field that was
# wrong. So every count reported below is counted from work done, and a table
# that has shrunk or been emptied is a HARNESS FAULT rather than a pass.
#
# The guards are ordered so that a HARNESS FAULT can never pre-empt a real
# matcher diagnosis: the floors come first because an empty table cannot
# produce a meaningful verdict, but everything derived from the tables is
# checked as a matcher failure, and the "did we actually compare anything"
# arithmetic comes last. Among the matcher's own verdicts, WHAT it emitted is
# reported before WHY it chose that -- a cost duel is an explanation, and an
# explanation of code that is already wrong is the less useful half.
{ sources }: # { expr = ./ir/expr.sym; ... }, passed in so the flake can
# supply store paths and run.sh can supply a mutated copy
let
  b = builtins;
  parse = import ./parse.nix;
  table = import ./rules.nix;
  cases = import ./cases.nix;

  # Floors, not targets. Raise them if the tables legitimately grow.
  #
  # They live HERE, not beside the tables they guard in cases.nix, and that is
  # the point: a floor kept in the same file as its data is defeated by the
  # same one-file edit it exists to catch. An earlier version of this put the
  # last three in cases.nix and emptying every list AND zeroing every floor was
  # a single sed, after which the suite passed while printing "0 required
  # opcodes matched".
  minFunctions = 13;
  minSelections = 88;
  minDuels = 5;
  minRules = 107;
  minNodes = 590;
  minRequiredOps = 70;
  minLibcalls = 6;
  minCallRules = 10;
  minLowerings = 44;
  minForbidden = 6;
  minFollows = 2;
  minPairs = 29;
  # How many of the rule table's rows the corpus must REDUCE. Not derived from
  # the table's length: the point of this one is the edit that shrinks the
  # CORPUS and legalises the loss in `unexercisedRules', which is a single
  # change to cases.nix that every other floor here survives -- deleting the
  # `lbuf' function takes no `emitted' assertions with it, because lbuf
  # deliberately has none, so neither the assertion floor nor the instruction
  # count moves. Demonstrated in review, not imagined.
  minReduced = 99;
  # A declared reason shorter than this is not one. Here rather than beside
  # the table it guards, for the reason the block above says.
  minWhy = 40;
  # `totalAssertions' is derived from the `emitted' table rather than from a
  # list length, so it moves with the corpus rather than with one edit. It was
  # 20 while the actual was over a hundred, which is the kind of slack this
  # block exists to refuse.
  minAssertions = 152;

  fault = msg: throw "HARNESS FAULT: ${msg}";

  emitWith = tbl: name:
    let
      fn = parse.parse (b.readFile sources.${name});
      e = import ./emit.nix { table = tbl; };
    in
    (e.compile fn) // { inherit fn; };

  compiled = b.listToAttrs (map
    (c: { inherit (c) name; value = emitWith table c.name; })
    cases.functions);

  labelsOf = c: forest: (b.elemAt c.selected forest).labels;

  # --- rule table ---------------------------------------------------------
  ruleById = b.listToAttrs (map (r: { name = r.id; value = r; }) table.rules);
  templates = b.concatStringsSep "\n" (map (r: r.tmpl) table.rules);
  contains = needle: hay: b.length (b.split (b.replaceStrings [ "." "*" "+" "(" ")" "[" "]" "\\" "$" "^" "|" "?" "{" "}" ] [ "\\." "\\*" "\\+" "\\(" "\\)" "\\[" "\\]" "\\\\" "\\$" "\\^" "\\|" "\\?" "\\{" "\\}" ] needle) hay) > 1;

  forbidden = b.filter (m: contains m templates) cases.forbiddenMnemonics;

  # Which INSTRUCTION each opcode lowers to. `opCovered' below asserts that
  # SOME rule for an opcode fired and never which instruction it emits, and
  # for most of these rows no executed answer does either -- see cases.nix's
  # `lowerings' for the per-rule measurement of what the emulator can and
  # cannot see. So this is the only check standing behind them.
  #
  # The template's first TOKEN, not a substring: `lb' is a prefix of `lbu', so
  # a substring test would accept exactly the swap this exists to catch.
  firstToken = t: let m = b.match "([a-z][a-z0-9.]*)[ \t].*" t; in if m == null then "" else b.head m;
  badLowering = b.filter
    (l:
      let r = ruleById.${l.rule} or null; in
      r == null || r.op != l.op || firstToken r.tmpl != l.mnemonic)
    cases.lowerings;
  # Whether the table's own `callMarkers' recognise every rule for a CALL
  # opcode. burg.nix decides "this calls something, so the argument registers
  # are gone" by matching those markers against the EMITTED CODE, which is
  # right -- and it means a call rule whose text the markers happen not to
  # match looks to it like code that leaves a0 alone. For the rules no corpus
  # case exercises, nothing else here would notice.
  #
  # THE POPULATION IS DERIVED, not listed. A hand-written list of call rules
  # catches a row deleted from it and never a row ADDED to the table and
  # forgotten -- which is the mistake that actually happens, and which the
  # first version of this check claimed to catch and did not: a new
  # `stmt: CALLP4' emitting `jal' passed it clean. Only the `CALL.*' opcode
  # convention is shared with burg.nix, which spells the same thing `isCall';
  # the marker test is reimplemented, because a check sharing the
  # implementation would agree with it however wrong it was.
  #
  # The multiply/divide libcalls are not CALL opcodes and are covered by
  # `badLibcall' below, which asks for `call __mulsi3' and so subsumes this.
  callRules = b.filter (r: r ? op && b.match "CALL.*" r.op != null) table.rules;
  uncalled = b.filter
    (r: !(b.any (m: contains m r.tmpl) table.callMarkers))
    callRules;

  # THE I/U PAIRING, checked against the templates rather than described in
  # prose. Two rules that must agree have to emit byte-identical text; two
  # that must differ have to not. That catches drift in BOTH directions with
  # one table -- an edit that makes RSHU4 arithmetic and an edit that makes
  # ADDU4 a subtract are each one character, and each leaves a rule table that
  # still looks symmetrical (task-051).
  #
  # Deliberately a comparison of whole templates and not of mnemonics: the
  # divide and remainder libcalls both start `mv a0,%0', so a first-token test
  # would call them identical and pass a table that had pointed DIVU4 at
  # __divsi3.
  pairResults = map
    (q:
      let
        ri = ruleById.${q.i} or null;
        ru = ruleById.${q.u} or null;
      in
      q // {
        missing = if ri == null then q.i else if ru == null then q.u else null;
        broken =
          ri != null && ru != null
          && (if q.relation == "same" then ri.tmpl != ru.tmpl else ri.tmpl == ru.tmpl);
      })
    cases.pairs;
  pairMissing = b.filter (r: r.missing != null) pairResults;
  pairBad = b.filter (r: r.broken) pairResults;
  badRelation = b.filter (q: !(b.elem q.relation [ "same" "different" ])) cases.pairs;

  badLibcall = b.filter
    (l:
      let r = ruleById.${l.rule} or null; in
      r == null || r.op != l.op || !(contains "call ${l.symbol}" r.tmpl))
    cases.libcalls;

  # --- every node labels --------------------------------------------------
  # Labelling is lazy, so this is also what forces the whole DP table: a node
  # for which no nonterminal is reachable would reduce to a throw later, and
  # naming it here says which one rather than which template broke.
  nodeReports = b.concatLists (map
    (c:
      let comp = compiled.${c.name}; in
      b.concatLists (b.genList
        (i:
          let
            forest = b.elemAt comp.fn.forests i;
            labels = labelsOf comp i;
          in
          map
            (id: {
              file = c.name;
              forest = i;
              inherit id;
              op = forest.byId.${id}.op;
              nts = b.length (b.attrNames labels.${id});
            })
            forest.order)
        (b.length comp.fn.forests)))
    cases.functions);
  unlabelled = b.filter (r: r.nts == 0) nodeReports;
  opsSeen = b.listToAttrs (map (r: { name = r.op; value = true; }) nodeReports);

  # An opcode is "covered" when a node with that opcode exists in the corpus
  # AND some rule for that same opcode labels it. A rule that exists but never
  # fires does not count.
  opCovered = op:
    let
      hits = b.filter (r: r.op == op) nodeReports;
      fired = b.filter
        (r:
          let l = (labelsOf compiled.${r.file} r.forest).${r.id}; in
          b.any (nt: (l.${nt}.rule.op or null) == op) (b.attrNames l))
        hits;
    in
    { inherit op; present = hits != [ ]; fired = fired != [ ]; };
  opCoverage = map opCovered cases.requiredOps;
  opMissing = b.filter (c: !c.present) opCoverage;
  opUnmatched = b.filter (c: c.present && !c.fired) opCoverage;

  # --- selections ---------------------------------------------------------
  selectionResults = map
    (s:
      let
        l = (labelsOf compiled.${s.file} s.forest).${s.node} or null;
        got = if l == null then null else l.${s.nt} or null;
      in
      s // {
        gotRule = if got == null then "<no rule>" else got.rule.id;
        gotCost = if got == null then (-1) else got.cost;
        bad = got == null || got.rule.id != s.rule || got.cost != s.cost;
      })
    cases.selections;
  selectionBad = b.filter (r: r.bad) selectionResults;

  # --- cost duels ---------------------------------------------------------
  # Raise the winner's cost and nothing else. If the labeller were taking the
  # first matching rule rather than the cheapest, the choice would not move.
  perturb = id: penalty: table // {
    rules = map (r: if r.id == id then r // { cost = r.cost + penalty; } else r) table.rules;
  };

  duelResults = map
    (d:
      let
        base = compiled.${d.file};
        alt = emitWith (perturb d.winner d.penalty) d.file;
        baseWin = ((labelsOf base d.forest).${d.node} or { }).${d.nt} or null;
        altWin = ((labelsOf alt d.forest).${d.node} or { }).${d.nt} or null;
        baseBody = b.concatStringsSep "\n" base.bodyLines;
        altBody = b.concatStringsSep "\n" alt.bodyLines;
        say = e: if e == null then "<no rule>" else "${e.rule.id}@${toString e.cost}";
      in
      d // {
        got = say baseWin;
        gotAlt = say altWin;
        wrongWinner = baseWin == null || baseWin.rule.id != d.winner;
        notCheaper = baseWin == null || altWin == null || !(baseWin.cost < altWin.cost);
        noFlip = altWin == null || altWin.rule.id != d.loser;
        missingWinnerAsm = !(contains d.winnerAsm baseBody);
        strayLoserAsm = contains d.loserAsm baseBody;
        missingLoserAsm = !(contains d.loserAsm altBody);
      })
    cases.duels;
  duelBad = b.filter
    (r: r.wrongWinner || r.notCheaper || r.noFlip || r.missingWinnerAsm || r.strayLoserAsm || r.missingLoserAsm)
    duelResults;
  duelWhy = r:
    "${r.what} [${r.file} forest ${toString r.forest} #${r.node} ${r.nt}]: "
    + (if r.wrongWinner then "expected ${r.winner} to win, got ${r.got}"
    else if r.notCheaper then "${r.got} won but is not cheaper than ${r.gotAlt}"
    else if r.noFlip then "raising ${r.winner} by ${toString r.penalty} should have handed it to ${r.loser}, but ${r.gotAlt} won -- the choice is not being made on cost"
    else if r.missingWinnerAsm then "the emitted body does not contain `${r.winnerAsm}'"
    else if r.strayLoserAsm then "the emitted body contains `${r.loserAsm}', which belongs to the losing rule"
    else "with ${r.winner} penalised, the body still does not contain `${r.loserAsm}'");

  # --- emitted assembly ---------------------------------------------------
  emittedResults = map
    (e:
      let
        comp = compiled.${e.file};
        body = b.concatStringsSep "\n" comp.bodyLines;
      in
      e // {
        # `present` is matched against whole lines and `absent` as substrings,
        # which is what each means: "this instruction is emitted" against "this
        # text appears nowhere". Matching `present` as a substring quietly
        # accepted `mv a1,s11' for `mv a1,s1'.
        missing = b.filter (t: !(b.elem t comp.bodyLines)) e.present;
        stray = b.filter (t: contains t body) e.absent;
        got = b.length (b.filter (l: b.match "[^ \t].*:" l == null) comp.bodyLines);
        # What must be emitted IMMEDIATELY after a given label. A position, not
        # a presence: "the value is reloaded after the join" cannot be said any
        # other way, and it is the property that says a register is not being
        # assumed live across a branch target.
        misplaced = b.filter
          (f:
            let
              at = b.filter (i: b.elemAt comp.bodyLines i == f.label)
                (b.genList (i: i) (b.length comp.bodyLines));
            in
            at == [ ] || b.head at + 1 >= b.length comp.bodyLines
            || b.elemAt comp.bodyLines (b.head at + 1) != f.instruction)
          e.follows;
      })
    cases.emitted;
  emittedBad = b.filter
    (r: r.missing != [ ] || r.stray != [ ] || r.misplaced != [ ] || r.got != r.instructions)
    emittedResults;
  emittedWhy = r:
    if r.stray != [ ] then "${r.file}: the emitted body contains ${b.concatStringsSep ", " (map (t: "`${t}'") r.stray)}, which it must not"
    else if r.missing != [ ] then "${r.file}: the emitted body is missing ${b.concatStringsSep ", " (map (t: "`${t}'") r.missing)}"
    else if r.misplaced != [ ] then "${r.file}: `${(b.head r.misplaced).instruction}' must be the first instruction after `${
      (b.head r.misplaced).label}', and is not"
    else "${r.file}: the matcher emitted ${toString r.got} instructions where ${
      toString r.instructions} are expected, so it is producing different code and not just different registers";

  # --- the rule census (task-053) ------------------------------------------
  # WHICH ROWS OF THE RULE TABLE THE CORPUS ACTUALLY REACHES, computed here
  # rather than worked out by a reader.
  #
  # Everything above that names a rule -- `lowerings', `libcalls', `pairs' --
  # asserts something about that rule's TEMPLATE and nothing about whether the
  # matcher ever picks it. So a row the corpus cannot reach is pinned by a
  # table describing it and by nothing else, which is how task-051 shipped
  # five U-typed rows including `reg_rshu_reg', where `sra' for `srl' is the
  # defect that slice existed to prevent. This is the check that would have
  # said so.
  #
  # REDUCED, NOT MERELY LABELLED, and the difference is the whole value. The
  # labeller computes every nonterminal at every node whether or not the
  # reduction ever asks for one, so a rule can win a nonterminal nothing ever
  # asks for: `addr_addi' wins `addr' at the ADDI4 nodes whose kids fit it and
  # is never expanded into a single byte of assembly, because lcc types
  # address arithmetic as ADDP4 and no load or store in the corpus has an
  # ADDI4 under it. A labelling census calls that row covered; this one does
  # not.
  #
  # HOW, and it is two methods rather than one, because neither answers alone.
  #
  #   THE MARKER. The corpus is compiled a second time against a table whose
  #   every template carries its own rule id in front of it. A marker reaching
  #   the emitted body means that template was expanded there -- through a
  #   parent's `%0' for a fragment, on its own line for an instruction. One
  #   extra compile for the whole table rather than one per rule, and it
  #   cannot report a rule reduced that was not: a marker is emitted only by
  #   expanding the rule it belongs to, and `contains' escapes its needle, so
  #   one id cannot match another.
  #
  #   THE ABLATION, for every rule the marker did not find. burg.nix DISCARDS
  #   the result text of a root reduced to the start nonterminal, so a rule
  #   whose template is a fragment in statement position can be reduced and
  #   leave no marker anywhere: the marker can say "reduced" and cannot say
  #   "not reduced". When it is silent the row is taken OUT of the table and
  #   the corpus compiled again -- assembly identical to the real table's
  #   means nothing needed it. A throw counts as reduced, because burg.nix
  #   refuses only when the reduction actually asks for something no rule can
  #   produce.
  #
  # The ablation runs once per rule the marker missed, which is the number of
  # rows `unexercisedRules' declares, and only on a run where every other
  # check has already passed -- Nix's laziness puts the whole census behind
  # the verdict chain. An earlier version decided this by SHAPE instead
  # ("a fragment whose nonterminal is the start symbol"), which duplicated a
  # predicate private to burg.nix and produced a status no evidence could
  # contradict: it declared `stmt_from_reg' reduced but invisible, where the
  # ablation says the corpus emits byte-identical assembly without it.
  censusMark = id: "<census:${id}>";
  markedTable = table // {
    rules = map (r: r // { tmpl = censusMark r.id + r.tmpl; }) table.rules;
  };
  markedBody = b.concatStringsSep "\n"
    (b.concatMap (c: (emitWith markedTable c.name).bodyLines) cases.functions);
  # burg.nix decides "this emits a call" by matching the table's own
  # callMarkers against the EMITTED TEXT, and that match is unanchored, so
  # gluing a marker to the front of a template cannot remove a hit -- but it
  # could ADD one, if a rule id ended in `call' and its template began with a
  # space. No rule does. This is what says so, rather than leaving it to how
  # the ids happen to be spelled: a marked table that calls something the real
  # one does not is a census of a different program.
  markerMakesCall = b.filter
    (r: b.any (m: contains m (censusMark r.id + r.tmpl) && !(contains m r.tmpl))
      table.callMarkers)
    table.rules;

  baseAsm = map (c: compiled.${c.name}.asm) cases.functions;
  reducedWithout = id:
    let
      without = table // { rules = b.filter (r: r.id != id) table.rules; };
      probe = b.tryEval (let a = map (c: (emitWith without c.name).asm) cases.functions;
                         in b.deepSeq a a);
    in
    !probe.success || probe.value != baseAsm;

  labelledIds = b.listToAttrs (map (id: { name = id; value = true; })
    (b.concatMap
      (c:
        let comp = compiled.${c.name}; in
        b.concatLists (b.genList
          (i:
            let labels = labelsOf comp i; in
            b.concatMap
              (nid: map (nt: labels.${nid}.${nt}.rule.id) (b.attrNames labels.${nid}))
              (b.attrNames labels))
          (b.length comp.fn.forests)))
      cases.functions));

  censusStatus = r:
    if contains (censusMark r.id) markedBody || reducedWithout r.id then "reduced"
    else if labelledIds ? ${r.id} then "labelled"
    else "unreached";

  # `reduced' is NOT among these. It is a status the census hands out and not
  # one a declaration may claim: a row saying `reduced' would agree with the
  # rule's real state, so the staleness check below would stay silent, and the
  # undeclared check never looks at reduced rules -- which is a one-line way
  # to add a row that asserts nothing. Found in review, after the comment here
  # had said the table could not be padded.
  declarableStatuses = [ "labelled" "unreached" ];
  census = map (r: { inherit (r) id; status = censusStatus r; }) table.rules;
  reducedCount = b.length (b.filter (c: c.status == "reduced") census);

  declared = b.listToAttrs (map (d: { name = d.rule; value = d; }) cases.unexercisedRules);
  censusUnknown = b.filter (d: !(ruleById ? ${d.rule})) cases.unexercisedRules;
  censusBadStatus = b.filter (d: !(b.elem d.status declarableStatuses)) cases.unexercisedRules;
  # A reason has to BE one. An empty string satisfies "named in a list with
  # the reason written down" while saying nothing, and this table is the only
  # place the corpus's gaps are explained.
  censusNoWhy = b.filter (d: b.stringLength d.why < minWhy) cases.unexercisedRules;
  # Undeclared: the census found a row nothing in the corpus reduces and
  # cases.nix does not say why.
  censusUndeclared = b.filter (c: c.status != "reduced" && !(declared ? ${c.id})) census;
  # Rotted the other way: the row is in a different state from the one its
  # reason describes.
  censusStale = b.filter
    (c: declared ? ${c.id} && declared.${c.id}.status != c.status)
    census;
  # AND THE ARITHMETIC, which is what makes "every rule is accounted for" a
  # claim rather than a hope. `listToAttrs' keeps the FIRST entry for a
  # repeated name, so a second row naming an already-declared rule is
  # otherwise ignored in silence -- it sits in the file explaining something
  # while a different row governs. Counting both sides catches that, and
  # catches the summary line below quoting a total nothing ever added up.
  censusAccounted = reducedCount + b.length cases.unexercisedRules;

  # --- registers ----------------------------------------------------------
  # Every callee-saved register the body touches must be one the EMITTED
  # prologue saves and the EMITTED epilogue restores. Reading the intended save
  # list out of the frame record instead would be checking the plan rather than
  # the code: a prologue that saved one register fewer than the frame record
  # says passed that version of this check.
  regsIn = pattern: ls: b.filter (x: x != null) (map
    (l: let m = b.match pattern l; in if m == null then null else b.head m)
    ls);

  savedCheck = map
    (c:
      let
        comp = compiled.${c.name};
        touched = b.concatLists (map
          (l: b.filter (w: b.isString w && b.match "s[0-9]+" w != null) (b.split "[^a-z0-9]+" l))
          comp.bodyLines);
        saved = regsIn "\tsw (s[0-9]+),.*\\(sp\\)" comp.prologue;
        restored = regsIn "\tlw (s[0-9]+),.*\\(sp\\)" comp.epilogue;
        unsaved = b.attrNames (b.listToAttrs (map (t: { name = t; value = true; })
          (b.filter (t: t != "s0" && !(b.elem t saved)) touched)));
        lost = b.filter (t: !(b.elem t restored)) saved;
      in
      { file = c.name; inherit unsaved lost saved; touched = b.length touched; })
    cases.functions;
  savedBad = b.filter (r: r.unsaved != [ ] || r.lost != [ ]) savedCheck;
  savedWhy = r:
    if r.unsaved != [ ] then
      "${r.file} uses callee-saved register(s) ${b.concatStringsSep ", " r.unsaved} that its prologue never saves"
    else
      "${r.file} saves ${b.concatStringsSep ", " r.lost} in its prologue and never restores them in its epilogue";

  totalNodes = b.length nodeReports;
  totalInstructions = b.foldl' (a: r: a + r.got) 0 emittedResults;
  totalAssertions = b.foldl'
    (a: r: a + b.length r.present + b.length r.absent + b.length r.follows + 1) 0
    cases.emitted;
  totalFollows = b.foldl' (a: r: a + b.length r.follows) 0 cases.emitted;
in
# --- floors: an empty table cannot produce a verdict at all ---------------
if b.length cases.functions < minFunctions then
  fault "only ${toString (b.length cases.functions)} test functions, expected at least ${
    toString minFunctions} -- did cases.nix shrink?"
else if b.length table.rules < minRules then
  fault "the rule table has ${toString (b.length table.rules)} rules, fewer than the ${
    toString minRules} floor"
else if b.length cases.selections < minSelections then
  fault "only ${toString (b.length cases.selections)} labelling expectations, expected at least ${
    toString minSelections}"
else if b.length cases.duels < minDuels then
  fault "only ${toString (b.length cases.duels)} cost duels, expected at least ${toString minDuels}"
else if b.length cases.requiredOps < minRequiredOps then
  fault "cases.nix requires only ${toString (b.length cases.requiredOps)} opcodes to be covered, fewer than the ${
    toString minRequiredOps} floor -- emptying that list turns the opcode-coverage check into a no-op"
else if b.length callRules < minCallRules then
  fault "the rule table has ${toString (b.length callRules)} rules for CALL opcodes, fewer than the ${
    toString minCallRules} floor -- with none of them the check that burg.nix can still see a call is vacuous"
else if b.length cases.libcalls < minLibcalls then
  fault "cases.nix names only ${toString (b.length cases.libcalls)} libcall lowerings, fewer than the ${
    toString minLibcalls} floor"
else if b.length cases.lowerings < minLowerings then
  fault "cases.nix names only ${toString (b.length cases.lowerings)} opcode lowerings, fewer than the ${
    toString minLowerings} floor -- shortening that list stops the check that lb and lbu are told apart"
else if b.length cases.forbiddenMnemonics < minForbidden then
  fault "cases.nix forbids only ${toString (b.length cases.forbiddenMnemonics)} mnemonics, fewer than the ${
    toString minForbidden} floor -- emptying that list stops the check that RV32I has no multiplier"
else if b.length cases.pairs < minPairs then
  fault "cases.nix pairs only ${toString (b.length cases.pairs)} of the I-typed and U-typed rules, fewer than the ${
    toString minPairs} floor -- shortening that list stops the check that the two families have not drifted"
else if badRelation != [ ] then
  fault "cases.nix's pairing table says `${(b.head badRelation).relation}', which is neither `same' nor `different'; an unknown relation would be checked by nothing"
else if pairMissing != [ ] then
  fault "cases.nix's pairing table names rule `${(b.head pairMissing).missing}', which is not in the table"
else if markerMakesCall != [ ] then
  fault "the census marker in front of rule `${(b.head markerMakesCall).id}' spells one of the table's callMarkers, so the marked table burg.nix reads call-ness off is not the program the real table describes"
else if censusUnknown != [ ] then
  fault "cases.nix's unexercised-rule table names rule `${(b.head censusUnknown).rule}', which is not in the table"
else if censusBadStatus != [ ] then
  fault "cases.nix's unexercised-rule table gives `${(b.head censusBadStatus).rule}' the status `${
    (b.head censusBadStatus).status}', which is not one of ${b.concatStringsSep ", " declarableStatuses}. `reduced' is deliberately not among them: a row claiming it would agree with the rule's real state and so be checked by nothing"
else if censusNoWhy != [ ] then
  fault "cases.nix declares rule `${(b.head censusNoWhy).rule}' unexercised without writing down why -- that table is the only place the corpus's gaps are explained, so an empty reason is a silence with a row in front of it"
else if totalFollows < minFollows then
  fault "only ${toString totalFollows} after-a-label assertions, fewer than the ${
    toString minFollows} floor -- those are what pin that a register is not assumed live across a branch target"
else if totalNodes < minNodes then
  fault "the corpus DAGs hold ${toString totalNodes} nodes in total, fewer than the ${
    toString minNodes} floor -- did the .sym files come back empty?"
# --- the matcher's own verdicts -----------------------------------------
else if unlabelled != [ ] then
  throw "matcher: no rule labels ${(b.head unlabelled).op} (${(b.head unlabelled).file} forest ${
    toString (b.head unlabelled).forest} node #${(b.head unlabelled).id}); ${
    toString (b.length unlabelled)} node(s) affected"
else if opUnmatched != [ ] then
  throw "matcher: ${b.concatStringsSep ", " (map (c: c.op) opUnmatched)} appear in the corpus but no rule for those opcodes ever matched them"
else if forbidden != [ ] then
  throw "matcher: a rule template emits ${b.concatStringsSep ", " (map (m: "`${m}'") forbidden)}, which RV32I has not got (decision-003)"
else if badLowering != [ ] then
  throw "matcher: ${(b.head badLowering).op} must be lowered by rule `${(b.head badLowering).rule}' to `${
    (b.head badLowering).mnemonic}', and is not -- most of these lowerings are invisible to any executed answer, so this table is the only thing checking them (task-024)"
else if uncalled != [ ] then
  throw "matcher: rule `${(b.head uncalled).id}' is a rule for ${(b.head uncalled).op}, but none of the table's callMarkers matches what it emits -- burg.nix reads call-ness off the emitted code, so this rule would look to it like code that leaves the argument registers alone (task-025)"
else if badLibcall != [ ] then
  throw "matcher: ${(b.head badLibcall).op} must be lowered by rule `${(b.head badLibcall).rule}' to a call on ${
    (b.head badLibcall).symbol}, and is not (decision-003)"
# LAST of the table-only verdicts, on purpose. `lowerings' and `libcalls' name
# one rule and the instruction or symbol it owes; this names two rules and
# their relation. When both would fire, the specific one is the more useful
# message, so it goes first and this catches what it leaves -- the pairs no
# other table mentions at all.
else if pairBad != [ ] then
  throw "matcher: rules `${(b.head pairBad).i}' and `${(b.head pairBad).u}' must emit ${
    (b.head pairBad).relation} code and do not -- the I-typed and U-typed halves of the table have drifted (task-051)"
else if selectionBad != [ ] then
  throw "matcher: ${toString (b.length selectionBad)} of ${
    toString (b.length selectionResults)} labelling expectations failed\n  ${
    b.concatStringsSep "\n  " (map
      (r: "${r.what} [${r.file} forest ${toString r.forest} #${r.node} ${r.nt}]: expected ${
        r.rule}@${toString r.cost}, got ${r.gotRule}@${toString r.gotCost}")
      selectionBad)}"
else if emittedBad != [ ] then
  throw "matcher: ${toString (b.length emittedBad)} emitted-assembly expectation(s) failed\n  ${
    b.concatStringsSep "\n  " (map emittedWhy emittedBad)}"
else if duelBad != [ ] then
  throw "matcher: ${toString (b.length duelBad)} of ${toString (b.length duelResults)} cost duels failed\n  ${
    b.concatStringsSep "\n  " (map duelWhy duelBad)}"
else if savedBad != [ ] then
  throw "matcher: ${savedWhy (b.head savedBad)}"
# --- the corpus assumptions the above rest on ---------------------------
else if opMissing != [ ] then
  fault "${b.concatStringsSep ", " (map (c: c.op) opMissing)} is required by cases.nix but appears in none of the test DAGs, so nothing was checked for it"
else if totalInstructions == 0 then
  fault "the three cases emitted no instructions at all"
else if totalAssertions < minAssertions then
  fault "only ${toString totalAssertions} emitted-assembly assertions in total, against the ${
    toString minAssertions} floor; the `present'/`absent' lists look emptied"
# --- the census (task-053) ----------------------------------------------
# LAST, and behind the corpus assumptions rather than in front of them. Several
# of the checks above fail by making a rule stop being selected -- pricing an
# addressing mode out of the fold, dropping a conversion's width predicate,
# adding a call rule the markers do not recognise -- and each of those has a
# diagnosis that says what went wrong rather than merely that something is now
# unreached. So does `opMissing': a corpus case that went missing makes rules
# stop being reduced, and "a rule stopped being reduced" is the symptom where
# the missing opcode is the cause. This catches what none of them has anything
# to say about -- a row no corpus case can reach at all.
else if censusUndeclared != [ ] then
  throw "matcher: rule `${(b.head censusUndeclared).id}' is ${
    (b.head censusUndeclared).status} -- no case in the corpus reduces it, so its template is asserted by nothing but the tables that name it (task-053). Affected: ${
    b.concatStringsSep ", " (map (c: "${c.id} (${c.status})") censusUndeclared)}. Reach it from ir/, or declare it in cases.nix's `unexercisedRules' with the reason"
else if censusStale != [ ] then
  throw "matcher: cases.nix declares rule `${(b.head censusStale).id}' ${
    declared.${(b.head censusStale).id}.status}, and the corpus now makes it ${
    (b.head censusStale).status} -- the declaration is stale, so either the row moved or the reason written beside it has stopped being true (task-053)"
else if censusAccounted != b.length table.rules then
  fault "the census accounts for ${toString censusAccounted} rules against the ${
    toString (b.length table.rules)} in the table: ${toString reducedCount} reduced plus ${
    toString (b.length cases.unexercisedRules)} declared. A rule is declared twice, or a declaration names one the corpus already reduces"
else if reducedCount < minReduced then
  fault "the corpus reduces ${toString reducedCount} of the ${
    toString (b.length table.rules)} rules in the table, fewer than the ${
    toString minReduced} floor -- a corpus case taken away and the rules it reached declared unexercised instead passes every other check in this file"
else
  "${toString (b.length cases.functions)} functions from real lcc output: ${
    toString totalNodes} DAG nodes labelled, ${toString (b.length cases.selections)} rule/cost expectations, ${
    toString (b.length cases.duels)} cost duels each flipped by a cost change, ${
    toString totalAssertions} assertions over ${toString totalInstructions} emitted instructions, ${
    toString (b.length cases.requiredOps)} required opcodes matched, ${
    toString (b.length (b.attrNames opsSeen))} distinct opcodes seen, ${
    toString (b.length cases.pairs)} signed/unsigned rule pairs checked for drift, ${
    toString reducedCount} of ${toString (b.length table.rules)} rules reduced by the corpus and the other ${
    toString (b.length cases.unexercisedRules)} declared with a reason\n"
