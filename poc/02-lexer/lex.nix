# A C89 lexer written in the Nix expression language.
#
# It reproduces lcc's token set (lcc/src/token.h, lcc/src/lex.c), not lcc's
# code: lcc's gettok is an imperative single-pass scanner over a refilled
# buffer, which has no Nix equivalent. What is ported is the token set and the
# lexical rules; the loop shape is dictated by the evaluator.
#
# Shape, and why (all figures measured, see decision-001):
#
#   * The token loop is `builtins.genericClosure`, not `foldl'`. A lexer is a
#     data-dependent loop that must EMIT one value per step, and Nix has no
#     other way to do that in linear time at constant stack depth: `foldl'`
#     carries a scalar accumulator and cannot emit, `acc ++ [x]` is quadratic,
#     and a self-referential `genList` builds a thunk chain as deep as the
#     token count. `genericClosure` is an iterative worklist inside the
#     evaluator: 0.07/0.11/0.18/0.35/0.49 s at 25k/50k/100k/200k/400k steps.
#
#   * Laziness is the other way this dies. genericClosure forces only `key`, and
#     `foldl'` forces its accumulator only to weak head normal form, so a field
#     left lazy across a long loop is a thunk chain as deep as the loop -- and
#     that is "stack overflow (possible infinite recursion)", not a slowdown.
#     Measured both ways: a synthetic genericClosure carrying one lazy field
#     overflows at 100000 steps, and dropping the `deepSeq` inside `runUntil`
#     below makes a 1 MB block comment overflow. The item returned by the
#     operator is deepSeq'd too. Its fields do currently get forced anyway,
#     transitively through `key`, but that is a property of today's field graph
#     and not something the next person should have to re-derive.
#
#   * Lexemes are cut out of the character LIST with `concatStringsSep`, never
#     out of the source STRING with `builtins.substring`. `substring` copies
#     its haystack, so one slice per token is quadratic in file size: cutting a
#     2.2 MB file into 4-character pieces costs 22.68 s with `substring` and
#     2.13 s with `concatStringsSep`.
#
#   * The only inner loop is `runUntil`: a step function driven by `foldl'`
#     over windows that double in size. Its recursion depth is O(log run
#     length) -- 20 levels for a 1 MB comment -- not O(run length), so no
#     traversal here grows its depth with the input.
#
# Deviations from lcc, all deliberate:
#
#   * lcc has NO compound-assignment tokens. It lexes `<<=` as LSHIFT then '='
#     and its parser disambiguates by peeking at the raw next character
#     (lcc/src/expr.c: `while (prec[t] == k1 && *cp != '=')`). We match lcc, and
#     each token records the trivia that preceded it, so the parser can make
#     the same peek by testing `ws == ""` -- no second copy of the information.
#
#   * lcc rejects `//` comments and `#`, because lcc is fed preprocessed input.
#     We lex raw C source, so `//` is a comment, a backslash-newline pair is
#     trivia (line splicing, restricted to between tokens), and `#` is a
#     one-character punctuator for a future preprocessor to consume.
#
#   * lcc calls nextline() on '\r'; we class '\r' as blank and count lines on
#     '\n' only. Identical on LF files, saner on CRLF ones.
#
#   * Character constants come back as ICON, as in lcc. Whether an ICON is a
#     character constant is derivable from its text, so it is not also stored.
#
#   * lcc's scon() CONCATENATES adjacent string literals and returns one SCON,
#     wide and narrow alike. We emit one token per literal and leave joining to
#     the parser, which is where the standard puts it (phase 6) and where the
#     wide/narrow rule is easier to state.
#
#   * Splicing is between tokens, not ISO C's phase 2 (task-008), and the
#     three places where that distinction is VISIBLE are all refused rather
#     than lexed differently, because each of them would otherwise compile
#     something the standard does not say: a continuation joining two token
#     characters (flagged as `glue` and refused by poc/08-cpp), one ending a
#     `//` comment (which would compile a line the standard discards), and
#     one inside a string or character literal (which would put a newline in
#     the literal where phase 2 removes it). What remains -- a continuation
#     between two tokens, or inside a block comment -- reads the same either
#     way, which is why it is the only case that is simply allowed.
#
#   * Trigraphs are not translated. They are phase 1, lcc does not do them
#     either, and nothing in the corpora uses them.
#
# `kind` deliberately draws from two namespaces: a name for keywords and
# multi-character punctuators ("LSHIFT", "ELLIPSIS"), the character itself for
# single-character ones ("+", "("). That is lcc's own scheme -- its token codes
# ARE the character values for the single-character cases -- and keeping it
# means our token stream and lcc's line up one for one.
#
# `key` and `next` are the loop's own indices, kept in the token because they
# are free: `key` is where the token's trivia starts and `next` is one past its
# text. A parser may ignore both. There is no column: the byte offset is here
# but the offset of the preceding newline is not, so a column cannot be derived
# from what a token carries. See task-012 -- cheap to add now, expensive once a
# parser depends on this shape.
#
# What this does NOT do: it classifies constants but does not evaluate them.
# lcc computes the value inside gettok, in icon()/fcon()/scon(); here the token
# carries only its text. See task-011, which also records why that is harder in
# Nix than it looks (overflow throws, and strings cannot hold NUL).
let
  b = builtins;

  # Nix string literals understand only \n \r \t \\ \" \$ -- writing "\v" would
  # silently yield the letter v -- so the two remaining C blanks are decoded
  # from JSON rather than written as escapes the language does not have.
  vtab = b.fromJSON "\"\\u000b\"";
  ftab = b.fromJSON "\"\\u000c\"";

  # Character classes, in the spirit of lcc's map[256]. Bits, so they can be
  # or'd. lcc also has a HEX bit; ours would have no reader, because hexadecimal
  # digits are checked by the regex that validates the whole constant.
  BLANK = 1;
  NEWLINE = 2;
  LETTER = 4;
  DIGIT = 8;
  IDCHAR = LETTER + DIGIT;
  SPACE = BLANK + NEWLINE;

  # Explode a string into single-character strings. `split "(.)"` does the
  # whole job in one evaluator call; `genList (i: substring i 1 s)` is the
  # obvious alternative and is 10x slower on a 278 kB file (1.40 s vs 0.13 s).
  # The length check is not paranoia: `.` is a byte-oriented POSIX regex here,
  # and a silent mismatch would corrupt every offset downstream.
  explode = s:
    let cs = map b.head (b.filter b.isList (b.split "(.)" s));
    in
    if b.length cs == b.stringLength s then cs
    else throw "explode: got ${toString (b.length cs)} characters from a ${
      toString (b.stringLength s)}-byte string; input is not single-byte";

  classTable =
    let
      tag = mask: str: b.listToAttrs (map (c: { name = c; value = mask; }) (explode str));
      groups = [
        { mask = BLANK; chars = " \t\r" + vtab + ftab; }
        { mask = NEWLINE; chars = "\n"; }
        { mask = LETTER; chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"; }
        { mask = DIGIT; chars = "0123456789"; }
      ];
    in
    b.foldl'
      (acc: g: acc // b.mapAttrs (name: mask: mask + (acc.${name} or 0)) (tag g.mask g.chars))
      { }
      groups;

  # lcc's keywords, including its two extensions (lcc/src/lex.c). Quoted
  # uniformly because several of them ("if", "else", "or") are Nix keywords.
  keywords = {
    "auto" = "AUTO";
    "break" = "BREAK";
    "case" = "CASE";
    "char" = "CHAR";
    "const" = "CONST";
    "continue" = "CONTINUE";
    "default" = "DEFAULT";
    "do" = "DO";
    "double" = "DOUBLE";
    "else" = "ELSE";
    "enum" = "ENUM";
    "extern" = "EXTERN";
    "float" = "FLOAT";
    "for" = "FOR";
    "goto" = "GOTO";
    "if" = "IF";
    "int" = "INT";
    "long" = "LONG";
    "register" = "REGISTER";
    "return" = "RETURN";
    "short" = "SHORT";
    "signed" = "SIGNED";
    "sizeof" = "SIZEOF";
    "static" = "STATIC";
    "struct" = "STRUCT";
    "switch" = "SWITCH";
    "typedef" = "TYPEDEF";
    "union" = "UNION";
    "unsigned" = "UNSIGNED";
    "void" = "VOID";
    "volatile" = "VOLATILE";
    "while" = "WHILE";
    "__typecode" = "TYPECODE";
    "__firstarg" = "FIRSTARG";
  };

  # Punctuators, longest match first. lcc's set exactly, plus '#'.
  punct3 = { "..." = "ELLIPSIS"; };
  punct2 = {
    "++" = "INCR";
    "--" = "DECR";
    "->" = "DEREF";
    "&&" = "ANDAND";
    "||" = "OROR";
    "<=" = "LEQ";
    "==" = "EQL";
    "!=" = "NEQ";
    ">=" = "GEQ";
    ">>" = "RSHIFT";
    "<<" = "LSHIFT";
  };
  punct1 = b.listToAttrs (map (c: { name = c; value = c; }) (explode "!#%&()*+,-./:;<=>?[]^{|}~"));

  # Number shapes, checked once per numeric token. This is also what separates
  # ICON from FCON: 0x1e is hex, 1e5 is a float. The octal alternative is
  # spelled out so that 08 is rejected, as lcc rejects it, and the suffix is
  # spelled out rather than written `[uUlL]*` so that 1lul is rejected too:
  # lcc's icon() consumes at most one u and one l, in either order, and
  # ppnumber() then errors on whatever is left.
  intSuffix = "(([uU][lL]?)|([lL][uU]?))?";
  reHexInt = "0[xX][0-9a-fA-F]+${intSuffix}";
  reDecInt = "(0[0-7]*|[1-9][0-9]*)${intSuffix}";
  reFloat = "([0-9]*\\.[0-9]+|[0-9]+\\.[0-9]*)([eE][-+]?[0-9]+)?[fFlL]?|[0-9]+[eE][-+]?[0-9]+[fFlL]?";

  lex = src:
    let
      chars = explode src;
      n = b.length chars;

      # "" past end of input plays the part of lcc's NUL sentinel: every
      # lookahead below is total, so no scan can run off the end of the list.
      ch = i: if i >= n then "" else b.elemAt chars i;
      cl = i: if i >= n then 0 else classTable.${b.elemAt chars i} or 0;
      isa = mask: i: b.bitAnd (cl i) mask != 0;
      slice = from: to: b.concatStringsSep "" (b.genList (j: b.elemAt chars (from + j)) (to - from));

      # Drive `step` over consecutive indices from `from` until the state says
      # done or the input ends. Windows double, so depth is O(log length).
      # The deepSeq is not optional: `foldl'` forces its accumulator only to
      # weak head normal form, so an attrset accumulator would leave one
      # unforced field chain per window, as deep as the window.
      runUntil = step: st0: from:
        let
          go = width: pos: st:
            if st.done || pos >= n then st
            else
              let
                lim = if pos + width > n then n else pos + width;
                st' = b.foldl'
                  (s: i: if s.done then s else let r = step s i; in b.deepSeq r r)
                  st
                  (b.genList (i: pos + i) (lim - pos));
              in
              go (2 * width) lim st';
        in
        go 1 from st0;

      # First index at or after `from` whose class misses `mask`, else n.
      scanClass = mask: from:
        let
          r = runUntil (s: i: if isa mask i then s else s // { done = true; pos = i; })
            { done = false; pos = from; } from;
        in
        if r.done then r.pos else n;

      # Whitespace, comments and backslash-newline: one state machine rather
      # than a loop per trivia kind, because they interleave -- a `//` inside a
      # `/* */` is not a comment, and neither is a `/*` inside a `//`.
      #
      # TWO DERIVED FACTS FOR THE PREPROCESSOR, computed here because this is
      # the only place in the tree that already knows them (task-013.01):
      #
      #   `nlAt' -- the trivia contained a newline that ENDED A LOGICAL LINE.
      #     A newline inside a block comment does not, and neither does the one
      #     in a backslash-newline pair; every other newline does, including
      #     the one that terminates a `//' comment. That single rule is what
      #     gcc -E was measured to obey on both sides of the question:
      #     `int a; /* x<nl> */ #define A 1' is NOT a directive to gcc, while
      #     `#define B /* c<nl> */ 7' IS one directive.
      #
      #   `solid' -- the trivia contained a character that was not half of a
      #     backslash-newline pair. Trivia that is spliced and NOT solid is a
      #     continuation joining two token characters, which ISO C splices in
      #     phase 2 into ONE token and this lexer does not (task-008). The
      #     preprocessor refuses that rather than mislexing it.
      #
      # Recomputing either downstream by re-scanning `ws' would be a second
      # definition of one fact, and the two would disagree on the first comment
      # that spans a line.
      triviaStep = s: i:
        let
          c = b.elemAt chars i;
          nx = ch (i + 1);
          line = if c == "\n" then s.line + 1 else s.line;
          closes = c == "*" && nx == "/";
          nl = c == "\n";
        in
        # The only skipped character that can be a newline is the one after a
        # backslash: `/*', `//' and `*/' each skip their second character, and
        # none of those three is a newline. So this is the splice's newline,
        # and it is neither solid nor a line ending.
        if s.skip then
          (if nl then s // { inherit line; skip = false; }
          else s // { inherit line; skip = false; solid = true; })
        else if s.mode == "block" then
          # ISO C splices in phase 2, BEFORE a comment is recognised, so a
          # backslash-newline sitting inside a `*/' ends the comment there:
          # `/* *\<newline>/ + 1 /* */' is `/* */ + 1 /* */' and the `+ 1' is
          # CODE. This scanner would run the comment on to the second
          # terminator and swallow it -- measured against gcc on exactly that
          # input, which returns 2 where we returned 1, with no diagnostic.
          # `checkGlue' cannot see it either, because a comment sets `solid'.
          #
          # The test is the character AFTER the newline rather than the one
          # before the backslash, so that no state has to be carried and so
          # that a run of continuations is caught by its last one. It
          # therefore also refuses `/* x\<newline>/ */', where phase 2 and
          # this scanner agree -- an over-refusal, which is the safe
          # direction for a rule whose other side is a silent miscompile.
          (if c == "\\" && nx == "\n" && ch (i + 2) == "/" then
            throw "a backslash-newline inside the comment opened on line ${toString s.openLine} is followed by `/': ISO C splices that away in translation phase 2, so the `/' closes the comment and what follows it is code. This lexer splices between tokens only (task-008), and would run the comment on to the next `*/' instead"
          else
            s // { inherit line; solid = true; mode = if closes then "code" else "block"; skip = closes; })
        else if s.mode == "line" then
          # ISO C splices in phase 2, BEFORE comments are recognised, so a
          # backslash-newline at the end of a `//' comment carries the comment
          # onto the NEXT line and everything on it is discarded. This lexer
          # splices between tokens, so it would end the comment here and
          # COMPILE that line -- code the standard says is commented out.
          # There is no reading of that which is merely a divergence, so it is
          # refused (task-008). gcc warns about the same construct.
          (if c == "\\" && nx == "\n" then
            throw "a backslash-newline ends the `//' comment on line ${toString s.line}: ISO C splices that away in translation phase 2, so the NEXT line is part of the comment too. This lexer splices between tokens only (task-008), and would compile that line instead of discarding it"
          else s // {
            inherit line;
            solid = true;
            nlAt = s.nlAt || nl;
            mode = if nl then "code" else "line";
          })
        else if b.bitAnd (classTable.${c} or 0) SPACE != 0 then
          s // { inherit line; solid = true; nlAt = s.nlAt || nl; }
        else if c == "/" && nx == "*" then
          s // { inherit line; solid = true; mode = "block"; skip = true; openLine = s.line; }
        else if c == "/" && nx == "/" then
          s // { inherit line; solid = true; mode = "line"; skip = true; }
        else if c == "\\" && nx == "\n" then
          s // { inherit line; skip = true; spliced = true; }
        else s // { inherit line; done = true; pos = i; };

      skipTrivia = from: line:
        let
          r = runUntil triviaStep
            {
              done = false;
              pos = from;
              inherit line;
              mode = "code";
              skip = false;
              openLine = line;
              nlAt = false;
              solid = false;
              spliced = false;
            }
            from;
        in
        if r.done then r
        else if r.mode == "block" then throw "unclosed comment opened on line ${toString r.openLine}"
        else r // { pos = n; };

      # C's preprocessing-number rule: once a number starts, letters, digits,
      # dots and an exponent sign all belong to it. The hex flag is what stops
      # 0x1e+5 from swallowing the '+', which is what lcc does too.
      numStep = hex: s: i:
        let
          c = b.elemAt chars i;
          nx = ch (i + 1);
        in
        if s.skip then s // { skip = false; }
        else if b.bitAnd (classTable.${c} or 0) IDCHAR != 0 || c == "." then
          (
            if !hex && (c == "e" || c == "E") && (nx == "+" || nx == "-")
            then s // { skip = true; }
            else s
          )
        else s // { done = true; pos = i; };

      scanNumber = p:
        let
          hex = b.elemAt chars p == "0" && (ch (p + 1) == "x" || ch (p + 1) == "X");
          r = runUntil (numStep hex) { done = false; pos = p; skip = false; } p;
        in
        if r.done then r.pos else n;

      # String and character literals. A backslash escapes any one character;
      # a bare newline is an error, as it is in lcc's scon(), and so now is a
      # backslash-newline, for the reason below.
      literalKind = quote: if quote == "\"" then "string" else "character";

      strStep = quote: openLine: s: i:
        let c = b.elemAt chars i; in
        if s.esc then
          # ISO C's phase 2 splices this away before the literal is lexed at
          # all, so `"ab\<newline>cd"' IS `"abcd"'. This lexer splices between
          # tokens only (task-008), so it would keep the newline in the lexeme
          # and poc/06-constants would then decode it as an unrecognised
          # escape worth 10 -- a literal with a newline in it where ISO C has
          # none, diagnosed as the wrong thing. Refused rather than mislexed.
          (if c == "\n" then
            throw "a backslash-newline inside the ${literalKind quote} literal started on line ${toString openLine}: ISO C splices that away in translation phase 2 and joins the two lines into one literal. This lexer splices between tokens only (task-008), and would compile a literal with a newline in it instead"
          else s // { esc = false; })
        else if c == "\\" then s // { esc = true; }
        else if c == quote then s // { done = true; pos = i + 1; }
        else if c == "\n" then
          throw "newline inside ${literalKind quote} literal started on line ${toString openLine}"
        else s;

      scanQuoted = quote: from: openLine:
        let
          r = runUntil (strStep quote openLine)
            { done = false; pos = from + 1; esc = false; } (from + 1);
        in
        if !r.done then
          throw "unterminated ${literalKind quote} literal started on line ${toString openLine}, reached end of input"
        # `""` is a legal empty string; `''` has no value to stand for, and a
        # constant evaluator handed it would have to invent one. lcc reads
        # uninitialised buffer here, which is worse than refusing.
        else if quote == "'" && r.pos == from + 2 then
          throw "empty character constant on line ${toString openLine}"
        else
          { kind = if quote == "\"" then "SCON" else "ICON"; end = r.pos; };

      # Classify one numeric lexeme. Order matters: 0x1e is an integer even
      # though it ends in what would otherwise be an exponent marker.
      numberKind = text: line:
        if b.match reHexInt text != null then "ICON"
        else if b.match reFloat text != null then "FCON"
        else if b.match reDecInt text != null then "ICON"
        else throw "invalid numeric constant `${text}' on line ${toString line}";

      # Scan the trivia starting at `from`, then the single token after it.
      # Returns a genericClosure item. `key` is `from`, which strictly
      # increases: only EOI consumes nothing, and EOI ends the loop.
      scanFrom = from: startLine:
        let
          tv = skipTrivia from startLine;
          p = tv.pos;
          inherit (tv) line;
          c = ch p;
          k = cl p;
          wide = c == "L" && (ch (p + 1) == "'" || ch (p + 1) == "\"");
          wq = ch (p + 1);

          # Every branch reports its own `text` rather than leaving the caller
          # to cut it again from `end`. Identifiers and numbers already built
          # the string to classify it, and a punctuator IS the one-, two- or
          # three-character lookahead the branch matched on, so this costs the
          # dominant token kinds no slice at all.
          got =
            if p >= n then { kind = "EOI"; end = n; text = ""; }
            else if wide then
              let r = scanQuoted wq (p + 1) line;
              in r // { text = slice p r.end; }
            else if b.bitAnd k LETTER != 0 then
              let
                e = scanClass IDCHAR (p + 1);
                word = slice p e;
              in
              { kind = keywords.${word} or "ID"; end = e; text = word; }
            else if b.bitAnd k DIGIT != 0 || (c == "." && isa DIGIT (p + 1)) then
              let
                e = scanNumber p;
                num = slice p e;
              in
              { kind = numberKind num line; end = e; text = num; }
            else if c == "\"" || c == "'" then
              let r = scanQuoted c p line;
              in r // { text = slice p r.end; }
            else
              let
                c2 = c + ch (p + 1);
                c3 = c2 + ch (p + 2);
              in
              if punct3 ? ${c3} then { kind = punct3.${c3}; end = p + 3; text = c3; }
              else if punct2 ? ${c2} then { kind = punct2.${c2}; end = p + 2; text = c2; }
              else if punct1 ? ${c} then { kind = c; end = p + 1; text = c; }
              else throw "unexpected character `${c}' on line ${toString line}";
        in
        {
          key = from;
          inherit (got) kind text;
          inherit line;
          ws = slice from p;
          next = got.end;
          # No token can span a line any more: a literal with a bare newline
          # in it is refused, and so is one continued with a backslash, so
          # every newline in the file is trivia and skipTrivia has counted it.
          nextLine = line;
          # This token starts a logical line: either its trivia ended one, or
          # it is the first token in the file. A `#' with this set is a
          # directive; without it, a stray punctuator.
          bol = tv.nlAt || from == 0;
          # Its trivia is a line continuation AND NOTHING ELSE, so the splice
          # sits between two characters ISO C's phase 2 would have joined into
          # one token. See task-008: this lexer splices between tokens only,
          # and the preprocessor refuses this case rather than mislexing it.
          glue = tv.spliced && !tv.solid;
        };
    in
    b.genericClosure {
      startSet = [ (scanFrom 0 1) ];
      operator = it:
        if it.kind == "EOI" then [ ]
        else let x = scanFrom it.next it.nextLine; in b.deepSeq x [ x ];
    };

  # The inverse of `lex`. Every byte of the source belongs to exactly one
  # token's `ws` or `text`, so this reproduces the input exactly or the lexer
  # has lost or duplicated something.
  render = toks: b.concatStringsSep "" (b.concatLists (map (t: [ t.ws t.text ]) toks));

  # Compact form for the expected-token tables. EOI is dropped: it carries no
  # text, and every table would otherwise end in the same noise.
  brief = toks: map (t: "${t.kind}:${t.text}") (b.filter (t: t.kind != "EOI") toks);
in
{
  inherit lex render brief;
  # Exported because poc/06-constants needs the same one. Cutting text out of a
  # character list rather than out of a string is a rule this whole tree obeys
  # (decision-001), and a second copy of it is a second place for the
  # single-byte assertion above to go missing from.
  inherit explode;

  # Every `kind' this lexer can produce, DERIVED from the tables above rather
  # than listed. poc/07-parser classifies tokens by kind and has its own lists
  # of which kinds start a statement, a declaration or an expression; a typo in
  # one of those degrades silently into "this token is its own kind", so the
  # parser checks its names against this set. Deriving it is the point: a
  # keyword added here appears here too, with nothing to remember.
  tokenKinds =
    b.attrValues keywords
    ++ b.attrValues punct3
    ++ b.attrValues punct2
    ++ b.attrNames punct1
    ++ [ "ID" "ICON" "FCON" "SCON" "EOI" ];
}
