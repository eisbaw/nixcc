# The lexer's comparison logic, in one place so that run.sh and the flake's
# `checks.lexer` cannot drift apart. Forcing this either throws with a precise
# message or returns a summary of what was actually measured.
#
# The harness is as much on trial as the lexer. The guards below exist because
# this project has already shipped a test that printed PASS while comparing
# nothing. So: every count reported is counted from work done, never from the
# size of the table that was meant to be walked, and a table that has shrunk or
# been emptied is a HARNESS FAULT rather than a pass.
#
# The guards are ordered so that a HARNESS FAULT can never pre-empt a real
# lexer diagnosis. A wrong lexer usually changes token counts as well as token
# kinds, and an earlier version of this file reported "the comparison is not
# elementwise" for a deleted punctuator table -- blaming itself, and throwing
# away the per-case message it had already computed.
{ sources ? [ ] }:
let
  b = builtins;
  l = import ./lex.nix;
  cases = import ./cases.nix;

  # Floors, not targets. If the tables legitimately grow, raise these.
  minCases = 60;
  minExpectedTokens = 130;
  minLineCases = 8;
  minSources = 10;

  showList = xs: b.concatStringsSep " " (map (x: "`${x}'") xs);

  # One comparison shape for both tables; only the projection differs.
  compare = project: cs:
    let
      toks = l.lex cs.src;
      got = project toks;
    in
    {
      inherit (cs) what;
      tokens = b.length got;
      bad = got != cs.expect;
      why = "${cs.what}: expected ${showList cs.expect} but got ${showList got}";
    };

  kindResults = map (compare l.brief) cases.tokens;
  lineResults = map (compare (map (t: "${toString t.line}:${t.kind}"))) cases.lines;

  # Round-trip every table case as well, free of charge: `render` is the
  # inverse of `lex`, so any byte the lexer drops shows up here first.
  roundResults = map
    (cs: { inherit (cs) what src; back = l.render (l.lex cs.src); })
    (cases.tokens ++ cases.lines);
  roundBad = b.filter (r: r.back != r.src) roundResults;

  tableBad = b.filter (r: r.bad) (kindResults ++ lineResults);
  expectedTokens = b.foldl' (a: cs: a + b.length cs.expect) 0 cases.tokens;
  comparedTokens = b.foldl' (a: r: a + r.tokens) 0 kindResults;

  # --- real sources ------------------------------------------------------
  # Round-trip is the property that catches what a token table cannot: a lost,
  # duplicated or reordered token anywhere in ten thousand lines of real C89.
  # genericClosure silently drops items with duplicate keys, so this is also
  # what would catch a key collision in the token loop.
  #
  # It is blind in one direction, though: it proves no byte moved, not that the
  # boundaries fell in the right places. A lexer that merged four tokens into
  # one would round-trip perfectly. `maxBytesPerToken` is the cheap guard for that
  # -- real C89 runs about 3.3 bytes of source per token.
  maxBytesPerToken = 4;

  # We splice backslash-newline between tokens only, not in phase 2 as ISO C
  # does (see lex.nix). That is sound exactly while no continuation in the
  # corpus joins two token characters, which is an assumption worth measuring
  # rather than believing.
  splicesInsideTokens = text:
    b.length (b.filter b.isList (b.split "[0-9A-Za-z_]\\\\\n[0-9A-Za-z_]" text));

  sourceResults = map
    (p:
      let
        text = b.readFile p;
        toks = l.lex text;
        newlines = (b.length (b.split "\n" text) - 1) / 2;
        last = b.elemAt toks (b.length toks - 1);
      in
      {
        path = toString p;
        bytes = b.stringLength text;
        tokens = b.length toks;
        splices = splicesInsideTokens text;
        roundBad = l.render toks != text;
        # Every "\n" in the file must advance the line counter exactly once,
        # whether it was skipped as trivia or consumed inside a continued
        # literal. So the line EOI reports pins the whole count.
        lineBad = last.kind != "EOI" || last.line != newlines + 1;
      })
    sources;

  sourceRoundBad = b.filter (r: r.roundBad) sourceResults;
  sourceLineBad = b.filter (r: r.lineBad) sourceResults;
  sourceSpliced = b.filter (r: r.splices > 0) sourceResults;
  sourceTokens = b.foldl' (a: r: a + r.tokens) 0 sourceResults;
  sourceBytes = b.foldl' (a: r: a + r.bytes) 0 sourceResults;

  fault = msg: throw "HARNESS FAULT: ${msg}";
in
# Guards that prove the tables were populated at all.
if b.length kindResults < minCases then
  fault "only ${toString (b.length kindResults)} token-table cases, expected at least ${
    toString minCases} -- did cases.nix shrink?"
else if expectedTokens < minExpectedTokens then
  fault "the token table expects only ${toString expectedTokens} tokens in total, fewer than the ${
    toString minExpectedTokens} floor -- were the `expect' lists emptied?"
else if b.length lineResults < minLineCases then
  fault "only ${toString (b.length lineResults)} line-number cases, expected at least ${
    toString minLineCases}"
else if b.length sources < minSources then
  fault "only ${toString (b.length sources)} source files to round-trip, expected at least ${
    toString minSources} -- did the file list come back empty?"
else if sourceBytes == 0 then
  fault "the ${toString (b.length sources)} source files contain no bytes at all"
# Then the lexer's own verdicts, so a real bug is always named as one.
else if tableBad != [ ] then
  throw "lexer: ${toString (b.length tableBad)} of ${
    toString (b.length kindResults + b.length lineResults)} table cases failed\n  ${
    b.concatStringsSep "\n  " (map (r: r.why) tableBad)}"
else if roundBad != [ ] then
  throw "lexer: round-trip produced different bytes for ${
    toString (b.length roundBad)} table case(s): ${
    b.concatStringsSep ", " (map (r: r.what) roundBad)}"
else if sourceRoundBad != [ ] then
  throw "lexer: round-trip lost bytes in ${toString (b.length sourceRoundBad)} file(s): ${
    b.concatStringsSep ", " (map (r: r.path) sourceRoundBad)}"
else if sourceLineBad != [ ] then
  throw "lexer: the last token's line does not match the newline count in ${
    toString (b.length sourceLineBad)} file(s): ${
    b.concatStringsSep ", " (map (r: r.path) sourceLineBad)}"
else if sourceTokens * maxBytesPerToken < sourceBytes then
  throw "lexer: ${toString sourceTokens} tokens for ${toString sourceBytes} bytes is over ${
    toString maxBytesPerToken} bytes per token; real C89 runs about 3.3, so tokens are being merged"
# Finally the assumption the corpus has to satisfy for the above to mean
# anything. Not a lexer failure: a signal that the corpus outgrew the lexer.
else if sourceSpliced != [ ] then
  fault "these sources splice a line inside a token, which this lexer does not implement: ${
    b.concatStringsSep ", " (map (r: r.path) sourceSpliced)}"
else if comparedTokens != expectedTokens then
  fault "compared ${toString comparedTokens} produced tokens against ${
    toString expectedTokens} expected ones; the comparison is not elementwise"
else
  "${toString (b.length kindResults)} token cases (${toString comparedTokens} tokens) and ${
    toString (b.length lineResults)} line-number cases compared, ${
    toString (b.length sourceResults)} real sources round-tripped byte for byte (${
    toString sourceBytes} bytes, ${toString sourceTokens} tokens, ${
    toString (sourceBytes / sourceTokens)} bytes per token)\n"
