# The constant forms this PoC diffs against lcc, our answer for each of them,
# and the C that asks lcc the same question. One list, so the program handed
# to the oracle and the expectations compared against it cannot drift apart.
#
# HOW A CONSTANT'S TYPE IS MADE VISIBLE. `rcc -target=symbolic' prints a
# constant node as CNSTI4 or CNSTU4, so a constant's SIGNEDNESS is on the
# face of the IR -- but only if something keeps it there. An initializer does
# not: `unsigned long u = 1;' converts the constant to the declared type and
# prints the converted node, so every form would come back as whatever it was
# assigned to. A relational against an int variable does keep it: the usual
# arithmetic conversions turn `x < 7u' into CVIU4 + CNSTU4 + GEU4 while
# `x < 7' stays CNSTI4 + GEI4. So every integer and character form is asked
# as `int fN(int x) { return x < FORM; }' and the first CNST node in the
# function is the constant itself.
#
# WHAT THE ORACLE CANNOT SEE, and it is worth being plain about it: int and
# long are both 4-byte signed on this target, so lcc prints CNSTI4 for both
# and no C construct distinguishes them in this IR. `7' and `7l' are diffed
# and agree; that they agree is all the oracle can say. The int/long half of
# the type ladder is covered by cases.nix instead, which is a hand-written
# table and says so.
#
# WIDE CHARACTER CONSTANTS promote. `L'a'' has type unsigned short, and in
# `x < L'a'' the usual arithmetic conversions promote it to int, because int
# holds every unsigned short value (C89 6.2.1.1). So the oracle sees a signed
# constant for a form whose own type is unsigned. That promotion is applied
# here, explicitly, rather than being quietly absorbed into the expectation.
#
# FORMS THAT MAKE lcc ERROR ARE NOT HERE. `'\xg'' is an lcc error, not a
# warning, and we throw on it rather than continuing with 0; a form whose two
# sides fail in different ways has nothing to diff. Those live in
# must-fail.nix, where the check is that we refuse them and say why.
let
  b = builtins;
  c = import ./const.nix;

  # Integer and character constants, asked through a relational so the
  # signedness survives.
  scalars = [
    # decimal, and the int/long/unsigned-long ladder C89 walks
    "0"
    "1"
    "7"
    "2147483646"
    "2147483647"
    "2147483648"
    "3000000000"
    "4294967295"
    "4294967296"
    "5000000000"
    "99999999999999999999999"
    "18446744073709551615"
    # octal
    "00"
    "07"
    "010"
    "0777"
    "017777777777"
    "020000000000"
    "037777777777"
    "040000000000"
    # hexadecimal
    "0x0"
    "0x1e"
    "0X1E"
    "0x7fffffff"
    "0x80000000"
    "0xFFFFFFFF"
    "0xffffffff"
    "0x100000000"
    "0x1FFFFFFFF"
    # suffixes, in both cases and both orders
    "7u"
    "7U"
    "7l"
    "7L"
    "7ul"
    "7uL"
    "7Ul"
    "7UL"
    "7lu"
    "7lU"
    "7Lu"
    "7LU"
    "2147483647u"
    "2147483648u"
    "4294967295u"
    "5000000000u"
    "2147483647l"
    "2147483648l"
    "3000000000l"
    "5000000000l"
    "5000000000ul"
    "0x7fffffffl"
    "0x80000000l"
    # character constants: plain, the simple escapes, octal and hexadecimal
    "'a'"
    "'Z'"
    "'0'"
    "' '"
    "'~'"
    "'\\n'"
    "'\\t'"
    "'\\r'"
    "'\\v'"
    "'\\f'"
    "'\\b'"
    "'\\a'"
    "'\\\\'"
    "'\\''"
    "'\\\"'"
    "'\\?'"
    "'\\0'"
    "'\\1'"
    "'\\12'"
    "'\\123'"
    "'\\177'"
    "'\\200'"
    "'\\377'"
    "'\\400'"
    "'\\x0'"
    "'\\x41'"
    "'\\x7f'"
    "'\\x80'"
    "'\\xff'"
    "'\\x1ff'"
    "'\\xffff'"
    "'\\x1ffff'"
    "'\\q'"
    "'\\e'"
    "'ab'"
    "'abc'"
    # wide character constants
    "L'a'"
    "L'\\0'"
    "L'\\377'"
    "L'\\xff'"
    "L'\\xffff'"
    "L'ab'"
  ];

  # String literals, asked as an array initializer so `defstring' (narrow) or
  # a run of `defconst unsigned.2' (wide) shows every decoded unit.
  strings = [
    "\"\""
    "\"a\""
    "\"hello\""
    "\"a\\0b\""
    "\"\\x41\\101\\0\\377\""
    "\"\\377\\200\\177 ~\""
    "\"tab\\there\""
    "\"q\\?m\""
    "\"back\\\\slash\""
    "\"quote\\\"inside\""
    "\"\\q\""
    "\"\\x1ff\""
    "L\"\""
    "L\"ab\""
    "L\"\\0\""
    "L\"\\xffff\""
    "L\"\\377\""
  ];

  isWide = lexeme: b.substring 0 1 lexeme == "L";

  # The C line that asks lcc about one form. One form per line and nothing
  # before them, so the line number in a diagnostic IS the form's index plus
  # one -- which is how a warning gets attributed to the form that caused it.
  lineFor = i: form:
    if form.kind == "scalar" then
      "int f${toString i}(int x) { return x < ${form.lexeme}; }"
    else if isWide form.lexeme then
      "unsigned short s${toString i}[] = ${form.lexeme};"
    else
      "char s${toString i}[] = ${form.lexeme};";

  # Our answer, in the shape the oracle's output is decoded into.
  answerFor = form:
    if form.kind == "scalar" then
      let
        r = c.evalICON form.lexeme;
        signed = b.elem r.type c.target.signedTypes || r.type == "unsigned short";
      in
      {
        kind = "scalar";
        signedness = if signed then "signed" else "unsigned";
        inherit (r) value warnings;
      }
    else
      let r = c.evalSCON form.lexeme; in
      {
        kind = "string";
        # THE TERMINATING NUL IS ADDED HERE, not by evalSCON. lcc's scon()
        # appends it after joining adjacent literals; we emit one token per
        # literal and leave both the joining and the terminator to the
        # parser, so the oracle has to do the parser's half to compare.
        units = r.units ++ [ 0 ];
        inherit (r) width warnings;
      };

  forms =
    (map (lexeme: { kind = "scalar"; inherit lexeme; }) scalars)
    ++ (map (lexeme: { kind = "string"; inherit lexeme; }) strings);

  indices = b.genList (i: i) (b.length forms);
in
{
  count = b.length forms;
  lexemes = map (f: f.lexeme) forms;
  csource = b.concatStringsSep "\n" (map (i: lineFor i (b.elemAt forms i)) indices) + "\n";
  answers = map answerFor forms;
}
