# The preprocessor's comparison logic, in one place so run.sh and the flake
# check cannot drift apart. Forcing this either throws with a precise message
# or returns a summary of what was actually measured.
#
# THE HARNESS IS AS MUCH ON TRIAL AS THE PREPROCESSOR. Every count reported is
# counted from work DONE, never from the size of the table that was meant to
# be walked, and a table that has shrunk or been emptied is a HARNESS FAULT
# rather than a pass. Eleven harnesses in this project have reported success
# while verifying nothing.
#
# THE GUARDS ARE ORDERED so that a HARNESS FAULT can never pre-empt a real
# diagnosis: the declared-count checks come first, then the preprocessor's own
# verdicts. poc/06-constants/check.nix says the same thing about itself and is
# where the ordering came from.
#
# WHY THE CONDITIONAL TABLE GOES THROUGH THE WHOLE PREPROCESSOR. Each case is
# run as `#if EXPR' with two arms that emit DIFFERENT identifiers, rather than
# by calling the expression evaluator directly: a table that called `evalExpr'
# would still pass if `#if' never consulted it. There is one assertion per
# case and not two -- the expected token stream is derived from the declared
# answer by the `c' constructor -- and what earns its keep is that the two
# arms cannot be made to agree.
let
  b = builtins;
  cpp = import ./cpp.nix;
  lexer = import ../02-lexer/lex.nix;
  cases = import ./cases.nix;

  # DECLARED counts, checked for EQUALITY rather than as floors. A floor with
  # slack in it can be spent downward in silence: poc/lib/mutant.sh makes the
  # argument about mutation counts, poc/06-constants demonstrated it on a case
  # table by deleting ten rows and watching the suite stay green.
  declaredExpansions = 86;
  declaredConditions = 52;
  declaredRelocations = 10;
  declaredTables = 7;

  preprocessed = src: cpp.preprocess { inherit src; file = "t.c"; };
  brief = src: lexer.brief (preprocessed src).tokens;
  show = xs: "[${b.concatStringsSep " " (map (x: "`${x}'") xs)}]";

  expansionResult = cs:
    let have = brief cs.src; in
    {
      inherit (cs) what;
      tokens = b.length have;
      bad = have != cs.expect;
      why = "${cs.what}: expected ${show cs.expect} but got ${show have}";
    };

  conditionResult = cs:
    let have = brief cs.src; in
    {
      inherit (cs) what;
      tokens = b.length have;
      bad = have != cs.expect;
      why = "${cs.what}: `#if ${cs.expr}' should be ${
        if cs.value then "TRUE" else "FALSE"} and the arm it took gives ${show have}";
    };

  # The line number of every token, which is the half of the output the
  # differential throws away -- and the rendered text, which is the half rcc
  # reads.
  relocationResult = cs:
    let
      r = preprocessed cs.src;
      have = map (t: "${toString t.line}:${t.text}") (b.filter (t: t.kind != "EOI") r.tokens);
      text = cpp.render r;
    in
    {
      inherit (cs) what;
      tokens = b.length have;
      bad = have != cs.lines || text != cs.render;
      why =
        if have != cs.lines
        then "${cs.what}: the line numbers are ${show have}, not ${show cs.lines}"
        else "${cs.what}: the rendered output is\n${text}and should be\n${cs.render}";
    };

  # `NAME(a,b)=body' for a function-like macro, `NAME=body' for an object-like
  # one, so a dropped parameter list reads as what it is rather than as a
  # silently equal body.
  showMacro = t: n:
    let m = t.${n}; in
    "${n}${if m.params == null then "" else "(${b.concatStringsSep "," m.params})"}=${
      b.concatStringsSep " " m.body}";

  tableResult = cs:
    let have = (preprocessed cs.src).macros; in
    {
      inherit (cs) what;
      tokens = b.length (b.attrNames have);
      bad = have != cs.macros;
      why = "${cs.what}: the macro table holds ${
        show (map (showMacro have) (b.attrNames have))
      } and should hold ${
        show (map (showMacro cs.macros) (b.attrNames cs.macros))}";
    };

  results =
    map expansionResult cases.expansions
    ++ map conditionResult cases.conditions
    ++ map relocationResult cases.relocations
    ++ map tableResult cases.tables;

  bad = b.filter (r: r.bad) results;
  # Counted from the work, not from the tables: a case that produced nothing
  # at all compares equal to another that produced nothing. It is "values"
  # rather than "tokens" because a macro-table case counts the entries it
  # compared, which are not tokens.
  produced = b.foldl' (a: r: a + r.tokens) 0 results;
  empty = b.filter (r: r.tokens == 0) results;

  fault = msg: throw "HARNESS FAULT: ${msg}";
in
if b.length cases.expansions != declaredExpansions then
  fault "${toString (b.length cases.expansions)} expansion cases, against the ${
    toString declaredExpansions} this harness declares"
else if b.length cases.conditions != declaredConditions then
  fault "${toString (b.length cases.conditions)} `#if' cases, against the ${
    toString declaredConditions} this harness declares"
else if b.length cases.relocations != declaredRelocations then
  fault "${toString (b.length cases.relocations)} relocation cases, against the ${
    toString declaredRelocations} this harness declares"
else if b.length cases.tables != declaredTables then
  fault "${toString (b.length cases.tables)} macro-table cases, against the ${
    toString declaredTables} this harness declares"
else if empty != [ ] then
  fault "these cases produced nothing to compare, so they would pass against any preprocessor: ${
    b.concatStringsSep ", " (map (r: r.what) empty)}"
else if bad != [ ] then
  throw "the preprocessor disagrees with ${toString (b.length bad)} of ${
    toString (b.length results)} cases:\n  ${b.concatStringsSep "\n  " (map (r: r.why) bad)}"
else
  "${toString (b.length cases.expansions)} expansion cases, ${
    toString (b.length cases.conditions)} `#if' expressions, ${
    toString (b.length cases.relocations)} line-number and linemarker cases and ${
    toString (b.length cases.tables)} macro-table cases compared, ${
    toString produced} values compared\n"
