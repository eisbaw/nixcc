# What the parser PoC asserts without asking lcc.
#
# The oracle diff (oracle.py) is the criterion that matters for the IR, and it
# is a separate script so that a mutation can reach it. This file carries the
# claims that are NOT differentials:
#
#   * every corpus listing is accepted by poc/03-matcher/parse.nix, which
#     re-checks node numbering, reference counts, post-order and dangling `#n'
#     from the consumer's side;
#   * the corpus between them produce exactly the declared set of opcodes;
#   * a discarded call is still a LISTED root that nothing references, which is
#     the distinction poc/05-loop leans on and which lives in the forest shape
#     rather than in any node;
#   * and the three programs of criterion #4 compile from .c and RUN, printing
#     what cases.nix independently computes.
{ cpu }:
let
  b = builtins;
  cases = import ./cases.nix;
  cc = import ./compile.nix;
  irParse = import ../03-matcher/parse.nix;
  lexer = import ../02-lexer/lex.nix;
  parser = import ./parse.nix;

  fail = msg: throw "check: ${msg}";

  # --- 1. every listing parses, and holds the functions it should ---------
  parsed = map
    (name: {
      inherit name;
      fns = irParse.parseAll (cc.listingOf (b.readFile (./c + "/${name}.c")));
    })
    cases.corpus;

  functionCount = b.foldl' (a: p: a + b.length p.fns) 0 parsed;

  # The corpus is derived from the directory and `notes' documents it; each
  # has to account for the other, or one of the two is quietly wrong. There is
  # no minimum function count here: oracle.py holds that one, over the
  # population it actually DIFFED against lcc, which is the number criterion
  # #2 is about.
  undocumented = b.filter (n: !(cases.notes ? ${n})) cases.corpus;
  phantom = b.filter (n: !(b.elem n cases.corpus)) (b.attrNames cases.notes);

  # The parser classifies tokens by `kind', and every kind it names has to be
  # one poc/02-lexer can produce. A typo in one of those lists does not fail
  # anywhere: kindOf returns the token unchanged, the case never matches, and
  # the construct becomes quietly unreachable. The lexer derives its set from
  # its own tables, so this is a real cross-check and not two copies agreeing.
  unknownKinds = b.filter (k: !(b.elem k lexer.tokenKinds))
    (parser (import ./compile.nix).self).namedKinds;

  # --- 2. the opcode population ------------------------------------------
  opsOf = fns: b.concatLists (map
    (fn: b.concatLists (map (f: map (id: f.byId.${id}.op) f.order) fn.forests))
    fns);
  seen = b.attrNames (b.listToAttrs (map (o: { name = o; value = true; })
    (b.concatLists (map (p: opsOf p.fns) parsed))));
  missing = b.filter (o: !(b.elem o seen)) cases.opcodes;
  extra = b.filter (o: !(b.elem o cases.opcodes)) seen;

  # --- 3. a discarded call is a listed root nothing references ------------
  # poc/03-matcher/parse.nix computes `usedAsKid' per forest; the distinction
  # between a call whose value is used and one whose value is thrown away is
  # not in the node, it is in whether anything has it as a kid.
  callsFns = (b.head (b.filter (p: p.name == "calls") parsed)).fns;
  callRoots = b.concatLists (map
    (fn: b.concatLists (map
      (f: map
        (id: { node = f.byId.${id}; used = f.usedAsKid ? ${id}; })
        (b.filter (id: b.match "CALL.*" f.byId.${id}.op != null) f.order))
      fn.forests))
    callsFns);
  discarded = b.filter (c: !c.used && c.node.listed) callRoots;
  usedCalls = b.filter (c: c.used) callRoots;

  # --- 4. the three programs, compiled from .c and run --------------------
  ran = map
    (p:
      let
        d = import ./demo.nix {
          inherit cpu;
          source = ./run + "/${p.name}.c";
          inherit (p) arg;
        };
      in
      p // { inherit (d) report; want = cases.expectedStdout.${p.name}; })
    cases.programs;
  wrong = b.filter (r: r.report.stdout != r.want || r.report.exitCode != 0) ran;

  lines = [
    "${toString (b.length cases.corpus)} corpus files parsed into ${
      toString functionCount} functions, every listing accepted by poc/03-matcher"
    "${toString (b.length seen)} distinct opcodes across the corpus, matching the declared set"
    "${toString (b.length discarded)} discarded call root(s) and ${
      toString (b.length usedCalls)} used call(s) in calls.c"
  ] ++ map
    (r: "${r.name}.c compiled from C by Nix and ran: ${
      b.replaceStrings [ "\n" ] [ "\\n" ] r.report.stdout} in ${
      toString r.report.steps} instructions")
    ran;
in
if b.length cases.corpus != cases.corpusCount then
  fail "the corpus holds ${toString (b.length cases.corpus)} files, against the ${
    toString cases.corpusCount} it declares"
else if b.length cases.programs != cases.programCount then
  fail "run/ holds ${toString (b.length cases.programs)} programs, against the ${
    toString cases.programCount} it declares; criterion #4's \"three programs RUN\" is what this number IS"
else if unknownKinds != [ ] then
  fail "parse.nix names the token kind(s) ${b.concatStringsSep ", " unknownKinds}, which poc/02-lexer cannot produce; a kind the lexer does not emit is a case that never fires"
else if undocumented != [ ] then
  fail "c/${b.head undocumented}.c is in the corpus and has no entry in cases.nix's `notes'; say what it is for"
else if phantom != [ ] then
  fail "cases.nix's `notes' describes `${b.head phantom}', which is not a file in c/"
else if missing != [ ] then
  fail "the corpus no longer produces ${b.concatStringsSep ", " missing}, which cases.nix declares it does"
else if extra != [ ] then
  fail "the corpus produces ${b.concatStringsSep ", " extra}, which cases.nix does not declare; add them to the list once you have looked at what emits them"
else if discarded == [ ] then
  fail "calls.c no longer has a discarded call root, so the used/unused distinction is untested"
else if usedCalls == [ ] then
  fail "calls.c no longer has a call whose value is used, so the discarded one proves nothing by contrast"
else if wrong != [ ] then
  fail "${(b.head wrong).name} printed `${
    b.replaceStrings [ "\n" ] [ "\\n" ] (b.head wrong).report.stdout}' and exited ${
    toString (b.head wrong).report.exitCode}, wanted `${
    b.replaceStrings [ "\n" ] [ "\\n" ] (b.head wrong).want}' and 0"
else b.concatStringsSep "\n" lines + "\n"
