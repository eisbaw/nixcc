# A minimal C preprocessor in Nix: slices 1 and 2 of decision-005.
#
# Scope, and the reason it stops where it does (task-013.01, task-013.02):
# line splicing, object-like and function-like `#define' with the `#' and
# `##' operators, `#undef', the whole conditional family with
# constant-expression evaluation, `#line', and the `# n "file"' linemarkers
# lcc's input.c resynch() parses. `#include' is task-013.03 and waits on
# decision-010's header set. Every refusal below for something a later slice
# will do NAMES the slice's task.
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
# EXPANSION IS A WORKLIST, WHICH IS WHAT THE STANDARD'S RESCANNING WANTS.
# Slice 1 recursed once per nested macro, so its DEPTH tracked the length of
# the macro chain, which is bounded by the size of the file and by nothing
# else -- exactly what decision-001 bans (measured then: a chain of 3000
# expanded and one of 6000 died with "stack overflow; max-call-depth
# exceeded"). Slice 2 replaces it with the shape task-071 asked for: a cursor
# over the logical line plus a STACK OF FRAMES holding replacement lists still
# being rescanned, driven by one genericClosure step per token produced.
#
# The cursor advances PAST the invocation before it pushes the replacement,
# and a frame is popped the moment it is exhausted, so a chain `A -> B -> C'
# never stacks: the frame for B is pushed only after the frame for A has been
# emptied and dropped. A linear chain therefore runs at frame depth ONE
# however long it is, and the only thing that stacks is genuine nesting -- a
# replacement list that still has tokens left when one of its own tokens
# expands.
#
# THE BLUE PAINT IS PER TOKEN, NOT PER FRAME (C89 6.8.3.4: a macro is not
# re-expanded inside its own expansion). It has to be: a function-like
# macro's arguments come from the input, its body comes from the definition,
# and the two arrive carrying different hide sets. Measured against gcc:
# `#define F F' yields `F', `#define G H' with `#define H G' yields `G', and
# `#define SELF CAT(SE,LF)' yields `SELF' -- the last one only because the
# token `##' MANUFACTURES inherits the hide set of the expansion it was made
# in.
#
# AND `nest' IS A SECOND, UNCONDITIONAL COUNTER beside the hide set, which is
# not redundancy. The hide set is what makes expansion terminate; `nest' is
# what makes a BROKEN hide set terminate. With the hide set removed, `#define
# SELF SELF' has nothing left to stop it and the evaluator would spin forever
# -- a harness cannot mutation-test a hang. `nest' counts how many macros a
# token has been expanded THROUGH, so the symptom of a hide set that stopped
# hiding is MAX_NEST's diagnostic, which is a failure a test can see.
#
# THAT IS NOT THE SAME AS FRAME DEPTH, and the cap is on the counter and not
# on the stack. A chain `M0 -> M1 -> ... -> Mn' runs at frame depth one and
# still reaches `nest' = n, so MAX_NEST caps a chain at 200 exactly as slice
# 1's recursion did. What CHANGED is the failure mode behind it: measured
# with the cap lifted, slice 1 died at a chain of 6000 with "stack overflow;
# max-call-depth exceeded", and this expands it in 0.89 s. The cost is memory
# instead -- each level's hide set is the level before it plus one name, and
# copying it per level is O(n^2) bindings: 88 MB of peak RSS at 1000, 286 MB
# at 3000, 782 MB at 6000. So the cap is a MEMORY guard now, not a stack one,
# and task-071 is where removing it belongs.
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

  # WHAT DO TWO LEXEMES WRITTEN SIDE BY SIDE LEX AS?
  #
  # ONE primitive asks the lexer and THREE callers read its answer. That is
  # deliberate and it is load-bearing: slice 1 shipped a silent miscompile
  # here because two callers each had their own rule, and a character-class
  # rule would in any case have to be kept in step with the punctuator table.
  #
  #   `checkGlue' asks whether they STAY APART across a backslash-newline.
  #     ISO C splices in phase 2 and this lexer splices between tokens
  #     (task-008); the two disagree exactly when the characters on either
  #     side would have lexed as ONE token had the splice happened first.
  #   `render' asks the same of every boundary it writes with nothing between.
  #     In the SOURCE that is safe by construction, because the lexer cut the
  #     two apart there, but an expansion puts a token next to a neighbour it
  #     was never adjacent to -- `#define P +' used as `a P+ +2' is `a + + +2'
  #     and not `a ++ +2', which is a different program that also compiles.
  #   `pasteTok' asks the OPPOSITE question of the same lexing, because `##'
  #     exists precisely to make ONE token out of two. C89 6.8.3.3 leaves the
  #     result undefined when they do not join, so a paste that yields two
  #     tokens -- or none at all, because `/' and `*' open a comment -- is
  #     refused rather than emitted as a token stream nobody wrote.
  #
  # So `##' and `render' are the same question asked for opposite answers, and
  # having them share one lexing is what stops a paste that succeeds from
  # being re-split by the renderer, or one that failed from being silently
  # written out as two.
  #
  # `tryEval' is here because the joined text can fail to lex at all, which is
  # the strongest possible evidence that the two did not become one. Null, not
  # an empty list: a lexing that produced no tokens and a lexing that threw
  # are different answers and only one of them is a legal paste.
  # WHAT DOES THIS TEXT LEX AS? Null when it does not lex at all, and EOI is
  # dropped, so a caller counts the tokens it meant rather than the tokens
  # plus one. Every question below goes through this one call: two of them
  # ask about a joined pair and the third about a literal `#' built, and
  # having them answer with different conventions is how two rules that were
  # meant to be one drift apart.
  lexAll = text:
    let
      r = b.tryEval (
        let toks = b.filter (x: x.kind != "EOI") (lexer.lex text); in
        b.deepSeq toks toks);
    in
    if r.success then r.value else null;

  lexJoined = p: t: lexAll (p.text + t.text);

  staysApart = p: t:
    let r = lexJoined p t; in
    r != null
    && b.length r == 2
    && (b.head r).text == p.text
    && (b.elemAt r 1).text == t.text;

  # The `##' operator. `use' is the invocation site, so the manufactured token
  # points at the code the reader wrote rather than at the `#define'.
  pasteTok = use: p: t:
    let r = lexJoined p t; in
    # The result occupies the LEFT operand's position, so it takes the left
    # operand's boundary rather than `mkTok's default space. Without that,
    # `#define F(p,q) Q(z+p##q)' stringifies `F(f,oo)' to "z+ foo".
    if r != null && b.length r == 1
    then mkTok use ({ inherit ((b.head r)) kind text; } // preOf p)
    else throw "cpp: line ${toString use.line}: `##' in the expansion of `${
      use.text}' pastes `${p.text}' and `${t.text}', and `${p.text}${t.text}' is ${
      if r == null then "not a preprocessing token at all"
      else "${toString (b.length r)} preprocessing tokens"}, not one. C89 6.8.3.3 leaves that undefined, so it is refused rather than emitted as a token stream nobody wrote";

  # The `#' operator. C89 6.8.3.2: the argument's tokens in the spelling they
  # were WRITTEN in -- not the spelling they expand to -- separated by one
  # space wherever there was any whitespace between them and by nothing where
  # there was none, with no space at either end, and with a `\' inserted
  # before every `"' and `\' that occurs inside a string or character literal.
  #
  # A comment counts as whitespace and therefore as one space, which falls out
  # of `ws' rather than needing a rule: poc/02-lexer puts the comment in the
  # token's trivia, so `ws != ""'.
  isCharConst = t: t.kind == "ICON" && (b.substring 0 1 t.text == "'" || b.substring 0 2 t.text == "L'");
  spell = t:
    if t.kind == "SCON" || isCharConst t
    then b.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] t.text
    else t.text;

  stringifyToks = use: ts:
    let
      piece = j:
        let t = b.elemAt ts j; in
        (if j != 0 && separates t then " " else "") + spell t;
      text = "\"" + b.concatStringsSep "" (b.genList piece (b.length ts)) + "\"";
      # The result has to BE a string literal, not merely look like one. This
      # is the same argument `pasteTok' makes, asked of the same `lexAll' --
      # a manufactured token that the lexer would read as something else is a
      # miscompile that nothing downstream can attribute. Cheap, because `#'
      # is rare.
      r = lexAll text;
    in
    if r != null && b.length r == 1 && (b.head r).kind == "SCON"
    then mkTok use { kind = "SCON"; inherit text; }
    else throw "cpp: line ${toString use.line}: `#' in the expansion of `${
      use.text}' would stringify its argument to ${text}, which is not a string literal";

  # ---- WHO OWNS A BOUNDARY -------------------------------------------------
  #
  # A cross-model review found FOUR wrong string literals in one family, and
  # they were four answers to one question asked in four places: when a token
  # is substituted for something else, whose whitespace does the result carry?
  # The rule that covers all four is
  #
  #     TRIVIA BELONGS TO THE POSITION, NOT TO THE TOKEN.
  #
  # A replacement list occupies the position its invocation had; an argument
  # occupies the position its parameter had; a token `##' or `#' manufactures
  # occupies the position of the first token it replaced. In every one of
  # those the SEQUENCE that arrives takes the boundary of what it replaced,
  # and its own first token's boundary is discarded -- C89 6.8.3 says the
  # whitespace before the first token of a replacement list is not part of the
  # list, and 6.8.3.2 says the same of an argument in as many words ("white
  # space before the first preprocessing token ... composing the argument is
  # deleted"). So the plan carries a `pre' per element and the tokens carry
  # none, which is the same move `staysApart' made for the other boundary
  # question: one answer, one place.
  #
  # A DELETED ELEMENT DOES NOT DELETE ITS BOUNDARY. `#define G(x) Q(a x+b)'
  # invoked as `G()' stringifies to "a +b" and not "a+b": `x' went away and
  # the space in front of it did not, because the space is the boundary
  # between `a' and whatever comes next. That is what `mergePre' carries
  # forward and why the walk over a replacement list is a scan rather than a
  # map.
  #
  # `glue' RIDES ALONG BECAUSE IT IS NOT WHITESPACE. ISO C's phase 2 removes a
  # backslash-newline WITHOUT putting a space in its place, so `Q(a\<newline>+b)'
  # is "a+b". poc/02-lexer already distinguishes that trivia with its `glue'
  # flag -- "a continuation and nothing else" -- and the flag has to survive
  # substitution for `#' to be able to read it. That one is a separate fact
  # from the ownership rule above: it is about what whitespace IS, not about
  # whose it is.
  noPre = { ws = ""; glue = false; };
  preOf = t: { inherit (t) ws glue; };
  setPre = pre: t: t // { inherit (pre) ws glue; };

  # The boundary a deleted element leaves behind, joined to the next one.
  # Whitespace if either side had any; a splice only if BOTH were, since one
  # real space makes the whole boundary real.
  mergePre = a: c:
    if a.ws == "" then c
    else if c.ws == "" then a
    else { ws = a.ws + c.ws; glue = a.glue && c.glue; };

  # Whether a boundary separates two tokens for the purposes of `#'.
  separates = t: t.ws != "" && !t.glue;

  # Whether a token could be a macro invocation. `macros ? ${t.text}' alone
  # would be enough -- every macro name is an identifier, and no punctuator,
  # number or literal lexeme spells one -- but this states the reason rather
  # than relying on it silently.
  invokes = macros: t: macros ? ${t.text};

  # ---- macro expansion ---------------------------------------------------
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
  #   `ws'    is one space, and it is a PLACEHOLDER: every token that leaves
  #           a replacement list has its boundary written by `substituted'
  #           from the plan's `pre', because trivia belongs to the position
  #           and not to the token (see "who owns a boundary" above). The
  #           default survives only where nothing replaced anything, and what
  #           it used to defend -- an expansion pasting against its
  #           neighbour, `#define P +' in `a+P b' rendering as `a++ b' --
  #           `render' now defends at every boundary it writes, through
  #           `staysApart'.
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

  # NO `ws' HERE ON PURPOSE. A body token's boundary is carried by its plan
  # element's `pre', which is the same value -- except for the FIRST token of
  # a replacement list, whose leading whitespace is not part of the list at
  # all. Copying it here as well would be a second answer to the ownership
  # question, and `#define V 7' used in `a+V' would render as `a+ 7'.
  fromBody = use: bt: mkTok use { inherit (bt) kind text; };

  # ---- the replacement list, compiled once at `#define' time ---------------
  #
  # A replacement list stops being a flat token list the moment `#' and `##'
  # are in it, and working that out at every INVOCATION would be work
  # proportional to USES rather than to definitions. So it is compiled once
  # into two pieces:
  #
  #   elems   a flat list of elements, each one of
  #             { what = "tok"; tok; }   a literal token of the replacement
  #             { what = "arg"; idx; }   a parameter
  #             { what = "str"; idx; }   `#' applied to a parameter
  #   starts  the index in `elems' where each PASTE CHAIN begins. `a##b##c' is
  #           one chain of three and pastes left to right, as C89 6.8.3.3
  #           says; an element with no `##' beside it is a chain of one.
  #
  # Chains rather than a flag per element, because whether a parameter is
  # macro-expanded before it is substituted depends on the whole chain: C89
  # 6.8.3.1 expands an argument first EXCEPT where it is an operand of `#' or
  # `##', and "operand of ##" means "in a chain of more than one".
  #
  # `##' arrives as two `#' tokens with nothing between them, because
  # poc/02-lexer has no `##' punctuator -- `#' is the preprocessor's operator
  # and the lexer leaves it alone.
  planOf = name: paramIx: objectLike: body: dline:
    let
      n = b.length body;
      at = i: b.elemAt body i;
      bad = msg: throw "cpp: line ${toString dline}: ${msg}";
      isHash = i: i < n && (at i).kind == "#";
      # `glue' as well as an empty `ws', for the same reason `funcLike' below
      # tests both: adjacency is adjacency AFTER ISO C's phase 2, and
      # `a#\<newline>#b' is `a##b' once the splice is gone. Without the
      # second clause that is not a paste at all, and the diagnostic it earns
      # -- "`#' is followed by `#', which is not one of its parameters" --
      # calls a valid replacement list malformed, which is worse than doing
      # nothing. `glue' is exactly "the trivia is a continuation and nothing
      # else" (task-008).
      isPaste = i: isHash i && isHash (i + 1)
        && ((at (i + 1)).ws == "" || (at (i + 1)).glue);

      # One element, starting at i. `entryAt' calls it past a `##', so it CAN
      # land on a second one -- and that is malformed input rather than the
      # deliberate divergence task-078 records, so it says so itself instead
      # of falling into the object-like arm below and pointing the reader at
      # a backlog item about a case gcc accepts.
      elemFrom = i:
        let t = at i; in
        if isPaste i then
          bad "two `##' in a row in the replacement list of `${name}'; C89 6.8.3.3 wants an operand between them"
        else if t.kind == "#" && objectLike then
          bad "`#' in the replacement list of `${name}': stringify takes a PARAMETER and an object-like macro has none. gcc passes the `#' through as an ordinary token; this preprocessor refuses it, because a `#' that reached the parser is reported there as unpreprocessed input and points the reader at the wrong stage entirely (task-078)"
        else if t.kind == "#" then
          (if i + 1 < n && paramIx ? ${(at (i + 1)).text} then
            { elem = { what = "str"; idx = paramIx.${(at (i + 1)).text}; }; next = i + 2; }
          else
            bad "`#' in the replacement list of `${name}' is followed by `${
              if i + 1 < n then (at (i + 1)).text else "the end of the line"
            }', which is not one of its parameters; C89 6.8.3.2 gives `#' a meaning only in front of a parameter name")
        else if paramIx ? ${t.text} then
          { elem = { what = "arg"; idx = paramIx.${t.text}; }; next = i + 1; }
        else { elem = { what = "tok"; tok = t; }; next = i + 1; };

      # One plan entry: the `##' in front of it, if there is one, and the
      # element after it. genericClosure rather than a walk because the stride
      # is one token or three, and the depth of a recursive walk would track
      # the length of the replacement list (decision-001).
      #
      # `pre' is the boundary written in FRONT of the element, and it is the
      # element's own rather than its token's because a parameter's token is
      # replaced by an argument and a `#' by a literal. The FIRST element has
      # none: C89 6.8.3 says the whitespace before the first token of a
      # replacement list is not part of the list, so what goes there is the
      # boundary of the invocation the list replaced.
      entryAt = i:
        if isPaste i then
          (if i == 0 then
            bad "the replacement list of `${name}' begins with `##', which C89 6.8.3.3 wants an operand on each side of"
          else if i + 2 >= n then
            bad "the replacement list of `${name}' ends with `##', which C89 6.8.3.3 wants an operand on each side of"
          else let e = elemFrom (i + 2); in
            { key = i; inherit (e) next elem; pasted = true; pre = preOf (at (i + 2)); })
        else let e = elemFrom i; in
          { key = i; inherit (e) next elem; pasted = false;
            pre = if i == 0 then noPre else preOf (at i); };

      entries =
        if n == 0 then [ ]
        else b.genericClosure {
          startSet = [ (entryAt 0) ];
          operator = it: if it.next >= n then [ ] else let x = entryAt it.next; in b.deepSeq x [ x ];
        };
    in
    {
      elems = map (e: e.elem // { inherit (e) pre; }) entries;
      starts = b.filter (j: !(b.elemAt entries j).pasted)
        (b.genList (i: i) (b.length entries));
    };

  # ---- expansion, as a worklist -------------------------------------------
  #
  # An ITEM is a token plus the two things carried beside it: `hide', the set
  # of macro names it must not be re-expanded as, and `nest', how many frames
  # deep it was manufactured. `more' says whether there is input after this
  # list that a function-like macro's argument list could have opened into;
  # `depth' counts nested ARGUMENT expansions, which is the one place this
  # still recurses.
  expandItems = macros: depth: more: src:
    let
      nSrc = b.length src;

      # THE CURSOR: a position in `src' plus a stack of frames, each frame a
      # replacement list still being rescanned. The head of the stack is the
      # innermost, and the invariant `settle' keeps is that no frame on it is
      # exhausted -- which is what makes a linear chain run at depth one,
      # because the frame a macro came from is dropped before the frame its
      # expansion pushes.
      #
      # `settle' is the one recursion left in the cursor, and its depth is the
      # number of frames that ran out AT ONCE -- which is the nesting the
      # `nest' counter caps at MAX_NEST, not the length of anything.
      settle = stack:
        if stack == [ ] then [ ]
        else let f = b.head stack; in if f.j < f.n then stack else settle (b.tail stack);

      peek = st:
        if st.stack != [ ] then let f = b.head st.stack; in b.elemAt f.items f.j
        else if st.i < nSrc then b.elemAt src st.i
        else null;

      bump = st:
        if st.stack == [ ] then st // { i = st.i + 1; }
        else
          let f = b.head st.stack; in
          st // { stack = settle ([ (f // { j = f.j + 1; }) ] ++ b.tail st.stack); };

      pushFrame = st: items:
        if items == [ ] then st
        else st // { stack = [{ inherit items; j = 0; n = b.length items; }] ++ st.stack; };

      # Force the numbers that CHAIN from one step to the next, and nothing
      # else. A `deepSeq' of the cursor would walk every token of every live
      # frame once per step, which is decision-001's quadratic trap wearing a
      # different hat; leaving them unforced is its other one, a thunk chain
      # as deep as the loop.
      forceCur = st: b.seq st.i (b.foldl' (a: f: b.seq f.j a) true st.stack);

      # And the three fields every worklist item has, NAMED rather than taken
      # by subtraction. `deepSeq (removeAttrs x [ "st" ])' is the usual
      # spelling in this tree and it allocates a copy of the item once per
      # token of every line that names a macro. The enumeration is safe here
      # in a way it is not elsewhere because there are exactly two builders,
      # `mk' and `gstep', both within a screen of this -- and `gstep' adds
      # `depth' and `arg', which CHAIN and which its own operator forces
      # beside this call rather than leaving to it.
      forceStep = x: k: b.seq x.key (b.seq x.done (b.deepSeq x.out k));

      # --- one invocation's argument list ---------------------------------
      # Called with the cursor ON the `('. Counts parentheses and splits on
      # commas at depth one, so a comma INSIDE parentheses belongs to the
      # argument it is in -- which is what makes `M((1,2),3)' two arguments
      # rather than three.
      gather = use: st0:
        let
          gstep = s:
            let cur = peek s.st; in
            if cur == null then
              throw "cpp: line ${toString use.line}: the invocation of `${use.text}' opens an argument list that is not closed on this logical line. poc/08-cpp expands one logical line at a time, so an invocation whose `)' is on the next line is refused rather than mis-split; task-077"
            else
              let
                k = cur.tok.kind;
                nx = bump s.st;
              in
              if k == ")" && s.depth == 1 then
                { key = s.key + 1; st = nx; inherit (s) depth arg; out = [ ]; done = true; }
              else if k == "," && s.depth == 1 then
                { key = s.key + 1; st = nx; inherit (s) depth; arg = s.arg + 1; out = [ ]; done = false; }
              else {
                key = s.key + 1;
                st = nx;
                depth = if k == "(" then s.depth + 1 else if k == ")" then s.depth - 1 else s.depth;
                inherit (s) arg;
                out = [ (cur // { inherit (s) arg; }) ];
                done = false;
              };

          steps = b.genericClosure {
            startSet = [{ key = 0; st = bump st0; depth = 1; arg = 0; out = [ ]; done = false; }];
            operator = it:
              if it.done then [ ]
              else
                let x = gstep it; in
                # `depth' and `arg' as well, because both CHAIN from one
                # gather step to the next and an unforced chain as deep as
                # the argument list is decision-001's other trap.
                b.seq (forceCur x.st)
                  (b.seq x.depth (b.seq x.arg (forceStep x [ x ])));
          };
          last = b.elemAt steps (b.length steps - 1);
          collected = b.concatLists (map (it: it.out) steps);
          sections = last.arg + 1;
        in
        {
          inherit (last) st;
          # `F()' is ONE empty argument to a one-parameter macro and NO
          # arguments to a parameterless one. Nothing in the token stream
          # tells those apart, so the caller decides with the parameter list
          # in hand.
          empty = sections == 1 && collected == [ ];
          args = b.genList (g: b.filter (x: x.arg == g) collected) sections;
        };

      # --- substitution ---------------------------------------------------
      # `h' is the hide set every token of the replacement carries: the
      # invocation token's own, plus this macro's name. It applies to the
      # ARGUMENT tokens too, unioned with whatever paint they already had,
      # because an argument can arrive from inside another expansion.
      substituted = use: h: lvl: m: args:
        let
          nCh = b.length m.plan.starts;
          nEl = b.length m.plan.elems;
          paint = x: {
            inherit (x) tok;
            hide = x.hide // h;
            nest = if x.nest > lvl then x.nest else lvl;
          };
          born = t: { tok = t; hide = h; nest = lvl; };
          rawArg = g: map paint (b.elemAt args g);
          expArg = g: map paint (expandItems macros (depth + 1) false (b.elemAt args g));

          # C89 6.8.3.1: an argument is macro-expanded before it is
          # substituted, EXCEPT where it is an operand of `#' or `##'. `#'
          # takes the raw tokens by construction -- it stringifies what was
          # WRITTEN -- and a parameter in a chain of more than one element is
          # a `##' operand. Both forms are computed here and Nix's laziness
          # means the one that is not used costs nothing.
          seqOf = solo: e:
            if e.what == "tok" then [ (born (fromBody use e.tok)) ]
            else if e.what == "str" then
              [ (born (stringifyToks use (map (x: x.tok) (b.elemAt args e.idx)))) ]
            else if solo then expArg e.idx
            else rawArg e.idx;

          # An operand that is an empty argument keeps the other side and
          # pastes nothing -- the standard's placemarker, which `CAT(A,)'
          # needs and which falls out of the empty list rather than needing a
          # token to stand for it.
          joinTo = left: right:
            if left == [ ] then right
            else if right == [ ] then left
            else
              let
                lp = b.elemAt left (b.length left - 1);
                rp = b.head right;
              in
              b.genList (j: b.elemAt left j) (b.length left - 1)
              ++ [{
                tok = pasteTok use lp.tok rp.tok;
                # THE INTERSECTION OF THE TWO OPERANDS' PAINT, not the
                # union, and the difference decides which arm a `#if' takes.
                # C89 6.8.3.4's rule -- Prosser's `glue', which gives the
                # pasted token HS(left) INTERSECT HS(right) -- exists because
                # a name that only ONE operand was forbidden to be is not a
                # name the RESULT was forbidden to be. Measured, with the
                # union:
                #
                #   #define AB 1+A
                #   #define CAT(a,b) a##b
                #   #define EXP(a,b) CAT(a,b)
                #   #if EXP(AB,B) == 2
                #
                # `A' arrives from expanding AB and carries {AB}; `B' comes
                # from the source and does not. Union the two and the pasted
                # `AB' is hidden, we emit `1+AB', the leftover identifier is
                # 0, and the `#if' is FALSE where gcc's is TRUE. That is a
                # silent choice of the other arm, not a loud refusal.
                #
                # `h' is unioned in afterwards, as `hsadd' does, and is a
                # no-op here only because `paint' already put it on both
                # operands -- writing it is what keeps the composition
                # readable rather than incidental.
                #
                # What the intersection does NOT weaken: `#define SELF
                # CAT(SE,LF)' still comes out as `SELF', because both
                # operands came out of SELF's own expansion and so both carry
                # it. The paint is otherwise ordinary and the token IS
                # rescanned -- C89 6.8.3.3, "the resulting token is available
                # for further macro replacement", which lcc/cpp/macro.c
                # implements by backing its row up over what doconcat()
                # inserted, and which gcc demonstrates by turning `CAT(X,Y)'
                # into 42 given `#define XY 42'.
                hide = (b.intersectAttrs lp.hide rp.hide) // h;
                nest = lvl;
              }]
              ++ b.tail right;

          # A DECLARED RULE-BREAK: this is `foldl'' accumulating a list with
          # `++', which decision-001 bans and which `render' below boasts of
          # having removed. It is bounded by the length of ONE PASTE CHAIN in
          # ONE DEFINITION -- `a##b##c' is three -- and never by the size of
          # the input, so the quadratic term is over a constant the author of
          # the `#define' chose. Written as a fold because a paste has to see
          # the sequence to its left, which is the accumulator.
          chain = c:
            let
              from = b.elemAt m.plan.starts c;
              to = if c + 1 < nCh then b.elemAt m.plan.starts (c + 1) else nEl;
              solo = to - from == 1;
              one = j: seqOf solo (b.elemAt m.plan.elems j);
            in
            if solo then one from
            else b.foldl' (acc: j: joinTo acc (one j)) (one from)
              (b.genList (j: from + 1 + j) (to - from - 1));

          # THE BOUNDARY WALK. One step per paste chain, carrying the
          # boundary that has yet to be placed: a chain that produced nothing
          # -- an empty argument, or a paste of two empty ones -- hands its
          # boundary to the next rather than taking it out of the output with
          # it. The walk starts from the INVOCATION's own boundary, which is
          # what the first token of the replacement inherits.
          #
          # genericClosure rather than a fold, for the reason every other loop
          # in this file is one: it emits per step, and a `foldl'' would have
          # to accumulate the output with `++'.
          chainAt = c: pending:
            let
              seq = chain c;
              eff = mergePre pending (b.elemAt m.plan.elems (b.elemAt m.plan.starts c)).pre;
            in
            if seq == [ ]
            then { key = c; pending = eff; out = [ ]; }
            else {
              key = c;
              pending = noPre;
              out = [ (let x = b.head seq; in x // { tok = setPre eff x.tok; }) ]
                ++ b.tail seq;
            };

          steps = b.genericClosure {
            startSet = [ (chainAt 0 (preOf use)) ];
            operator = it:
              if it.key + 1 >= nCh then [ ]
              else let x = chainAt (it.key + 1) it.pending; in b.deepSeq x [ x ];
          };
        in
        if nCh == 0 then [ ] else b.concatLists (map (it: it.out) steps);

      # --- one step: one token consumed, zero or one emitted ---------------
      advance = cur: st:
        let t = cur.tok; in
        if !(invokes macros t) || cur.hide ? ${t.text} then { st = bump st; out = [ cur ]; }
        else if cur.nest >= MAX_NEST then
          throw "cpp: macro `${t.text}' on line ${toString t.line} is nested more than ${
            toString MAX_NEST} macros deep. The cap is memory rather than stack: each level's hide set is the level before it plus one name, so copying it per level costs O(n^2) bindings -- measured with the cap lifted, a chain of 1000 peaks at 88 MB, 3000 at 286 MB and 6000 at 782 MB. It does EXPAND, which slice 1's recursion did not; see task-071"
        else
          let
            m = macros.${t.text};
            h = cur.hide // { ${t.text} = true; };
            lvl = cur.nest + 1;
            adv = bump st;
          in
          if m.params == null then
            { st = pushFrame adv (substituted t h lvl m [ ]); out = [ ]; }
          else
            # THE `(' IS TESTED ON THE RAW NEXT TOKEN, never on what that
            # token would expand to. Measured against gcc: with `#define LP
            # (', `F LP 3 )' is NOT an invocation and comes out as `F ( 3 )'.
            # It may still come from a FRAME rather than from the source --
            # with `#define G F', `G (9)' IS an invocation, and gcc agrees --
            # which is why the cursor spans both and this peek is not a
            # lookahead into `src'.
            let nxt = peek adv; in
            if nxt == null then
              (if more then
                throw "cpp: line ${toString t.line}: the function-like macro `${t.text}' is the last token on its logical line, so whether the line after it opens an argument list cannot be decided here. poc/08-cpp expands one logical line at a time; task-077"
              else { st = adv; out = [ cur ]; })
            else if nxt.tok.kind != "(" then { st = adv; out = [ cur ]; }
            else
              let
                g = gather t adv;
                want = b.length m.params;
                args = if g.empty && want == 0 then [ ] else g.args;
              in
              if b.length args != want then
                throw "cpp: line ${toString t.line}: `${t.text}' was defined on line ${
                  toString m.line} with ${toString want} parameter(s) and is invoked with ${
                  toString (b.length args)} argument(s)"
              else { st = pushFrame g.st (substituted t h lvl m args); out = [ ]; };

      mk = k: st:
        let cur = peek st; in
        if cur == null then { key = k; inherit st; out = [ ]; done = true; }
        else let r = advance cur st; in { key = k; inherit (r) st out; done = false; };

      steps = b.genericClosure {
        startSet = [ (mk 0 { stack = [ ]; i = 0; }) ];
        operator = it:
          if it.done then [ ]
          else
            let x = mk (it.key + 1) it.st; in
            b.seq (forceCur x.st) (forceStep x [ x ]);
      };
    in
    if depth > MAX_NEST then
      throw "cpp: a macro argument is expanded more than ${toString MAX_NEST} levels deep. Expanding an argument before it is substituted is the one place expansion still recurses, one evaluator frame per level (decision-001); see task-071"
    else if nSrc == 0 then [ ]
    # A LIST WITH NO MACRO NAME IN IT IS ITS OWN ANSWER. The worklist
    # allocates a cursor, a step item and an output list per token, and most
    # lines of C name no macro at all, so this is worth having -- measured on
    # memory.py's ladder input at 800 functions it is 312868 kB of peak RSS
    # against 324544 kB, about 4%. It is not worth more than that, and
    # task-079 carries what would be: batching a macro-free RUN inside a line
    # that does name one. `invokes' rather than a second membership rule, so
    # the fast path and the slow one cannot come to different conclusions
    # about what a macro name is.
    # The same test `expandList' makes before it wraps anything, and both are
    # wanted: the outer one saves the WRAPPING for a line that names no macro,
    # and this one is what `expArg' reaches, since an argument arrives
    # already wrapped. The cost of having both is one attrset-membership test
    # per token of a line that does name one.
    else if !(b.any (x: invokes macros x.tok) src) then src
    else b.concatLists (map (it: it.out) steps);

  expandList = macros: more: ts:
    if !(b.any (invokes macros) ts) then ts
    else
      map (x: x.tok)
        (expandItems macros 0 more (map (t: { tok = t; hide = { }; nest = 0; }) ts));

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
      # function that combines two values.
      #
      # `go' is a loop written as a tail call, and Nix does not eliminate it,
      # so the depth here tracks the number of OPERATORS rather than the
      # nesting -- which is NOT the exemption decision-001 grants recursive
      # descent, whatever an earlier version of this comment claimed. A `#if'
      # of 3000 flat `+' terms dies with "stack overflow; max-call-depth
      # exceeded". task-074 carries it, and the same shape is in `logand',
      # `logor', `conditional' and in `unary', which recurses once per PREFIX
      # operator so that `#if ---...-0' tracks input length just as `+' does.
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

      # A `glue' token has a predecessor inside its own group, with ONE
      # exception this does not handle: trivia made only of continuations
      # contains no line-ending newline, so such a token is never the first
      # on a logical line -- except the file's FIRST token, whose `bol' does
      # not come from its trivia at all. A file opening with a
      # backslash-newline therefore reaches `elemAt ts (i - 1)' with i = 0
      # and dies with an index error instead of a diagnostic. task-073.
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
      # wrong for a different reason. It is left as it is here because nobody
      # writes four thousand defines by hand -- and slice 2 made each entry
      # BIGGER, with a parameter list and a compiled replacement plan, which
      # moved the 2000-macro point from 37 MB to 40. task-013.03 is
      # `#include', and one real header chain is a four-figure macro count.
      defineIn = st: ts: dline:
        let
          nameTok = if ts == [ ] then throw "cpp: line ${toString dline}: `#define' with no macro name" else b.head ts;
          name = nameTok.text;
          all = b.tail ts;
          first = b.head all;
          sameSpelling = xs: ys:
            b.length xs == b.length ys
            && b.all (i:
              let x = b.elemAt xs i; y = b.elemAt ys i; in
              x.text == y.text && (x.ws == "") == (y.ws == ""))
              (b.genList (i: i) (b.length xs));

          # WHAT MAKES A MACRO FUNCTION-LIKE is the `(' being ADJACENT to the
          # name, C89 6.8.3: `#define F(x) x' takes a parameter and
          # `#define F (x) x' is an object-like macro whose body starts with a
          # parenthesis. `first.glue' as well as an empty `ws', because
          # `#define F\<newline>(x) x' is adjacent after ISO C's phase 2 and
          # its `(' carries the splice as its trivia rather than nothing at
          # all -- `glue' is exactly "the trivia is a continuation and nothing
          # else" (task-008).
          funcLike = all != [ ] && first.kind == "(" && (first.ws == "" || first.glue);

          # A parameter list holds identifiers and commas and nothing else, so
          # the FIRST `)' ends it: there is nothing that could nest inside
          # one. A malformed list is caught by the shape check below rather
          # than by the search, which is why the search can be this simple.
          closes = b.filter (j: (b.elemAt all j).kind == ")")
            (b.genList (i: i) (b.length all));
          pClose = if closes == [ ] then 0 else b.head closes;
          pToks = b.genList (j: b.elemAt all (j + 1)) (if pClose > 0 then pClose - 1 else 0);
          nP = b.length pToks;
          # Identifiers at the even positions, commas at the odd ones, and an
          # odd number of tokens -- which rejects `(a,)' and `(a b)' together.
          # A parameter may be spelled like a keyword: to the preprocessor
          # `int' is an identifier, so this tests TEXT and not `kind'.
          shapeOk =
            (nP == 0 || b.bitAnd nP 1 == 1)
            && b.all
              (j: let t = b.elemAt pToks j; in
                if b.bitAnd j 1 == 0 then isIdent t.text else t.kind == ",")
              (b.genList (i: i) nP);
          params = b.genList (j: (b.elemAt pToks (2 * j)).text) ((nP + 1) / 2);
          dupes = b.filter
            (j: b.elem (b.elemAt params j) (b.genList (k: b.elemAt params k) j))
            (b.genList (i: i) (b.length params));
          paramIx = b.listToAttrs
            (b.genList (j: { name = b.elemAt params j; value = j; }) (b.length params));

          body =
            if funcLike
            then b.genList (j: b.elemAt all (pClose + 1 + j)) (b.length all - pClose - 1)
            else all;
          myParams = if funcLike then params else null;
          prev = st.macros.${name} or null;
          m = {
            inherit name body;
            params = myParams;
            line = dline;
            plan = planOf name (if funcLike then paramIx else { }) (!funcLike) body dline;
          };
        in
        if !(isIdent name) then
          throw "cpp: line ${toString dline}: `${name}' is not a macro name; `#define' takes an identifier"
        # C89 forbids it by name, and for a reason this file would feel:
        # `defined' is resolved before expansion, so a macro of that name is
        # silently never used.
        else if name == "defined" then
          throw "cpp: line ${toString dline}: `defined' cannot be a macro name; it is the operator a `#if' expression uses to ask whether a name is defined"
        else if funcLike && closes == [ ] then
          throw "cpp: line ${toString dline}: the parameter list of `${name}(' is never closed; `#define' wants a `)' before the replacement list"
        else if funcLike && !shapeOk then
          throw "cpp: line ${toString dline}: the parameter list of `${name}(' is not a list of identifiers separated by commas"
        else if funcLike && dupes != [ ] then
          throw "cpp: line ${toString dline}: `${name}(' names the parameter `${
            b.elemAt params (b.head dupes)}' twice, and a substitution could not say which one it meant"
        # C89 6.8.3 says a redefinition SHALL be identical. gcc makes that a
        # warning and takes the new body; there is no warning channel here,
        # and a body that quietly changed under a second `#define' is the
        # kind of thing that is found three stages later, so it is refused.
        #
        # THE PARAMETER LIST IS HALF OF "IDENTICAL", and it gets its own
        # sentence rather than being folded into the one below: `#define
        # F(a,b) a' and `#define F(a,c) a' have the same replacement list
        # spelled the same way and are still two different macros, and a
        # diagnostic that said "a different replacement list" about a pair of
        # identical replacement lists would send the reader looking at the
        # wrong half of the line. It is also the only thing that TESTS the
        # comparison: with one message for both, a check that stopped
        # comparing parameters would be indistinguishable from one that
        # stopped comparing bodies.
        else if prev != null && prev.params != myParams then
          throw "cpp: line ${toString dline}: `${name}' is redefined with a different parameter list; it was defined on line ${toString prev.line}, and C89 6.8.3 requires a redefinition to be identical. `#undef' it first"
        else if prev != null && !(sameSpelling prev.body body) then
          throw "cpp: line ${toString dline}: `${name}' is redefined with a different replacement list; it was defined on line ${toString prev.line}, and C89 6.8.3 requires a redefinition to be identical. `#undef' it first"
        # THE PLAN IS FORCED HERE, not left for the first invocation. `##' at
        # either end of a replacement list, and a `#' with no parameter after
        # it, are constraint violations of the `#define' itself: gcc reports
        # them at the definition whether or not the macro is ever used, and a
        # macro that is defined wrongly and never invoked would otherwise go
        # through in silence. The cost is one forcing per `#define', which is
        # what the table's own `deepSeq' would have paid on first lookup.
        else b.seq (b.deepSeq m.plan true)
          (st // { macros = st.macros // { ${name} = b.deepSeq m m; }; });

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
          expanded = expandList st.macros false ts;
          numTok = if expanded == [ ] then throw "cpp: line ${toString dline}: `${what}' with no line number" else b.head expanded;
          rest = b.tail expanded;
          nameTok = b.head rest;
          # task-075: evalICON reads the C SPELLING, so `#line 010' is octal
          # 8 here and decimal 10 to gcc and to lcc's resynch(). The standard
          # takes a digit sequence, which is decimal whatever it starts with.
          # The overflow check below is what this call is still wanted for.
          # Bound ONCE: this used to be two separate `const.evalICON' calls on
          # the same text, one for the value and one for the warnings.
          icon = const.evalICON numTok.text;
          num = icon.value;
          numWarnings = icon.warnings;
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
          # task-076: the last TOKEN's line, which is not the directive's
          # last physical line when trivia after the operands spans one -- a
          # block comment opened on the directive's line and closed on the
          # next puts everything after it one line early.
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
          push st (!skipping && evalExpr (zeroIdents (expandList st.macros false (resolveDefined st.macros args))) dline)
        else if what == "elif" then
          if frame.kind == "else" then throw "cpp: line ${toString dline}: `#elif' after `#else'"
          else
            let
              take = frame.parentActive && !frame.taken
                && evalExpr (zeroIdents (expandList st.macros false (resolveDefined st.macros args))) dline;
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
          throw "cpp: line ${toString dline}: `#include' is task-013.03. decision-010 settled where a header comes from -- the C89 freestanding set, carried in this repository so the path is flake-relative and a `nix flake check' needs no --impure -- but the directive itself is not written yet"
        else
          throw "cpp: line ${toString dline}: `#${what}' is not a directive this preprocessor implements. What it does is #define/#undef/#if/#ifdef/#ifndef/#elif/#else/#endif/#line; what the minimal preprocessor deliberately leaves out is tracked in task-014";

      # `more' says whether the line after this one could open an argument
      # list that this one left unclosed. A function-like macro name at the
      # very end of a line is an ordinary identifier unless the next line
      # begins with `(', and this stage expands one logical line at a time, so
      # THAT case -- and only that case -- is refused naming task-077 rather
      # than quietly taking the first answer and compiling `y = F (1)' as a
      # call. Two things narrow it, and both are one `elemAt': a directive
      # does not count, because a directive ends any invocation, and a next
      # line that does not START with `(' cannot be opening one.
      textLine = st: ts: more:
        let
          out = expandList st.macros more ts;
          shift = t: if st.delta == 0 then t else t // { line = t.line + st.delta; };
          moved = map shift out;
        in
        if out == [ ] then [ ]
        else [{
          inherit ((b.head moved)) line;
          inherit (st) file;
          toks = moved;
        }];

      firstKindOf = k: (code (b.elemAt starts k)).kind;

      stepAt = k: st0:
        let
          ts = groupAt k;
          isDirective = (b.head ts).kind == "#";
          st = b.seq (checkGlue ts) st0;
        in
        if isDirective then { key = k; st = directive st ts (here ts); out = [ ]; }
        else if !(live st) then { key = k; inherit st; out = [ ]; }
        else { key = k; inherit st; out = textLine st ts (k + 1 < nLines && firstKindOf (k + 1) == "("); };

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
      # removed something rather than trusting that nothing used it. The
      # PARAMETER LIST is part of that: a function-like macro whose parameters
      # were dropped is still a macro with the right body, and the token
      # stream only notices once something invokes it.
      macros = b.mapAttrs
        (_: m: { inherit (m) params; body = map (t: t.text) m.body; })
        final.macros;
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
      # A token that had whitespace before it in the source gets one space;
      # a token that had none gets none -- unless writing it there would
      # change what the text lexes as. That last clause is not cosmetic:
      # `#define P +' used as `a P+ +2' puts the expansion's `+' next to an
      # original `+' whose `ws' is empty, and `a ++ +2' is a program that
      # compiles and increments `a', where `a + + +2' does not. Measured
      # against gcc, which renders the second.
      textOf = l:
        let
          ts = l.toks;
          piece = j:
            let t = b.elemAt ts j; in
            if t.ws != "" then " " + t.text
            else if j == 0 then t.text
            else if staysApart (b.elemAt ts (j - 1)) t then t.text
            else " " + t.text;
        in
        b.concatStringsSep "" (b.genList piece (b.length ts));
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
