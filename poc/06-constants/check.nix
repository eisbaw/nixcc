# The constant evaluator's comparison logic, in one place so run.sh and any
# later caller cannot drift apart. Forcing this either throws with a precise
# message or returns a summary of what was actually measured.
#
# The harness is as much on trial as the evaluator. Every count reported is
# counted from work DONE, never from the size of the table that was meant to
# be walked, and a table that has shrunk or been emptied is a HARNESS FAULT
# rather than a pass. This project has shipped seven harnesses that reported
# success while verifying nothing.
#
# The guards are ordered so that a HARNESS FAULT can never pre-empt a real
# diagnosis: the declared-count checks come first, then the evaluator's own
# verdicts. There is deliberately NOTHING after the verdicts -- two totals
# used to be compared there and review showed both were unreachable, since
# `bad == [ ]' already means every case's whole expected list was matched.
# The anti-truncation property they were meant to give comes from comparing
# whole lists per case, which is what `have != want' does.
let
  b = builtins;
  c = import ./const.nix;
  l = import ../02-lexer/lex.nix;
  cases = import ./cases.nix;

  # DECLARED counts, checked for EQUALITY rather than floors. A floor with
  # slack in it can be spent downward in silence: review demonstrated exactly
  # that on oracle.nix, deleting ten diagnosed forms and watching the diff
  # stay green against a floor with fourteen forms of slack in it. The
  # argument is poc/lib/mutant.sh's, made there about mutation counts and just
  # as true of a case table.
  declaredScalars = 51;
  declaredStrings = 14;
  declaredLexed = 3;
  declaredLexedConstants = 8;

  showInts = xs: "[${b.concatStringsSep " " (map toString xs)}]";
  showStrs = xs: b.concatStringsSep " " (map (x: "`${x}'") xs);

  # One scalar case. `warnings' defaults to none here rather than in the
  # table, so a case that forgot the field still asserts something.
  scalarResult = cs:
    let
      got = c.evalICON cs.lexeme;
      want = { inherit (cs) type value; warnings = cs.warnings or [ ]; };
      have = { inherit (got) type value warnings; };
    in
    {
      inherit (cs) what;
      bad = have != want;
      why = "${cs.what}: `${cs.lexeme}' should be ${want.type} ${toString want.value} warning ${
        showStrs want.warnings} but is ${have.type} ${toString have.value} warning ${
        showStrs have.warnings}";
    };

  stringResult = cs:
    let
      got = c.evalSCON cs.lexeme;
      want = { inherit (cs) units width; warnings = cs.warnings or [ ]; };
      have = { inherit (got) units width warnings; };
    in
    {
      inherit (cs) what;
      units = b.length got.units;
      bad = have != want;
      why = "${cs.what}: `${cs.lexeme}' should decode to width ${toString want.width} ${
        showInts want.units} warning ${showStrs want.warnings} but gives width ${
        toString have.width} ${showInts have.units} warning ${showStrs have.warnings}";
    };

  # The integration case: lex, then evaluate every constant token. This is the
  # shape task-027's parser will use, so it is the one that would catch the
  # evaluator and the lexer disagreeing about what a lexeme is.
  brief = tok:
    let r = c.evalToken tok; in
    if r ? units
    then "w${toString r.width}:${b.concatStringsSep "," (map toString r.units)}"
    else "${r.type}:${toString r.value}";

  lexedResult = cs:
    let
      toks = b.filter (t: t.kind == "ICON" || t.kind == "SCON") (l.lex cs.src);
      got = map brief toks;
    in
    {
      inherit (cs) what;
      constants = b.length got;
      bad = got != cs.expect;
      why = "${cs.what}: expected ${showStrs cs.expect} but got ${showStrs got}";
    };

  scalarResults = map scalarResult cases.scalars;
  stringResults = map stringResult cases.strings;
  lexedResults = map lexedResult cases.lexed;

  bad = b.filter (r: r.bad) (scalarResults ++ stringResults ++ lexedResults);
  # Counted from the work, for the summary line -- not guards. See the header.
  decodedUnits = b.foldl' (a: r: a + r.units) 0 stringResults;
  foundConstants = b.foldl' (a: r: a + r.constants) 0 lexedResults;
  expectedConstants = b.foldl' (a: cs: a + b.length cs.expect) 0 cases.lexed;

  # An embedded NUL is the reason string constants are unit lists rather than
  # Nix strings (decision-001), so the tables have to contain one or the whole
  # design argument goes untested.
  withNul = b.filter (cs: b.elem 0 cs.units) cases.strings;

  fault = msg: throw "HARNESS FAULT: ${msg}";
in
if b.length scalarResults != declaredScalars then
  fault "${toString (b.length scalarResults)} scalar cases, against the ${
    toString declaredScalars} this file declares -- raise the declared number with the table"
else if b.length stringResults != declaredStrings then
  fault "${toString (b.length stringResults)} string cases, against the ${
    toString declaredStrings} this file declares"
else if b.length lexedResults != declaredLexed then
  fault "${toString (b.length lexedResults)} lexed cases, against the ${
    toString declaredLexed} this file declares"
else if expectedConstants != declaredLexedConstants then
  fault "the lexed table expects ${toString expectedConstants} constants in total, against the ${
    toString declaredLexedConstants} this file declares -- were the `expect' lists emptied?"
else if withNul == [ ] then
  fault "no string case decodes to a unit list containing a NUL, so the one property that forces unit lists rather than Nix strings is untested"
else if bad != [ ] then
  throw "constants: ${toString (b.length bad)} of ${
    toString (b.length scalarResults + b.length stringResults + b.length lexedResults)} cases failed\n  ${
    b.concatStringsSep "\n  " (map (r: r.why) bad)}"
else
  "${toString (b.length scalarResults)} scalar cases, ${toString (b.length stringResults)} string cases (${
    toString decodedUnits} units decoded) and ${toString (b.length lexedResults)} lexed sources (${
    toString foundConstants} constants) compared against hand-written expectations\n"
