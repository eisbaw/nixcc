# A minimal C preprocessor in Nix: slice 1 of decision-005.
#
# Scope, and the reason it stops where it does (task-013.01): line splicing,
# object-like `#define', `#undef', the whole conditional family with
# constant-expression evaluation, `#line', and the `# n "file"' linemarkers
# lcc's input.c resynch() parses. Function-like macros, `#' and `##' are
# task-013.02; `#include' is task-013.03 and waits on task-070, which has to
# decide where a header comes from and how that survives a pure eval. Every
# refusal below for something a later slice will do NAMES the slice's task.
#
# A note on which refusals carry a task id and which do not, because the rule
# is easy to over-read: a refusal that DEFERS A FEATURE names the task that
# will implement it, so nothing can go missing the way compound types did. A
# diagnostic for malformed input -- `#endif' with nothing open, `#line' with
# no number -- defers nothing and names only what is wrong with the input.
#
# ============================== the shape =================================
#
# IT WORKS ON TOKENS, NOT ON TEXT. poc/02-lexer already lexes RAW C89 -- it
# keeps `#', `//' and backslash-newline, all three of which lcc's own lexer
# rejects because lcc is fed preprocessed input -- and its tokens carry
# `kind', `text', `line' and `ws', which is everything poc/07-parser reads.
# A text-in/text-out preprocessor would lex the translation unit, print it,
# and lex it again, paying the lexer's measured ~4 kB of peak RSS per token
# twice over. Memory is this project's binding constraint (decision-001,
# decision-007: 142-359 kB of peak RSS per source line in the frontend), so
# the seam is a token list and `render' below exists only for the two
# consumers that genuinely want text -- the gcc -E differential, and rcc.
#
# LOGICAL LINES COME FROM THE LEXER. A directive is a `#' that is the first
# token on a logical line, and the line ends at the first newline that is
# outside a comment and is not half of a backslash-newline pair. lex.nix's
# triviaStep is the only state machine in this tree that already knows which
# of those a newline is, so it now derives two flags per token -- `bol' and
# `glue' -- rather than this file re-scanning every token's `ws' and becoming
# a second, divergent definition of the same rule. Both halves of that rule
# were measured against gcc -E and are quoted in lex.nix.
#
# LINE SPLICING, EXACTLY AS FAR AS IT GOES. The lexer splices
# backslash-newline BETWEEN tokens, not in ISO C's phase 2 (task-008), so a
# continued directive -- the case that actually occurs -- already works and
# needs nothing here. A continuation that joins two TOKEN characters
# (`ab\<newline>cd', one identifier in ISO C, two in this lexer) is REFUSED
# naming task-008 rather than silently mislexed. That is what `glue' is for.
# Doing the full phase-2 pass would mean splicing the text before lexing and
# then carrying an offset-to-line map to keep line numbers exact, which is
# more machinery and more live values than the case is worth; task-008
# already records that whoever does it should do it as a pass before the
# lexer.
#
# WHAT `#if' ARITHMETIC IS DONE IN, and it is a real divergence from gcc.
# C89 6.8.1 evaluates a `#if' with every signed type widened to `long' and
# every unsigned one to `unsigned long'; on RV32 both are 32 bits
# (decision-003), so everything below is computed modulo 2^32. gcc has used
# intmax_t since C99, so `#if 2147483647 + 1 > 0' is FALSE here and TRUE
# under gcc. Ours is the C89 answer on this target and gcc's is the C99 one;
# the differential corpus deliberately stays clear of the width, and
# cases.nix pins the wrapping behaviour directly instead.
#
# Nix has no shift operators and its integer overflow THROWS rather than
# wrapping (decision-001), which is why `shl'/`shr' go through a power-of-two
# table and why `mul' multiplies in 16-bit halves: (2^32-1)^2 is far past the
# 63-bit ceiling, and a thrown evaluator error is not a diagnosable overflow,
# it is the whole compilation dying with a message about Nix.
#
# SHORT-CIRCUITING IS LAZINESS, NOT A SPECIAL CASE. `#if 0 && (1/0)' must not
# divide. The expression parser returns `{ v; u; i; }` where `i' -- the
# position -- is always forced but `v' is a thunk, so `&&' can consume its
# right operand's TOKENS without consuming its VALUE. That falls out of the
# evaluator for free and is the reason there is no separate "evaluate or just
# skip" mode in the parser.
#
# EXPANSION IS RECURSIVE, AND THE CAP IS WHAT MAKES THAT LEGAL. decision-001
# bans traversals whose DEPTH tracks input length. `expandTok' recurses once
# per nested macro and carries a hide set that grows by one name each time, so
# it always terminates -- but the number of DISTINCT macros in a chain is
# itself bounded by the size of the file and by nothing else, so the depth
# does track input length. Measured: with the cap lifted, a chain of 3000
# expands and one of 6000 dies with "stack overflow; max-call-depth
# exceeded". So MAX_NEST is load-bearing rather than defensive, and task-071
# carries what would remove it -- a genericClosure worklist, which task-013.02
# has to build anyway for function-like macros.
let
  b = builtins;
  lexer = import ../02-lexer/lex.nix;
  const = import ../06-constants/const.nix;

  # ---- 32-bit arithmetic, done the way decision-001 forces ---------------
  TWO32 = 4294967296;
  TWO31 = 2147483648;
  # Powers of two, because Nix has no shift. poc/01-encoder and
  # poc/07-parser/types.nix each have their own three-line copy of this; a
  # fourth is cheaper than making the preprocessor import the RV32
  # instruction encoder, which is what sharing would cost here.
  pow2 = n: b.foldl' (a: _: a * 2) 1 (b.genList (i: i) n);

  # Reduce into [0, 2^32). Nix's `/' truncates toward zero and there is no
  # `mod' builtin, so the remainder is spelled out and corrected for sign.
  wrap = n:
    let r = n - (n / TWO32) * TWO32; in
    if r < 0 then r + TWO32 else r;

  # The mathematical value a bit pattern stands for, given its signedness.
  sgn = x: if x.u then x.v else (if x.v >= TWO31 then x.v - TWO32 else x.v);

  # a * b mod 2^32 without ever forming a product above 2^63. Both operands
  # are below 2^32, so the naive multiply can reach 2^64 and Nix would THROW
  # (decision-001) -- taking the compilation down with a message about the
  # evaluator rather than about the user's `#if'.
  mulmod = x: y:
    let
      a1 = x / 65536; a0 = b.bitAnd x 65535;
      b1 = y / 65536; b0 = b.bitAnd y 65535;
      cross = b.bitAnd (a1 * b0 + a0 * b1) 65535;
    in
    wrap (a0 * b0 + cross * 65536);

  # Floor division, for the arithmetic right shift of a negative value. C89
  # leaves `>>' on a negative left operand implementation-defined; gcc shifts
  # arithmetically, and `-1 / 2' truncating toward zero would give 0 where an
  # arithmetic shift gives -1.
  floorDiv = x: y: let q = x / y; in if x - q * y < 0 then q - 1 else q;

  # ---- identifiers -------------------------------------------------------
  # A macro name is an identifier, and to the PREPROCESSOR a keyword is an
  # identifier too -- `#define int long' is legal C. The lexer classifies
  # `int' as kind INT, so a name is tested by its TEXT rather than its kind.
  isIdent = s: b.match "[A-Za-z_][A-Za-z0-9_]*" s != null;

  # Whether a token could be a macro invocation. `macros ? ${t.text}' alone
  # would be enough -- every macro name is an identifier, and no punctuator,
  # number or literal lexeme spells one -- but this states the reason rather
  # than relying on it silently.
  invokes = macros: t: macros ? ${t.text};

  # ---- macro expansion ---------------------------------------------------
  # The hide set is the blue paint of the standard's 6.8.3.4: a macro is not
  # re-expanded inside its own expansion. Measured against gcc: `#define F F'
  # yields `F', and `#define G H' with `#define H G' yields `G'.
  MAX_NEST = 200;

  # THE ONE PLACE A TOKEN IS MANUFACTURED rather than lexed, and it exists
  # because there were two and they remembered different halves of the shape.
  # poc/02-lexer's token carries `key', `next' and `nextLine' as well as the
  # four fields anything downstream reads -- the loop's own indices, free for
  # the lexer and meaningless for a token that was never at an offset. They
  # are still SET here rather than dropped, because an attribute miss is the
  # one failure builtins.tryEval does not catch (task-037), and a consumer
  # reading `nextLine' off a synthesised token should get a number rather
  # than take the whole compilation down.
  #
  #   `line'  is the USE site, never the definition: a diagnostic has to
  #           point at the code the reader wrote.
  #   `ws'    is one space unconditionally, which is what stops an expansion
  #           pasting against its neighbour -- `#define P +' used as `a+P b'
  #           must not render as `a++ b'. The cost is that a macro can never
  #           reconstruct a compound assignment through poc/02-lexer's
  #           `ws == ""' peek (`a <<P' with `#define P =' is LSHIFT then
  #           `='), which no real program asks for.
  #   `bol'   is false: in cpp OUTPUT it is the line record, not the token,
  #           that says where a line begins.
  mkTok = use: fields:
    {
      inherit (use) line key next;
      ws = " ";
      nextLine = use.line;
      bol = false;
      glue = false;
    } // fields;

  fromBody = use: bt: mkTok use { inherit (bt) kind text; };

  expandTok = macros: hidden: depth: t:
    if !(invokes macros t) || hidden ? ${t.text} then [ t ]
    else if depth >= MAX_NEST then
      throw "cpp: macro `${t.text}' on line ${toString t.line} is nested more than ${
        toString MAX_NEST} macros deep. Expansion recurses once per nesting level and Nix's max-call-depth is a setting this project will not ask a `nix eval' user to raise (decision-001); see task-071"
    else
      let
        m = macros.${t.text};
        hidden' = hidden // { ${t.text} = true; };
      in
      # `map (fromBody t)' runs once per ENCLOSING level, so a token nested d
      # deep is rewritten d times: the cost of one invocation is
      # O(depth x expansion) rather than O(expansion). Bounded by MAX_NEST and
      # by expansions that are a handful of tokens; worth knowing before
      # task-013.02 makes an expansion large.
      map (fromBody t) (b.concatMap (expandTok macros hidden' (depth + 1)) m.body);

  expandList = macros: ts: b.concatMap (expandTok macros { } 0) ts;

  # ---- #if expressions ---------------------------------------------------
  # `defined X' and `defined ( X )' are resolved BEFORE expansion, because
  # their operand is a name and not a value. genericClosure rather than a
  # recursive walk for decision-001's reason: this emits a variable number of
  # tokens per step, and its depth must not track the line's length.
  definedIcon = t: v: mkTok t { kind = "ICON"; text = if v then "1" else "0"; };

  resolveDefined = macros: ts:
    let
      n = b.length ts;
      at = i: b.elemAt ts i;
      kindAt = i: if i >= n then "" else (at i).kind;
      textAt = i: if i >= n then "" else (at i).text;

      step = i:
        let
          t = at i;
          paren = kindAt (i + 1) == "(" && isIdent (textAt (i + 2)) && kindAt (i + 3) == ")";
          bare = isIdent (textAt (i + 1));
        in
        if t.text != "defined" then { key = i; next = i + 1; out = [ t ]; }
        else if paren then
          { key = i; next = i + 4; out = [ (definedIcon t (macros ? ${textAt (i + 2)})) ]; }
        else if bare then
          { key = i; next = i + 2; out = [ (definedIcon t (macros ? ${textAt (i + 1)})) ]; }
        else
          throw "cpp: line ${toString t.line}: `defined' must be followed by an identifier or by `( identifier )'";

      items =
        if n == 0 then [ ]
        else b.genericClosure {
          startSet = [ (step 0) ];
          operator = it: if it.next >= n then [ ] else let x = step it.next; in b.deepSeq x [ x ];
        };
    in
    b.concatLists (map (it: it.out) items);

  # Every identifier still standing after expansion is 0 (C89 6.8.1). That
  # includes keywords: to the preprocessor `int' is just a name, so
  # `#if sizeof(int)' becomes `0(0)' and is a syntax error, exactly as gcc
  # reports it.
  zeroIdents = ts:
    map (t: if isIdent t.text then t // { kind = "ICON"; text = "0"; } else t) ts;

  # C89's integer promotions, which decide the signedness `#if' computes in.
  # Only `unsigned int' and `unsigned long' survive as unsigned; a wide
  # character constant is `unsigned short', whose every value fits in an int,
  # so it promotes to a SIGNED int. `or (throw ...)' rather than a defaulting
  # lookup because builtins.tryEval does not catch an attribute miss
  # (task-037) and this decides the sign of every comparison below.
  unsignedTypes = {
    "int" = false;
    "long" = false;
    "unsigned int" = true;
    "unsigned long" = true;
    "unsigned short" = false;
  };
  isUnsigned = ty:
    unsignedTypes.${ty} or (throw "cpp: the constant evaluator returned type `${ty}', which this `#if' evaluator has no promotion rule for");

  evalExpr = ts: line:
    let
      n = b.length ts;
      at = i: if i >= n then { kind = "EOI"; text = ""; } else b.elemAt ts i;
      kindAt = i: (at i).kind;
      bad = msg: throw "cpp: line ${toString line}: ${msg}";

      num = v: u: { inherit v u; };
      boolean = c: num (if c then 1 else 0) false;

      prim = i:
        let t = at i; in
        if t.kind == "ICON" then
          let
            c = const.evalICON t.text;
            u = isUnsigned c.type;
          in
          # poc/06-constants CLAMPS a constant that does not fit and records
          # why in `warnings'. There is no warning channel here, and a clamped
          # value silently changes which arm a `#if' takes -- `4294967296'
          # becomes 4294967295, so `#if 4294967296 == 4294967295' would be
          # TRUE. poc/07-parser replays these warnings; this stage cannot, so
          # it refuses instead. Same reasoning as the redefinition below.
          if c.warnings != [ ] then
            bad "`${t.text}' in a `#if' expression: ${b.head c.warnings}"
          else
            { v = if c.value < 0 then c.value + TWO32 else c.value; inherit u; i = i + 1; }
        else if t.kind == "(" then
          let e = conditional (i + 1); in
          if kindAt e.i != ")" then bad "unbalanced `(' in the `#if' expression"
          else { inherit (e) v u; i = e.i + 1; }
        else if t.kind == "FCON" then
          bad "floating constant `${t.text}' in a `#if': float is deferred to a later wave (decision-006), and task-015 wants it refused rather than silently miscompiled"
        else if t.kind == "SCON" then
          bad "string literal ${t.text} in a `#if': a `#if' expression is an integer constant expression"
        else if t.kind == "EOI" then
          bad "the `#if' expression ends where a value was expected"
        else
          bad "`${t.text}' is not a value in a `#if' expression";

      unary = i:
        let k = kindAt i; in
        if k == "-" then let e = unary (i + 1); in { v = wrap (0 - e.v); inherit (e) u i; }
        else if k == "+" then unary (i + 1)
        # No bitNot in Nix (decision-001); the complement of a value already
        # reduced into [0, 2^32) is the subtraction.
        else if k == "~" then let e = unary (i + 1); in { v = 4294967295 - e.v; inherit (e) u i; }
        else if k == "!" then let e = unary (i + 1); in (boolean (e.v == 0)) // { inherit (e) i; }
        else prim i;

      # One left-associative binary level. `ops' maps a token kind to the
      # function that combines two values. The loop is recursion whose depth
      # tracks the number of OPERATORS in one `#if' expression -- bounded by
      # one logical line of source, not by the file -- which is the
      # recursive-descent exemption decision-001 grants.
      level = ops: below: i:
        let
          go = acc:
            let k = kindAt acc.i; in
            if !(ops ? ${k}) then acc
            else
              let r = below (acc.i + 1); in
              go ((ops.${k} acc r) // { inherit (r) i; });
        in
        go (below i);

      # The usual arithmetic conversions, in the only form C89 needs here: if
      # either operand is unsigned, both are read as unsigned.
      arith = f: x: y: let u = x.u || y.u; in { v = f u x y; inherit u; };
      cmp = f: x: y: let u = x.u || y.u; in boolean (f (if u then x.v else sgn x) (if u then y.v else sgn y));

      divisor = op: y: if y.v == 0 then bad "`${op}' by zero in a `#if' expression" else y;
      shiftBy = y:
        if y.u || y.v < TWO31 then
          (if y.v > 31 then bad "shift by ${toString y.v} in a `#if' expression: this evaluator computes in 32 bits (C89 6.8.1 on a target whose long is 4 bytes), and a count outside 0..31 has no defined answer to give" else y.v)
        else bad "shift by a negative count in a `#if' expression";

      mulOps = {
        "*" = arith (_: x: y: mulmod x.v y.v);
        "/" = arith (u: x: y: let d = divisor "/" y; in if u then x.v / d.v else wrap (sgn x / sgn d));
        "%" = arith (u: x: y:
          let d = divisor "%" y; in
          if u then x.v - (x.v / d.v) * d.v
          else wrap (sgn x - (sgn x / sgn d) * sgn d));
      };
      addOps = {
        "+" = arith (_: x: y: wrap (x.v + y.v));
        "-" = arith (_: x: y: wrap (x.v - y.v));
      };
      shiftOps = {
        # The result of a shift takes the LEFT operand's type, not the usual
        # arithmetic conversions.
        "LSHIFT" = x: y: { v = wrap (x.v * pow2 (shiftBy y)); inherit (x) u; };
        "RSHIFT" = x: y:
          let p = pow2 (shiftBy y); in
          { v = if x.u then x.v / p else wrap (floorDiv (sgn x) p); inherit (x) u; };
      };
      relOps = {
        "<" = cmp (x: y: x < y);
        ">" = cmp (x: y: x > y);
        "LEQ" = cmp (x: y: x <= y);
        "GEQ" = cmp (x: y: x >= y);
      };
      eqOps = {
        "EQL" = cmp (x: y: x == y);
        "NEQ" = cmp (x: y: x != y);
      };
      andOps = { "&" = arith (_: x: y: b.bitAnd x.v y.v); };
      xorOps = { "^" = arith (_: x: y: b.bitXor x.v y.v); };
      orOps = { "|" = arith (_: x: y: b.bitOr x.v y.v); };

      mul = level mulOps unary;
      add = level addOps mul;
      shift = level shiftOps add;
      rel = level relOps shift;
      eq = level eqOps rel;
      bitand = level andOps eq;
      bitxor = level xorOps bitand;
      bitor = level orOps bitxor;

      # `&&' and `||' consume their right operand's TOKENS but force its
      # VALUE only when the answer depends on it. That is what makes
      # `#if 0 && (1/0)' legal, and it costs nothing because `r.v' is a thunk
      # until something looks at it.
      logand = i:
        let
          go = acc:
            if kindAt acc.i != "ANDAND" then acc
            else
              let r = bitor (acc.i + 1); in
              go { v = if acc.v == 0 then 0 else (if r.v == 0 then 0 else 1); u = false; inherit (r) i; };
        in
        go (bitor i);

      logor = i:
        let
          go = acc:
            if kindAt acc.i != "OROR" then acc
            else
              let r = logand (acc.i + 1); in
              go { v = if acc.v != 0 then 1 else (if r.v == 0 then 0 else 1); u = false; inherit (r) i; };
        in
        go (logand i);

      conditional = i:
        let c = logor i; in
        if kindAt c.i != "?" then c
        else
          let
            t = conditional (c.i + 1);
            e = if kindAt t.i == ":" then conditional (t.i + 1)
                else bad "a `?' in a `#if' expression with no matching `:'";
            u = t.u || e.u;
          in
          { v = if c.v != 0 then t.v else e.v; inherit u; inherit (e) i; };

      r = conditional 0;
    in
    if n == 0 then bad "`#if' with no expression"
    else if r.i != n then bad "`${(at r.i).text}' is left over at the end of the `#if' expression"
    else r.v != 0;

  # ---- the directive pass ------------------------------------------------
  preprocess = { src, file ? "<stdin>" }:
    let
      toks = lexer.lex src;
      nAll = b.length toks;
      # The EOI token is not part of any logical line; it is appended to the
      # output once, at the end, so that the parser sees the terminator it
      # expects whatever the last directive did.
      nCode = nAll - 1;
      eoi = b.elemAt toks nCode;
      code = i: b.elemAt toks i;

      starts = b.filter (i: (code i).bol) (b.genList (i: i) nCode);
      nLines = b.length starts;
      groupAt = k:
        let
          from = b.elemAt starts k;
          to = if k + 1 < nLines then b.elemAt starts (k + 1) else nCode;
        in
        b.genList (i: code (from + i)) (to - from);

      # ISO C splices in phase 2 and this lexer splices between tokens
      # (task-008). The two agree on almost everything: `1\<nl>+2' is `1 + 2'
      # either way. They disagree exactly when the characters on the two
      # sides of the continuation would have lexed as ONE token had the
      # splice happened first -- `ab\<nl>cd', or `<\<nl><'. So the test is
      # not "was there a splice" but "does re-lexing the two lexemes joined
      # give the same two lexemes back", which is decided by asking the
      # lexer rather than by a character-class rule that would have to be
      # kept in step with the punctuator table.
      #
      # `tryEval' is here because the joined text can fail to lex at all --
      # `/' and `*' become an unclosed comment -- and that is the strongest
      # possible evidence that the two do not stay separate.
      staysApart = p: t:
        let
          r = b.tryEval (
            let toks = b.filter (x: x.kind != "EOI") (lexer.lex (p.text + t.text)); in
            b.deepSeq toks toks);
        in
        r.success
        && b.length r.value == 2
        && (b.head r.value).text == p.text
        && (b.elemAt r.value 1).text == t.text;

      # A `glue' token always has a predecessor inside its own group: trivia
      # made only of continuations contains no line-ending newline, so such a
      # token is never the first on a logical line, and the file's very first
      # token has no trivia at all.
      checkGlue = ts:
        if !(b.any (t: t.glue) ts) then true else
        let
          joined = b.filter
            (i: let t = b.elemAt ts i; in t.glue && !(staysApart (b.elemAt ts (i - 1)) t))
            (b.genList (i: i) (b.length ts));
        in
        if joined == [ ] then true
        else
          let
            i = b.head joined;
            t = b.elemAt ts i;
          in
          throw "cpp: line ${toString t.line}: a backslash-newline joins `${
            (b.elemAt ts (i - 1)).text}' to `${t.text}'. ISO C's phase 2 splices that into ONE token before lexing; poc/02-lexer splices between tokens only (task-008), so this is refused rather than lexed as two";

      live = st: st.cond == [ ] || (b.head st.cond).active;
      here = ts: (b.head ts).line;

      # --- #define ---------------------------------------------------------
      # THE TABLE IS ONE ATTRSET, AND THAT IS QUADRATIC. `//' copies every
      # binding the table already holds, so n `#define's copy n^2/2 of them:
      # measured at 4 MB of peak RSS above lexing at 500 macros, 37 MB at
      # 2000 and 138 MB at 4000. memory.py's second ladder carries those
      # numbers and a ceiling on the top one so it cannot get quietly worse;
      # task-072 carries what it would take to make it linear, and why the
      # obvious remedies (bucket by first character, hash the name) are each
      # wrong for a different reason. It is left as it is here because slice 1
      # has no `#include' and nobody writes four thousand defines by hand.
      defineIn = st: ts: dline:
        let
          nameTok = if ts == [ ] then throw "cpp: line ${toString dline}: `#define' with no macro name" else b.head ts;
          name = nameTok.text;
          body = b.tail ts;
          first = b.head body;
          sameSpelling = xs: ys:
            b.length xs == b.length ys
            && b.all (i:
              let x = b.elemAt xs i; y = b.elemAt ys i; in
              x.text == y.text && (x.ws == "") == (y.ws == ""))
              (b.genList (i: i) (b.length xs));
          hashes = b.filter (t: t.kind == "#") body;
          # `##' reaches here as two `#' tokens with nothing between them --
          # poc/02-lexer has no `##' punctuator, deliberately, because `#' is
          # the preprocessor's and the lexer leaves it alone. Telling the two
          # apart matters: they are different operators, and must-fail.nix
          # cannot distinguish two cases that throw the same sentence.
          pastes = b.filter
            (i: (b.elemAt body i).kind == "#" && (b.elemAt body (i + 1)).kind == "#"
              && (b.elemAt body (i + 1)).ws == "")
            (b.genList (i: i) (if body == [ ] then 0 else b.length body - 1));
          prev = st.macros.${name} or null;
          m = { inherit name body; line = dline; };
        in
        if !(isIdent name) then
          throw "cpp: line ${toString dline}: `${name}' is not a macro name; `#define' takes an identifier"
        # C89 forbids it by name, and for a reason this file would feel:
        # `defined' is resolved before expansion, so a macro of that name is
        # silently never used.
        else if name == "defined" then
          throw "cpp: line ${toString dline}: `defined' cannot be a macro name; it is the operator a `#if' expression uses to ask whether a name is defined"
        else if body != [ ] && first.kind == "(" && first.ws == "" then
          throw "cpp: line ${toString dline}: `${name}(' is a function-like macro, which slice 1 does not do; parameters, `#' and `##' are task-013.02"
        else if pastes != [ ] then
          throw "cpp: line ${toString dline}: `##' in the replacement list of `${name}': token paste is task-013.02"
        else if hashes != [ ] then
          throw "cpp: line ${toString dline}: `#' in the replacement list of `${name}': stringify is task-013.02"
        # C89 6.8.3 says a redefinition SHALL be identical. gcc makes that a
        # warning and takes the new body; there is no warning channel here,
        # and a body that quietly changed under a second `#define' is the
        # kind of thing that is found three stages later, so it is refused.
        else if prev != null && !(sameSpelling prev.body body) then
          throw "cpp: line ${toString dline}: `${name}' is redefined with a different replacement list; it was defined on line ${toString prev.line}, and C89 6.8.3 requires a redefinition to be identical. `#undef' it first"
        else st // { macros = st.macros // { ${name} = b.deepSeq m m; }; };

      oneName = what: ts: dline:
        if b.length ts == 1 && isIdent (b.head ts).text then (b.head ts).text
        else throw "cpp: line ${toString dline}: `${what}' takes exactly one identifier";

      # 6.8.1: in a group that is not being compiled, a directive is examined
      # only to keep track of nesting. That is what lets `#if 0' fence off
      # text, and it has to apply to `#else junk' and `#endif junk' as well as
      # to the `#if' operands -- otherwise the rule holds for three directives
      # out of five and the comment above `#if' describes something this file
      # does not do.
      noOperands = skip: what: ts: dline:
        if skip || ts == [ ] then true
        else throw "cpp: line ${toString dline}: `${what}' takes no operands, and `${(b.head ts).text}' follows it";

      # --- the conditional stack -------------------------------------------
      # A frame remembers three things and needs all three: `active' is
      # whether this group's text is being emitted, `taken' is whether any
      # arm of this `#if' has been taken yet -- so that a later `#elif' or
      # `#else' knows to stay quiet -- and `parentActive' is whether the
      # enclosing group was live, which is what makes a nested `#else' inside
      # a skipped `#if' stay skipped.
      push = st: taken: st // {
        cond = [{
          active = live st && taken;
          # In a skipped group nothing is evaluated and no arm may fire, so
          # the frame opens already taken.
          taken = if live st then taken else true;
          parentActive = live st;
          kind = "if";
        }] ++ st.cond;
      };

      condOf = st: what: dline:
        if st.cond == [ ] then throw "cpp: line ${toString dline}: `${what}' with no matching `#if'"
        else b.head st.cond;

      # --- #line and the linemarker form -----------------------------------
      # lcc's resynch() reads `# n [ "file" ]' and `#line n [ "file" ]' the
      # same way, and takes n as the number of the NEXT line. `delta' is
      # carried rather than an absolute number so that a translation unit
      # with no #line in it rewrites no token at all.
      relocate = st: ts: dline: endLine: what:
        let
          expanded = expandList st.macros ts;
          numTok = if expanded == [ ] then throw "cpp: line ${toString dline}: `${what}' with no line number" else b.head expanded;
          rest = b.tail expanded;
          nameTok = b.head rest;
          num = (const.evalICON numTok.text).value;
          numWarnings = (const.evalICON numTok.text).warnings;
        in
        if numTok.kind != "ICON" || b.match "[0-9]+" numTok.text == null then
          throw "cpp: line ${toString dline}: `${what}' wants a decimal line number, not `${numTok.text}'"
        else if numWarnings != [ ] then
          # As in `#if': a clamped constant is not a line number, it is a
          # number poc/06-constants had to invent. `#line 99999999999' would
          # otherwise relocate to 4294967295.
          throw "cpp: line ${toString dline}: `${what} ${numTok.text}' does not name a line: ${b.head numWarnings}"
        else if num < 1 then
          throw "cpp: line ${toString dline}: `${what} ${numTok.text}' asks for a line number below 1"
        else st // {
          # The number names the line AFTER the directive, and "after" means
          # after its last PHYSICAL line: a `#line' continued with a
          # backslash-newline occupies more than one.
          delta = num - (endLine + 1);
          # Trailing flags after the file name are gcc's (`# 1 "f.c" 1'), and
          # lcc's resynch() stops at the closing quote, so they are ignored
          # here too rather than refused: that is what makes this cpp
          # idempotent on gcc -E output.
          file =
            if rest == [ ] then st.file
            else if nameTok.kind == "SCON" then b.substring 1 (b.stringLength nameTok.text - 2) nameTok.text
            else throw "cpp: line ${toString dline}: the file name after `${what} ${numTok.text}' must be a string literal, not `${nameTok.text}'";
        };

      # --- one logical line -------------------------------------------------
      directive = st: ts: dline:
        let
          rest = b.tail ts;
          what = if rest == [ ] then "" else (b.head rest).text;
          args = if rest == [ ] then [ ] else b.tail rest;
          frame = condOf st "#${what}" dline;
          skipping = !(live st);
          endLine = (b.elemAt ts (b.length ts - 1)).line;
        in
        # A `#' alone on a line is the null directive and does nothing.
        if what == "" then st
        else if what == "ifdef" then push st (!skipping && st.macros ? ${oneName "#ifdef" args dline})
        else if what == "ifndef" then push st (!skipping && !(st.macros ? ${oneName "#ifndef" args dline}))
        # A `#if' inside a group that is not being compiled is NOT evaluated:
        # 6.8.1 says a skipped group's directives are checked only for
        # nesting, which is what lets `#if 0' fence off text that would not
        # even evaluate. The nesting level is still pushed, or `#endif' would
        # close the wrong one.
        else if what == "if" then
          push st (!skipping && evalExpr (zeroIdents (expandList st.macros (resolveDefined st.macros args))) dline)
        else if what == "elif" then
          if frame.kind == "else" then throw "cpp: line ${toString dline}: `#elif' after `#else'"
          else
            let
              take = frame.parentActive && !frame.taken
                && evalExpr (zeroIdents (expandList st.macros (resolveDefined st.macros args))) dline;
            in
            st // {
              cond = [ (frame // { active = take; taken = frame.taken || take; }) ] ++ b.tail st.cond;
            }
        else if what == "else" then
          if frame.kind == "else" then throw "cpp: line ${toString dline}: a second `#else' for the `#if' this closes"
          else b.seq (noOperands skipping "#else" args dline) (st // {
            cond = [
              (frame // {
                active = frame.parentActive && !frame.taken;
                taken = true;
                kind = "else";
              })
            ] ++ b.tail st.cond;
          })
        else if what == "endif" then
          b.seq frame (b.seq (noOperands skipping "#endif" args dline) (st // { cond = b.tail st.cond; }))
        # Everything below this line is INERT inside a skipped group.
        else if skipping then st
        else if what == "define" then defineIn st args dline
        else if what == "undef" then
          st // { macros = b.removeAttrs st.macros [ (oneName "#undef" args dline) ]; }
        else if what == "line" then relocate st args dline endLine "#line"
        else if (b.head rest).kind == "ICON" then relocate st rest dline endLine "#"
        else if what == "include" then
          throw "cpp: line ${toString dline}: `#include' is task-013.03, which waits on task-070 -- where a header resolves from, and how that survives a `nix flake check' with no --impure, are not decided yet"
        else
          throw "cpp: line ${toString dline}: `#${what}' is not a directive slice 1 implements. Slice 1 is #define/#undef/#if/#ifdef/#ifndef/#elif/#else/#endif/#line; what the minimal preprocessor deliberately leaves out is tracked in task-014";

      textLine = st: ts:
        let
          out = expandList st.macros ts;
          shift = t: if st.delta == 0 then t else t // { line = t.line + st.delta; };
          moved = map shift out;
        in
        if out == [ ] then [ ]
        else [{
          inherit ((b.head moved)) line;
          inherit (st) file;
          toks = moved;
        }];

      stepAt = k: st0:
        let
          ts = groupAt k;
          isDirective = (b.head ts).kind == "#";
          st = b.seq (checkGlue ts) st0;
        in
        if isDirective then { key = k; st = directive st ts (here ts); out = [ ]; }
        else if !(live st) then { key = k; inherit st; out = [ ]; }
        else { key = k; inherit st; out = textLine st ts; };

      initial = { macros = { }; cond = [ ]; delta = 0; inherit file; };

      # One step per LOGICAL LINE, in a genericClosure: it is the only Nix
      # loop that can emit per step in linear time at constant stack depth
      # (decision-001). The item is deepSeq'd except for the macro table,
      # which is only `seq'd -- deep-forcing every macro once per source line
      # would be work proportional to lines times macros for nothing.
      #
      # WHY THAT IS SAFE, and it is not the reason you would guess. After the
      # `seq' the table is an attrset whose VALUES are still unforced
      # `deepSeq m m' thunks. What stops them becoming a chain as deep as the
      # loop is that a macro body closes over `groupAt k' -- over the single
      # shared token list `lexer.lex src' produced once -- and never over the
      # previous step's state. So an unforced macro value is a depth-1 thunk
      # however many steps have run. That invariant is what task-013.03 will
      # break the moment a macro body starts coming from an included file's
      # own token list, and it is the thing to re-check then.
      steps =
        if nLines == 0 then [ ]
        else b.genericClosure {
          startSet = [ (stepAt 0 initial) ];
          operator = it:
            if it.key + 1 >= nLines then [ ]
            else
              let x = stepAt (it.key + 1) it.st; in
              # Everything EXCEPT the macro table, by subtraction rather than
              # by naming the fields: an enumeration goes silently stale the
              # day a field is added, and decision-001 says the symptom of an
              # unforced field carried through a long loop is "stack
              # overflow", not a red test.
              b.deepSeq (b.removeAttrs x.st [ "macros" ]) (b.seq x.st.macros [ x ]);
        };

      final = if steps == [ ] then initial else (b.elemAt steps (b.length steps - 1)).st;
      lines = b.concatLists (map (it: it.out) steps);
      openFrame = if final.cond == [ ] then null else b.head final.cond;
    in
    if openFrame != null then
      throw "cpp: the file ends with ${toString (b.length final.cond)} conditional(s) still open; the innermost is the `#${openFrame.kind}' that has had no `#endif'"
    else {
      inherit lines;
      tokens = b.concatLists (map (l: l.toks) lines)
        ++ [ (if final.delta == 0 then eoi else eoi // { line = eoi.line + final.delta; }) ];
      # What the file ended up defining, so a harness can assert a `#undef'
      # removed something rather than trusting that nothing used it.
      macros = b.mapAttrs (_: m: map (t: t.text) m.body) final.macros;
    };

  # ---- text out, for the consumers that need text ------------------------
  # The token stream is the interface to poc/07-parser; this exists for the
  # two places that genuinely want characters -- the differential against
  # `gcc -E', and rcc, whose input.c resynch() is the thing acceptance
  # criterion #3 is about.
  #
  # ONE OUTPUT LINE PER RECORD, so the arithmetic is exact: rcc's `lineno'
  # advances by one per line it reads and a `# n "file"' sets it to n for the
  # line after the marker. Emit a marker whenever the presumed position is
  # not where rcc has got to, which is also the only correction needed after
  # a logical line that spanned several physical ones.
  #
  # A token is separated from the one before it by a single space unless it
  # had NO whitespace before it in the source. That is not cosmetic: lcc has
  # no compound-assignment tokens and its parser disambiguates `<<=' by
  # peeking at the raw next character (expr.c: `*cp != '=''), so rendering
  # `a <<= b' as `a << = b' would change what rcc parses.
  # No accumulator: each record renders as exactly one line, so whether it
  # needs a marker is a question about the record BEFORE it and nothing else.
  # An earlier version carried `{ at; file; out; }' through a `foldl'' with
  # `out ++ [ line ]', which is decision-001's quadratic trap -- affordable
  # here, and not worth spending a documented rule-break on when the same
  # output falls out of a `map'.
  render = r:
    let
      ls = r.lines;
      textOf = l: b.concatStringsSep ""
        (map (t: (if t.ws == "" then "" else " ") + t.text) l.toks);
      lineAt = i:
        let
          l = b.elemAt ls i;
          prev = if i == 0 then null else b.elemAt ls (i - 1);
          marker = prev == null || prev.file != l.file || prev.line + 1 != l.line;
        in
        (if marker then "# ${toString l.line} \"${l.file}\"\n" else "") + textOf l + "\n";
    in
    b.concatStringsSep "" (b.genList lineAt (b.length ls));

  tokensOf = args: (preprocess args).tokens;
in
{
  inherit preprocess render tokensOf expandList evalExpr resolveDefined;
  # Exported for the differential: the same compact form poc/02-lexer's
  # `brief' produces, so our token stream and a lexing of gcc's output are
  # compared as the same kind of value.
  inherit (lexer) brief;
}
