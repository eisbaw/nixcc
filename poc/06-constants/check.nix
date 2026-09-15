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
# diagnosis: the floors come first, then the evaluator's own verdicts, then
# the elementwise check that the comparison happened at all.
let
  b = builtins;
  c = import ./const.nix;
  l = import ../02-lexer/lex.nix;
  cases = import ./cases.nix;

  # Floors, not targets. If the tables legitimately grow, raise these.
  minScalars = 45;
  minStrings = 12;
  minLexed = 3;
  minLexedConstants = 8;

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
  decodedUnits = b.foldl' (a: r: a + r.units) 0 stringResults;
  expectedUnits = b.foldl' (a: cs: a + b.length cs.units) 0 cases.strings;
  foundConstants = b.foldl' (a: r: a + r.constants) 0 lexedResults;
  expectedConstants = b.foldl' (a: cs: a + b.length cs.expect) 0 cases.lexed;

  # An embedded NUL is the reason string constants are unit lists rather than
  # Nix strings (decision-001), so the tables have to contain one or the whole
  # design argument goes untested.
  withNul = b.filter (cs: b.elem 0 cs.units) cases.strings;

  fault = msg: throw "HARNESS FAULT: ${msg}";
in
if b.length scalarResults < minScalars then
  fault "only ${toString (b.length scalarResults)} scalar cases, expected at least ${
    toString minScalars} -- did cases.nix shrink?"
else if b.length stringResults < minStrings then
  fault "only ${toString (b.length stringResults)} string cases, expected at least ${
    toString minStrings}"
else if b.length lexedResults < minLexed then
  fault "only ${toString (b.length lexedResults)} lexed cases, expected at least ${
    toString minLexed}"
else if expectedConstants < minLexedConstants then
  fault "the lexed table expects only ${toString expectedConstants} constants in total, fewer than the ${
    toString minLexedConstants} floor -- were the `expect' lists emptied?"
else if withNul == [ ] then
  fault "no string case decodes to a unit list containing a NUL, so the one property that forces unit lists rather than Nix strings is untested"
else if bad != [ ] then
  throw "constants: ${toString (b.length bad)} of ${
    toString (b.length scalarResults + b.length stringResults + b.length lexedResults)} cases failed\n  ${
    b.concatStringsSep "\n  " (map (r: r.why) bad)}"
else if decodedUnits != expectedUnits then
  fault "decoded ${toString decodedUnits} string units against ${
    toString expectedUnits} expected ones; the comparison is not elementwise"
else if foundConstants != expectedConstants then
  fault "found ${toString foundConstants} constant tokens in the lexed sources against ${
    toString expectedConstants} expected ones; the comparison is not elementwise"
else
  "${toString (b.length scalarResults)} scalar cases, ${toString (b.length stringResults)} string cases (${
    toString decodedUnits} units decoded) and ${toString (b.length lexedResults)} lexed sources (${
    toString foundConstants} constants) compared against hand-written expectations\n"
