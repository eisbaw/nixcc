# The differential's comparison logic: OUR token stream against the one a
# real cpp produced, for every file in the corpus.
#
# WHY TOKENS AND NOT TEXT. gcc and this preprocessor agree about what a
# translation unit MEANS and disagree about how it is spaced -- gcc keeps the
# column of the first token on a line, we emit one space, and neither is
# wrong. A byte diff would therefore be red on every file and would have to be
# whittled down with substitutions until it went green, which is a test that
# converges on itself. So both sides are lexed with poc/02-lexer and the
# `kind:text' streams are compared. task-013.01 criterion #4 asks for exactly
# this.
#
# THREE COMPARISONS, not one, because they fail for different reasons:
#
#   * OURS vs GCC on the cpp corpus. The differential proper.
#   * OURS vs GCC on poc/07-parser's 26 preprocessor-free translation units.
#     A preprocessor must be the IDENTITY on a file with no directives in it,
#     and these are 26 files this project already compiles and diffs against
#     lcc byte for byte. This is the half that catches a pass which quietly
#     drops or reorders ordinary C.
#   * OUR RENDERED TEXT re-lexed vs our own token stream. `render' exists so
#     that rcc and gcc can read what we produce; without this, a render that
#     pasted two tokens together or lost one would be caught only by the
#     linemarker check in frontend.sh, and only by luck.
#
# WHAT A `gcc' ENTRY IS. The driver runs `gcc -std=c89 -E -P' and hands the
# result in as a path. -P suppresses gcc's linemarkers: they are not tokens,
# and criterion #3 checks linemarkers against rcc's resynch() -- the thing
# that actually parses them -- rather than against gcc's spelling of them.
# If gcc ever emits a `#' line anyway (a #pragma passed through, say) that is
# a FAULT here rather than something quietly filtered, because a filter is
# where a real difference would go to hide.
{ cases, identity }:
let
  b = builtins;
  cpp = import ./cpp.nix;
  lexer = import ../02-lexer/lex.nix;

  # DECLARED, and checked for EQUALITY rather than as floors. A floor can be
  # spent downward in silence; poc/lib/mutant.sh makes the argument about
  # mutation counts and it is just as true of a corpus.
  declaredCases = 22;
  declaredIdentity = 26;
  # The smallest corpus file still has to produce real work. A file that
  # lexed to nothing would compare equal to another file that lexed to
  # nothing, and the diff would be green.
  minTokens = 8;

  isHashLine = l: b.match "[[:space:]]*#.*" l != null;
  textLines = s: b.filter b.isString (b.split "\n" s);

  ourTokens = c: cpp.tokensOf { src = b.readFile c.src; file = c.name; };
  ourBrief = c: lexer.brief (ourTokens c);

  # Our own rendered output, with the linemarkers taken out -- they are not
  # tokens, and the check that they are RIGHT is rcc's, in frontend.sh.
  renderedBrief = c:
    let
      text = cpp.render (cpp.preprocess { src = b.readFile c.src; file = c.name; });
      kept = b.filter (l: !(isHashLine l)) (textLines text);
    in
    lexer.brief (lexer.lex (b.concatStringsSep "\n" kept + "\n"));

  gccBrief = c:
    let
      text = b.readFile c.gcc;
      hashes = b.filter isHashLine (textLines text);
    in
    if hashes != [ ] then
      throw "HARNESS FAULT: `gcc -E -P' left a directive line in its output for ${c.name} -- `${
        b.head hashes}'. Filtering it here is where a real difference would hide, so this is a fault rather than something skipped"
    else lexer.brief (lexer.lex text);

  # The raw file lexed with no preprocessing at all. Only meaningful for the
  # identity corpus, where it must equal our output token for token.
  rawBrief = c: lexer.brief (lexer.lex (b.readFile c.src));

  showFirstDiff = have: want:
    let
      n = if b.length have < b.length want then b.length have else b.length want;
      at = b.filter (i: b.elemAt have i != b.elemAt want i) (b.genList (i: i) n);
    in
    if at != [ ] then
      let i = b.head at; in
      "token ${toString i} is `${b.elemAt have i}' and should be `${b.elemAt want i}'"
    else
      "the streams agree for ${toString n} tokens and then one is longer: ${
        toString (b.length have)} against ${toString (b.length want)}";

  compare = what: c: have: want:
    if have == want then null
    else "${c.name}: ${what} -- ${showFirstDiff have want}";

  # The FIRST failing comparison per file, not all three. They are ordered by
  # how close each is to the root: a token stream that already disagrees with
  # gcc will disagree with its own rendering too, and reporting both says the
  # same thing twice while making two different defects indistinguishable --
  # which run.sh's distinctness loop then reports as a harness problem.
  resultOf = identical: c:
    let
      ours = ourBrief c;
      bad = b.filter (x: x != null) [
        (compare "our token stream against gcc -E" c ours (gccBrief c))
        (compare "our own render, re-lexed, against our token stream" c (renderedBrief c) ours)
        (if identical then compare "our token stream against the file lexed raw" c ours (rawBrief c) else null)
      ];
      first = if bad == [ ] then [ ] else [ (b.head bad) ];
    in
    {
      inherit (c) name;
      tokens = b.length ours;
      why = first;
    };

  caseResults = map (resultOf false) cases;
  identityResults = map (resultOf true) identity;
  all = caseResults ++ identityResults;

  failed = b.concatLists (map (r: r.why) all);
  thin = b.filter (r: r.tokens < minTokens) all;
  compared = b.foldl' (a: r: a + r.tokens) 0 all;

  fault = msg: throw "HARNESS FAULT: ${msg}";
in
# The harness's own verdicts come first, so that an emptied corpus can never
# be reported as a clean differential. poc/06-constants/check.nix's ordering,
# for its reasons.
if b.length cases != declaredCases then
  fault "${toString (b.length cases)} cpp corpus files were handed in, against the ${
    toString declaredCases} this differential declares"
else if b.length identity != declaredIdentity then
  fault "${toString (b.length identity)} preprocessor-free translation units were handed in, against the ${
    toString declaredIdentity} this differential declares"
else if thin != [ ] then
  fault "these corpus files lexed to fewer than ${toString minTokens} tokens, so comparing them proves nothing: ${
    b.concatStringsSep ", " (map (r: "${r.name} (${toString r.tokens})") thin)}"
else if failed != [ ] then
  throw "the preprocessor and gcc -E disagree:\n  ${b.concatStringsSep "\n  " failed}"
else
  "${toString (b.length all)} translation units preprocessed and compared against gcc -E token for token (${
    toString (b.length cases)} with directives, ${toString (b.length identity)} without), ${
    toString compared} tokens\n"
