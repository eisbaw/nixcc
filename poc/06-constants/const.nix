# Evaluating C89 constants from the lexemes poc/02-lexer produces.
#
# The lexer classifies ICON/FCON/SCON and keeps the text; nothing yet turns
# that text into a VALUE. lcc does it inside gettok, in icon(), scon(),
# backslash(), cput() and wcput() (lcc/src/lex.c). What is ported here is
# lcc's semantics, verified against `rcc-rv32' form by form in oracle.py --
# not lcc's control flow, which is an imperative scan over a refilled buffer.
#
# THE TWO NIX TRAPS (decision-001), because they decide the shape:
#
#   * INTEGER OVERFLOW THROWS. `9223372036854775807 + 1' raises "integer
#     overflow", it does not wrap. lcc detects overflow in exactly the place
#     where that would happen: it lets the accumulation run and looks at the
#     result. A thrown evaluator error is not a diagnosable overflow -- it
#     takes the whole compilation down with a message about Nix rather than
#     about the user's program -- so every accumulation below tests BEFORE the
#     multiply, never after. See `accumulate'.
#
#   * NIX STRINGS CANNOT HOLD A NUL BYTE. `"a\0b"' has a perfectly good value
#     in C and no representation as a Nix string at all. So a decoded string
#     constant is a LIST OF UNITS, never a string. That is also the
#     representation the emitter wants, which is why it costs nothing.
#
# WHAT A STRING CONSTANT IS, since task-027's parser inherits this decision:
#
#   evalSCON returns { units; width; warnings; }. `units' is the decoded
#   content of ONE literal with NO terminator, and `width' is the bytes per
#   unit -- 1 for "abc", 2 for L"abc", because widechar is unsignedshort on
#   this target. The terminating NUL is NOT here, and that is deliberate:
#   lcc's scon() concatenates adjacent literals and only then appends the NUL,
#   while our lexer deliberately emits one SCON token per literal and leaves
#   joining to the parser (see the deviations in poc/02-lexer/lex.nix). If
#   each literal carried its own NUL, `"ab" "cd"' would decode to
#   a,b,NUL,c,d,NUL instead of a,b,c,d,NUL. So the parser concatenates the
#   unit lists of adjacent literals and appends ONE 0 at the end.
#
# WHAT IS NOT HERE. Floating constants are NOT evaluated: decision-006 defers
# float to a later wave and task-015 wants the frontend to REJECT a float
# rather than silently miscompile it, so evalFCON throws and says so. It is
# also the one constant form with no oracle behind it -- symbolic.c prints
# floats with %g, six significant digits (decision-004).
#
# EVERY attrset lookup here carries `or (throw ...)'. That is not decoration:
# builtins.tryEval does NOT catch an attribute-missing error, it propagates
# straight through and takes the must-fail suite with it (task-037). A lookup
# that can miss has to miss as a `throw'.
#
# SOME OF THOSE THROWS ARE ASSERTIONS, NOT DIAGNOSTICS, and the difference is
# worth stating because run.sh's standard is that every check proves it can
# fail. The per-digit throws in `accumulate', `hexEscape' and `octEscape', and
# `typeInfo''s, are unreachable: the regex or `scanWhile' that selected the
# characters already established what they are. They are there so that a
# future caller who bypasses that selection gets a message instead of a wrong
# number, and no mutation is aimed at them because no input can reach them.
# The throws in `bodyOf', `codeOf', `suffixKind', `intConst', `charConst',
# `evalFCON', `evalToken' and the `\x'-with-no-digits path ARE reachable, and
# must-fail.nix covers every one.
#
# THREE DELIBERATE DIVERGENCES FROM lcc, all in the direction of refusing
# rather than continuing with an invented value:
#
#   * `'\xg'' is an lcc ERROR that continues with 0; we throw. The outcome is
#     the same, since an lcc error makes rcc exit non-zero, but the 0 never
#     propagates. It is therefore not in oracle.nix -- two sides failing in
#     different ways have nothing to diff -- and lives in must-fail.nix.
#   * `''' is rejected by our lexer, where lcc reads uninitialised buffer.
#   * lcc's scon() TRUNCATES at BUFSIZE (4096, lcc/src/c.h) and errors with
#     "string literal too long". We have no limit, and stress.nix decodes
#     60000 units from one literal and calls that a pass -- a literal lcc
#     would refuse outright. Ours is arguably the better behaviour, but it
#     means the differential does not cover literals past 4096 units and
#     never can.
let
  b = builtins;

  inherit (import ../02-lexer/lex.nix) explode;

  # ---- the target -------------------------------------------------------
  # RV32 (decision-003), as the rcc-rv32 oracle runs it (decision-004). The
  # numbers are lcc's symbolicIR metrics: char 1, short 2, int 4, long 4, and
  # `unsigned_char = 0', so plain char is SIGNED -- which is why '\377' is -1
  # and not 255. widechar is unsignedshort (lcc/src/types.c), so a wide
  # character constant is 16 bits wide and unsigned.
  INT_MAX = 2147483647;
  LONG_MAX = 2147483647;
  UINT_MAX = 4294967295;
  ULONG_MAX = 4294967295;
  UCHAR_MAX = 255;
  CHAR_SIGN_BIT = 128;
  CHAR_MODULUS = 256;
  WCHAR_MODULUS = 65536;

  # Every type this evaluator can hand back, with the two facts anything
  # downstream needs about one. ONE table rather than a max table beside a
  # list of signed names: the emitter decides whether to two's-complement a
  # value from `signed', and a name in neither table has to be an ERROR rather
  # than quietly defaulting to one answer. An earlier shape here exported a
  # `signedTypes' LIST, and `elem "itn" signedTypes' was false -- a misspelt
  # type read as unsigned, silently, on the emitter's critical path.
  types = {
    "int" = { max = INT_MAX; signed = true; };
    "long" = { max = LONG_MAX; signed = true; };
    "unsigned int" = { max = UINT_MAX; signed = false; };
    "unsigned long" = { max = ULONG_MAX; signed = false; };
    # A wide character constant's type. Its `max' is widechar's range and is
    # never used to CLAMP anything: a wide constant reaches that range by
    # masking inside the escape decoder, not through icon()'s ladder.
    "unsigned short" = { max = 65535; signed = false; };
  };
  typeInfo = ty: types.${ty} or (throw "`${ty}' is not a type this constant evaluator produces");
  maxOf = ty: (typeInfo ty).max;

  # ---- character codes --------------------------------------------------
  # Nix has no ord(). The table is built rather than written out, because 95
  # of the 127 entries are printable and the other 32 are control characters
  # that cannot be typed into a Nix string literal at all. `fromJSON' of a
  # \u escape below U+0080 yields exactly one byte, so the whole of ASCII
  # comes out of one genList.
  #
  # LIMIT, and it is a real one: bytes 128..255 are NOT in this table. A
  # literal containing one -- a UTF-8 string in C source, say -- throws
  # rather than evaluating to something invented. It cannot be built the same
  # way, because fromJSON of a code point above U+007F yields the two or more
  # bytes of its UTF-8 ENCODING rather than the byte itself, and the bytes
  # that never appear in valid UTF-8 (0xc0, 0xc1, 0xf5..0xff) cannot be
  # reached through it at all.
  # `\xNN' and `\NNN' escapes reach every byte value, so nothing is
  # unreachable, only inconvenient. lcc's own sources are pure ASCII. See
  # task-046.
  hexDigitChars = "0123456789abcdef";
  hex2 = n:
    b.substring (n / 16) 1 hexDigitChars + b.substring (b.bitAnd n 15) 1 hexDigitChars;
  asciiChar = n: b.fromJSON "\"\\u00${hex2 n}\"";
  charCode = b.listToAttrs (b.genList (i: { name = asciiChar (i + 1); value = i + 1; }) 127);
  nonAsciiByte = throw
    "a literal contains a byte outside ASCII, and this evaluator has no table entry to name its value with; write it as a \\NNN or \\xNN escape, which reaches every byte (task-046)";
  codeOf = c: charCode.${c} or nonAsciiByte;

  # name -> value, for a string whose characters ARE their own digit values.
  indexTable = s:
    let cs = explode s; in
    b.listToAttrs (b.genList (i: { name = b.elemAt cs i; value = i; }) (b.length cs));
  decValue = indexTable "0123456789";
  octValue = indexTable "01234567";
  # The two cases agree on 0-9 and differ only above it, so one overlays the
  # other rather than a third table being written out.
  hexValue = indexTable "0123456789abcdef" // indexTable "0123456789ABCDEF";

  # ---- integer constants ------------------------------------------------

  # Accumulate digits in `base', stopping at ULONG_MAX rather than running
  # past it.
  #
  # WHY THE TEST IS BEFORE THE MULTIPLY. lcc's decimal loop reads
  # `if (n > (ULONG_MAX - d)/10) overflow = 1; else n = 10*n + d;' -- the
  # comparison is the check, and the multiply only happens when it is known to
  # be safe. Its hexadecimal and octal loops instead inspect the top bits of
  # `n' AFTER shifting, which works in C because unsigned arithmetic wraps and
  # is exactly what cannot be done here. So all three bases use the decimal
  # shape, which is the one that never performs the operation it is guarding.
  #
  # WHY THE CEILING IS ULONG_MAX AND NOT 2^64-1. lcc accumulates into a host
  # `unsigned long' and only then clamps against the TARGET type's maximum. On
  # this target every type tops out at 4294967295, and every path through
  # icon() below sends an overflowing constant to `unsigned long' -- so a
  # value that exceeds 4294967295 produces the same answer (clamp, warn,
  # unsigned long) whether it exceeded it by one or by 2^40. Stopping at the
  # target ceiling therefore agrees with lcc form for form, and keeps every
  # intermediate three decimal orders of magnitude below the point where Nix
  # would throw.
  #
  # The deepSeq is decision-001's: foldl' forces its accumulator only to weak
  # head normal form, so an attrset accumulator otherwise leaves one unforced
  # field chain per digit.
  accumulate = base: table: chars:
    let
      step = acc: c:
        let
          d = table.${c} or (throw "`${c}' is not a base-${toString base} digit");
          r =
            if acc.overflow then acc
            else if acc.value > (ULONG_MAX - d) / base then acc // { overflow = true; }
            else { value = base * acc.value + d; overflow = false; };
        in
        b.deepSeq r r;
    in
    b.foldl' step { value = 0; overflow = false; } chars;

  # lcc's icon(). The type ladder is C89's, and the clamp-with-a-warning on
  # overflow is lcc's own: a constant too big for the type it landed in is a
  # diagnosed constant, not a refused translation unit.
  #
  # ONE ARM OF lcc's LADDER IS MISSING, and it is missing because it is dead
  # in lcc too -- on every target, not just this one. lcc's fourth test is
  # `else if (base != 10 && n > inttype max) unsignedtype', and it sits AFTER
  # `else if (n > inttype max) longtype'. Reaching it requires that test to
  # have failed, so `n > inttype max' is already known false and the arm can
  # never fire anywhere. Transliterating it would put a branch here that no
  # input can take and no test can cover.
  #
  # THAT ORDERING IS A REAL DEVIATION FROM C89, AND WE INHERIT IT. C89 6.1.3.2
  # gives an octal or hexadecimal constant the ladder int -> unsigned int ->
  # long -> unsigned long, so `0xFFFFFFFF' on a 4-byte-int target is UNSIGNED
  # INT. lcc's order reaches `long' first and, here, `unsigned long'. We match
  # lcc, because lcc is the oracle and a divergence the oracle cannot see is
  # how silent bugs get in -- and this one it cannot see: on RV32 int and long
  # are both 4 bytes, so C89's answer and lcc's have the same width, the same
  # signedness and the same value, and no code this compiler emits can tell
  # them apart. On a target whose long is wider than its int they would
  # differ, and that is a decision for whoever ports this to one.
  #
  # `else if n > INT_MAX then "long"' below is dead on THIS target for a
  # different and much duller reason -- INT_MAX and LONG_MAX are equal here --
  # and is kept because it is a rung C89 really names and a wider long would
  # need it. Dead-on-this-target is not the same as dead-everywhere.
  icon = lexeme: acc: suffix:
    let
      n = acc.value;
      over = acc.overflow;
      ty =
        if suffix == "ul" then "unsigned long"
        else if suffix == "u" then
          (if over || n > UINT_MAX then "unsigned long" else "unsigned int")
        else if suffix == "l" then
          (if over || n > LONG_MAX then "unsigned long" else "long")
        else if over || n > LONG_MAX then "unsigned long"
        else if n > INT_MAX then "long"
        else "int";
      limit = maxOf ty;
      blown = over || n > limit;
    in
    {
      value = if blown then limit else n;
      type = ty;
      warnings = if blown then [ "overflow in constant `${lexeme}'" ] else [ ];
    };

  # lcc's icon() reads at most one `u' and one `l' in either order; whatever
  # else follows is left for ppnumber() to reject, which our lexer already
  # does when it validates the numeric lexeme. So the shapes reaching here are
  # exactly these four.
  suffixKind = s:
    let low = b.replaceStrings [ "U" "L" ] [ "u" "l" ] s; in
    if low == "" then ""
    else if low == "u" then "u"
    else if low == "l" then "l"
    else if low == "ul" || low == "lu" then "ul"
    else throw "`${s}' is not a C89 integer suffix";

  # Split the lexeme into digits and suffix, and pick the base. Hexadecimal is
  # tested first because `0x1e' starts with the octal prefix too, and octal
  # before decimal because `0' is an octal constant with no digits.
  intConst = lexeme:
    let
      forms = [
        { re = "0[xX]([0-9a-fA-F]+)([uUlL]*)"; base = 16; table = hexValue; }
        { re = "0([0-7]*)([uUlL]*)"; base = 8; table = octValue; }
        { re = "([1-9][0-9]*)([uUlL]*)"; base = 10; table = decValue; }
      ];
      hit = b.foldl'
        (acc: f:
          if acc != null then acc
          else let m = b.match f.re lexeme; in if m == null then null else { inherit f m; })
        null
        forms;
    in
    if hit == null then
      throw "`${lexeme}' is not an integer constant"
    else
      icon lexeme
        (accumulate hit.f.base hit.f.table (explode (b.elemAt hit.m 0)))
        (suffixKind (b.elemAt hit.m 1));

  # ---- escape sequences -------------------------------------------------

  # lcc's backslash(), minus the parts that only make sense to a scanner with
  # a refill buffer. `\a' is 7 rather than '\a' because Nix has no such escape
  # either; the rest are spelled as numbers for the same reason.
  simpleEscape = {
    "a" = 7;
    "b" = 8;
    "f" = 12;
    "n" = 10;
    "r" = 13;
    "t" = 9;
    "v" = 11;
  };
  # `\'' `\"' `\\' `\?' yield the character itself -- lcc reaches them by
  # falling out of its switch onto `return cp[-1]'. A table rather than a
  # regex character class, because two of the four characters are the ones a
  # bracket expression argues about.
  literalEscape = {
    "'" = true;
    "\"" = true;
    "\\" = true;
    "?" = true;
  };

  # ---- one literal ------------------------------------------------------

  # Decode the body of a character or string literal into units.
  #
  # genericClosure rather than recursion or a `++' fold, for decision-001's
  # reasons: this is a data-dependent loop that must EMIT one value per step
  # (an escape consumes between one and an unbounded number of characters, so
  # the step size is not known in advance), `acc ++ [x]' is quadratic, and a
  # recursion whose depth tracks the literal's length would meet the
  # max-call-depth cap on a long one. genericClosure is an iterative worklist
  # in the evaluator: linear, at constant stack depth.
  #
  # genericClosure forces only `key', so the operator deepSeqs the item it
  # returns. That is defensive rather than load-bearing TODAY and the
  # difference is worth stating: every field of an item here depends on the
  # item's own offset and not on the previous item's, so no thunk chain forms
  # and dropping the deepSeq was measured not to overflow at 60000 units. It
  # stays because the next field added here need not have that property, and
  # the failure it would cause is "stack overflow (possible infinite
  # recursion)" rather than a slowdown. poc/02-lexer/lex.nix says the same
  # about its own loop, where the chain DOES form.
  #
  # Order: genericClosure yields items in the order they were discovered, and
  # `key' is the strictly increasing start offset, so the units come out in
  # source order.
  scanUnits = wide: body:
    let
      cs = explode body;
      n = b.length cs;
      at = i: if i >= n then "" else b.elemAt cs i;

      # First index at or after `from' that fails `pred', or n. Windows
      # double, so the work is O(run length) while the recursion DEPTH is
      # O(log run length) -- the same shape and the same reason as
      # poc/02-lexer's runUntil. A plain `if pred i then go (i + 1) else i'
      # would be one stack frame per digit, and decision-001's max-call-depth
      # cap is the reason no traversal in this tree is written that way.
      scanWhile = pred: from:
        let
          go = width: pos:
            if pos >= n then n
            else
              let
                lim = if pos + width > n then n else pos + width;
                r = b.foldl'
                  (s: i: if s.done then s else if pred i then s else { done = true; pos = i; })
                  { done = false; pos = lim; }
                  (b.genList (i: pos + i) (lim - pos));
              in
              if r.done then r.pos else go (2 * width) lim;
        in
        go 1 from;

      # lcc's `\x': one or more hexadecimal digits, no length limit, the
      # running value inspected for overflow against the WIDE character's
      # width (8*widechar->size - 4 = 12) whatever kind of literal it is in,
      # and masked to that width on the way out. The accumulation is kept
      # inside 32 bits with bitAnd because lcc's is an `unsigned int' and
      # would wrap there; without the mask a long enough escape would throw.
      hexEscape = from:
        let
          end = scanWhile (i: hexValue ? ${at i}) from;
          step = acc: i:
            let
              d = hexValue.${at i} or (throw "`${at i}' is not a hexadecimal digit");
              r = {
                value = b.bitAnd (16 * acc.value + d) 4294967295;
                overflow = acc.overflow || acc.value / 4096 > 0;
              };
            in
            b.deepSeq r r;
          acc = b.foldl' step { value = 0; overflow = false; } (b.genList (i: from + i) (end - from));
        in
        {
          next = end;
          value = b.bitAnd acc.value (WCHAR_MODULUS - 1);
          warnings = if acc.overflow then [ "overflow in hexadecimal escape sequence" ] else [ ];
        };

      # lcc's `\0'..`\7': at most three octal digits, so at most 0777, so no
      # overflow is reachable and none is diagnosed.
      octEscape = from:
        let
          run = scanWhile (i: octValue ? ${at i}) from;
          end = if run > from + 3 then from + 3 else run;
          step = acc: i: 8 * acc + (octValue.${at i} or (throw "`${at i}' is not an octal digit"));
        in
        {
          next = end;
          value = b.foldl' step 0 (b.genList (i: from + i) (end - from));
          warnings = [ ];
        };

      unitAt = i:
        let
          c = at i;
          e = at (i + 1);
        in
        if c != "\\" then { key = i; next = i + 1; value = codeOf c; warnings = [ ]; }
        else if simpleEscape ? ${e} then
          { key = i; next = i + 2; value = simpleEscape.${e}; warnings = [ ]; }
        else if literalEscape ? ${e} then
          { key = i; next = i + 2; value = codeOf e; warnings = [ ]; }
        else if e == "x" then
          let r = hexEscape (i + 2); in
          # lcc ERRORS here rather than warning, and carries on with 0. We
          # throw. The outcome is the same -- an lcc error makes rcc exit
          # non-zero, so neither compiler produces an object from this -- and
          # a thrown diagnostic is this tree's rule for a failure that has no
          # sensible value to continue with.
          if r.next == i + 2 then
            throw "ill-formed hexadecimal escape sequence `\\x${at (i + 2)}'"
          else { key = i; inherit (r) next value warnings; }
        else if octValue ? ${e} then
          let r = octEscape (i + 1); in { key = i; inherit (r) next value warnings; }
        else if e == "" then
          # The lexer cannot hand us this -- it rejects a literal whose
          # closing quote is escaped -- but a caller passing a body by hand
          # can, and a silent 0 would be worse than a refusal.
          throw "a literal ends in a backslash with nothing to escape"
        else
          {
            key = i;
            next = i + 2;
            value = codeOf e;
            warnings = [ "unrecognized character escape sequence `\\${e}'" ];
          };

      items =
        if n == 0 then [ ]
        else b.genericClosure {
          startSet = [ (unitAt 0) ];
          operator = it:
            if it.next >= n then [ ]
            else let x = unitAt it.next; in b.deepSeq x [ x ];
        };

      # lcc's cput() warns when a decoded unit will not fit in a byte and
      # stores it truncated anyway; wcput() has no such check because every
      # unit already fits in 16 bits (`\x' is masked, `\777' is 511, a source
      # character is at most 255).
      narrowed = map
        (it: {
          value = b.bitAnd it.value (CHAR_MODULUS - 1);
          warnings = it.warnings ++ (
            if it.value > UCHAR_MAX
            then [ "overflow in escape sequence with resulting value `${toString it.value}'" ]
            else [ ]
          );
        })
        items;
      widened = map (it: { inherit (it) value warnings; }) items;
      units = if wide then widened else narrowed;
    in
    {
      values = map (u: u.value) units;
      warnings = b.concatLists (map (u: u.warnings) units);
    };

  # `'a'' and `L'a''; the lexer hands both back as ICON, as lcc does.
  isWide = lexeme: b.substring 0 1 lexeme == "L";
  # The quotes are checked rather than assumed, and the EXPECTED quote is
  # passed in rather than read off the lexeme. Two traps, both real:
  # builtins.substring reads a NEGATIVE length as "to the end of the string",
  # so a truncated lexeme like `"' would come back as an empty literal instead
  # of an error; and a version of this that merely required the first and last
  # characters to MATCH accepted `evalSCON "'a'"' and `evalSCON "xax"'. The
  # lexer cannot produce either, but a frontend stage that fails fast is one
  # that does not depend on its caller staying correct.
  bodyOf = quote: lexeme:
    let
      start = if isWide lexeme then 2 else 1;
      n = b.stringLength lexeme;
      kind = if quote == "\"" then "string" else "character";
    in
    if n < start + 1
      || b.substring (start - 1) 1 lexeme != quote
      || b.substring (n - 1) 1 lexeme != quote then
      throw "`${lexeme}' is not a ${kind} literal: it must open and close with ${quote}"
    else
      b.substring start (n - start - 1) lexeme;

  charConst = lexeme:
    let
      wide = isWide lexeme;
      r = scanUnits wide (bodyOf "'" lexeme);
      count = b.length r.values;
      first = if count == 0 then throw "empty character constant `${lexeme}'" else b.head r.values;
      excess =
        if count <= 1 then [ ]
        else if wide then [ "excess characters in wide-character literal ignored" ]
        else [ "excess characters in multibyte character literal ignored" ];
    in
    {
      # A narrow character constant has type int and carries the byte SIGN
      # EXTENDED, because plain char is signed on this target; a wide one has
      # type unsigned short and carries the unit as it stands.
      value =
        if wide then first
        else if first >= CHAR_SIGN_BIT then first - CHAR_MODULUS
        else first;
      type = if wide then "unsigned short" else "int";
      warnings = r.warnings ++ excess;
    };

  stringConst = lexeme:
    let
      wide = isWide lexeme;
      r = scanUnits wide (bodyOf "\"" lexeme);
    in
    {
      units = r.values;
      width = if wide then 2 else 1;
      inherit (r) warnings;
    };

  # ---- the public surface -----------------------------------------------

  isCharLexeme = lexeme:
    b.substring 0 1 lexeme == "'" || b.substring 0 2 lexeme == "L'";

  evalICON = lexeme: if isCharLexeme lexeme then charConst lexeme else intConst lexeme;
  evalSCON = stringConst;
  evalFCON = lexeme: throw "floating constant `${lexeme}': float support is deferred to a later wave (decision-006), so the frontend rejects it rather than silently miscompiling it (task-015). RV32I has no F or D extension, and lcc's symbolic oracle prints floats with %g, so this is the one constant form with no oracle behind it";

  # The token's fields are read through `or (throw ...)' for the same reason
  # every other lookup in this file is: builtins.tryEval does not catch an
  # attribute miss (task-037), so `tok.text' on a token that has none would
  # propagate out of every must-fail suite that tried to cover it. This is the
  # entry point task-027 is told to call, which is the worst place in the file
  # for that hole to be.
  evalToken = tok:
    let
      kind = tok.kind or (throw "evalToken: this token has no `kind' field, so there is nothing to dispatch on");
      text = tok.text or (throw "evalToken: the `${kind}' token has no `text' field, so there is no lexeme to evaluate");
    in
    if kind == "ICON" then evalICON text
    else if kind == "SCON" then evalSCON text
    else if kind == "FCON" then evalFCON text
    else throw "evalToken: token kind `${kind}' is not a constant";
in
{
  inherit evalICON evalSCON evalFCON evalToken;
  # Whether a type this evaluator produced is signed. A FUNCTION and not a
  # list, so an unknown name is an error rather than "not in the list, so
  # unsigned". The emitter will decide whether to two's-complement a value
  # with this.
  signedOf = ty: (typeInfo ty).signed;
}
