# Hand-written expectations for the constant evaluator. Written out by hand
# rather than recorded from the evaluator, so a wrong evaluator cannot bless
# its own output.
#
# WHY THIS TABLE EXISTS AT ALL when oracle.py diffs a long list of forms
# against lcc: because the oracle cannot see everything. int and long are
# both 4-byte signed on this target, so lcc prints CNSTI4 for both and no C construct in
# this IR separates them. The TYPE NAME is what this table pins, and it is the
# half of C89's type ladder the differential is blind to. Everything else here
# is belt and braces, and cheap.
#
# `warnings' is omitted where there are none, which is most cases; the check
# defaults it to the empty list rather than letting a missing field mean
# "don't look".
let
  scalar = what: lexeme: type: value: { inherit what lexeme type value; };
  warned = what: lexeme: type: value: warnings: { inherit what lexeme type value warnings; };
  str = what: lexeme: units: { inherit what lexeme units; width = 1; };
  wstr = what: lexeme: units: { inherit what lexeme units; width = 2; };
in
{
  # --- the C89 type ladder, which is what the oracle cannot see ----------
  # C89 6.1.3.2: a decimal constant with no suffix is int, else long, else
  # unsigned long; an octal or hexadecimal one may also be unsigned int. lcc
  # walks it in icon(), and on a target whose int and long are both 4 bytes
  # the unsigned-int rung is unreachable without a `u' suffix -- see the note
  # in const.nix about the arm that is deliberately absent.
  scalars = [
    (scalar "decimal that fits in int" "7" "int" 7)
    (scalar "the largest int" "2147483647" "int" 2147483647)
    (scalar "one past the largest int becomes unsigned long, not long" "2147483648" "unsigned long" 2147483648)
    (scalar "the largest unsigned long" "4294967295" "unsigned long" 4294967295)
    (scalar "zero" "0" "int" 0)

    # Octal and hexadecimal take the same ladder.
    (scalar "octal zero" "00" "int" 0)
    (scalar "octal" "0777" "int" 511)
    (scalar "the largest octal int" "017777777777" "int" 2147483647)
    (scalar "octal past the largest int" "020000000000" "unsigned long" 2147483648)
    (scalar "hexadecimal" "0x1f" "int" 31)
    (scalar "uppercase hexadecimal digits and prefix" "0X1E" "int" 30)
    (scalar "the largest hexadecimal int" "0x7fffffff" "int" 2147483647)
    (scalar "hexadecimal past the largest int" "0x80000000" "unsigned long" 2147483648)
    # C89 6.1.3.2 says this one is UNSIGNED INT: an octal or hexadecimal
    # constant walks int -> unsigned int -> long -> unsigned long. lcc's
    # icon() tests `n > long max' before the unsigned-int rung, so it reaches
    # unsigned long instead, and we match lcc rather than the standard -- see
    # const.nix, which explains why and what it would cost on a target whose
    # long is wider than its int. On RV32 the two answers have the same width,
    # the same signedness and the same value, so nothing emitted can tell them
    # apart; this row is here so the choice is written down rather than
    # discovered.
    (scalar "lcc reaches unsigned long where C89 says unsigned int" "0xFFFFFFFF" "unsigned long" 4294967295)

    # Suffixes. lcc reads at most one u and one l, in either order.
    (scalar "unsigned suffix, lower case" "7u" "unsigned int" 7)
    (scalar "unsigned suffix, upper case" "7U" "unsigned int" 7)
    (scalar "long suffix is LONG, which the oracle cannot tell from int" "7l" "long" 7)
    (scalar "long suffix, upper case" "7L" "long" 7)
    (scalar "unsigned long, u first" "7ul" "unsigned long" 7)
    (scalar "unsigned long, l first" "7lu" "unsigned long" 7)
    (scalar "unsigned long, mixed case" "7Ul" "unsigned long" 7)
    (scalar "a long constant too big for long becomes unsigned long" "3000000000l" "unsigned long" 3000000000)
    (scalar "an unsigned constant that still fits unsigned int" "2147483648u" "unsigned int" 2147483648)

    # Overflow: diagnosed and clamped, never thrown and never wrapped.
    (warned "decimal past unsigned long" "4294967296" "unsigned long" 4294967295
      [ "overflow in constant `4294967296'" ])
    (warned "far past what a Nix integer could hold at all" "99999999999999999999999" "unsigned long" 4294967295
      [ "overflow in constant `99999999999999999999999'" ])
    (warned "the largest 64-bit unsigned value, which is still an overflow here" "18446744073709551615" "unsigned long" 4294967295
      [ "overflow in constant `18446744073709551615'" ])
    (warned "hexadecimal overflow" "0x100000000" "unsigned long" 4294967295
      [ "overflow in constant `0x100000000'" ])
    (warned "octal overflow" "040000000000" "unsigned long" 4294967295
      [ "overflow in constant `040000000000'" ])
    (warned "the warning quotes the whole lexeme, suffix included" "5000000000ul" "unsigned long" 4294967295
      [ "overflow in constant `5000000000ul'" ])

    # Character constants. Type int, and the byte is SIGN EXTENDED because
    # plain char is signed on this target (symbolicIR's unsigned_char = 0).
    (scalar "plain character" "'a'" "int" 97)
    (scalar "space" "' '" "int" 32)
    (scalar "newline escape" "'\\n'" "int" 10)
    (scalar "alarm escape, which Nix has no spelling for" "'\\a'" "int" 7)
    (scalar "vertical tab" "'\\v'" "int" 11)
    (scalar "escaped backslash" "'\\\\'" "int" 92)
    (scalar "escaped single quote" "'\\''" "int" 39)
    (scalar "escaped question mark" "'\\?'" "int" 63)
    (scalar "octal escape, one digit" "'\\0'" "int" 0)
    (scalar "octal escape, three digits" "'\\123'" "int" 83)
    (scalar "the largest positive char" "'\\177'" "int" 127)
    (scalar "an octal escape above 127 is NEGATIVE, char being signed" "'\\200'" "int" (-128))
    (scalar "hexadecimal escape" "'\\x41'" "int" 65)
    (scalar "hexadecimal escape above 127 is negative too" "'\\xff'" "int" (-1))
    (warned "an escape too big for a byte is diagnosed and truncated" "'\\x1ff'" "int" (-1)
      [ "overflow in escape sequence with resulting value `511'" ])
    (warned "octal 400 is 256, which does not fit a byte either" "'\\400'" "int" 0
      [ "overflow in escape sequence with resulting value `256'" ])
    (warned "an unknown escape yields the character and says so" "'\\q'" "int" 113
      [ "unrecognized character escape sequence `\\q'" ])
    (warned "a multi-character constant is its first character" "'ab'" "int" 97
      [ "excess characters in multibyte character literal ignored" ])

    # Wide character constants: type unsigned short (widechar is
    # unsignedshort in lcc/src/types.c), and NOT sign extended.
    (scalar "wide character" "L'a'" "unsigned short" 97)
    (scalar "a wide escape above 127 stays positive" "L'\\377'" "unsigned short" 255)
    (scalar "a wide escape fills all 16 bits" "L'\\xffff'" "unsigned short" 65535)
    (warned "a multi-character wide constant warns differently" "L'ab'" "unsigned short" 97
      [ "excess characters in wide-character literal ignored" ])
  ];

  # --- string constants --------------------------------------------------
  # NO TERMINATING NUL. One literal decodes to its own units and nothing
  # else; the parser joins adjacent literals and appends the single 0. See
  # const.nix's header for why that split is where it is.
  strings = [
    (str "empty string, which is legal and decodes to nothing" "\"\"" [ ])
    (str "plain text" "\"hi\"" [ 104 105 ])
    (str "an embedded NUL, which no Nix string could hold" "\"a\\0b\"" [ 97 0 98 ])
    (str "every simple escape" "\"\\a\\b\\f\\n\\r\\t\\v\"" [ 7 8 12 10 13 9 11 ])
    (str "the escapes that yield themselves" "\"\\\\\\\"\\?\\'\"" [ 92 34 63 39 ])
    (str "hexadecimal and octal escapes side by side" "\"\\x41\\101\"" [ 65 65 ])
    (str "bytes above 127 are stored as bytes, not sign extended" "\"\\377\\200\"" [ 255 128 ])
    (str "a digit after a three-digit octal escape is a separate byte" "\"\\1234\"" [ 83 52 ])
    (str "a non-hex character ends a hexadecimal escape" "\"\\x41g\"" [ 65 103 ])

    # THE CHARACTER-CODE TABLE ITSELF. const.nix builds it from fromJSON of
    # \u escapes rather than writing 127 entries out, so nothing else here
    # would catch an entry landing on the wrong code -- the other cases use a
    # handful of characters and would all still pass. The expectation is
    # `genList (i: i + 32) 95' rather than 95 numbers typed out, and that is a
    # SPECIFICATION and not a recording: printable ASCII is contiguous from 32
    # to 126, which is a fact about ASCII, not about our evaluator. `"' and
    # `\' appear as escapes because a C literal cannot hold them raw, which
    # incidentally puts them through the escape path instead.
    {
      what = "every printable ASCII character, in order";
      lexeme = "\" !\\\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\"";
      units = builtins.genList (i: i + 32) 95;
      width = 1;
    }
    # The oracle covers the diagnosed ones too; they are here because a
    # string is the only place where several of them can appear at once.
    {
      what = "two diagnosed escapes in one literal, in source order";
      lexeme = "\"\\q\\x1ff\"";
      units = [ 113 255 ];
      width = 1;
      warnings = [
        "unrecognized character escape sequence `\\q'"
        "overflow in escape sequence with resulting value `511'"
      ];
    }

    (wstr "a wide string is 2-byte units" "L\"ab\"" [ 97 98 ])
    (wstr "a wide unit is not truncated to a byte" "L\"\\xffff\"" [ 65535 ])
    (wstr "a wide escape above 127 is not sign extended either" "L\"\\377\"" [ 255 ])
  ];

  # --- through the lexer -------------------------------------------------
  # The evaluator's input is whatever poc/02-lexer produces, so at least one
  # case has to arrive that way rather than as a lexeme typed in here. This
  # is the shape task-027's parser will use: lex, then evaluate the ICON and
  # SCON tokens.
  #
  # `expect' is one entry per constant token, in source order: "TYPE:VALUE"
  # for a scalar and "wN:units" for a string.
  lexed = [
    {
      what = "a declaration with an integer, a character and a string in it";
      src = "int a = 42; char c = '\\n'; char *s = \"hi\";";
      expect = [ "int:42" "int:10" "w1:104,105" ];
    }
    {
      what = "the suffix ladder as the lexer hands it over";
      src = "x = 7u + 7l + 7ul + 2147483648;";
      expect = [ "unsigned int:7" "long:7" "unsigned long:7" "unsigned long:2147483648" ];
    }
    {
      what = "a string whose escapes the lexer passes through untouched";
      src = "char *p = \"a\\0b\\x41\";";
      expect = [ "w1:97,0,98,65" ];
    }
  ];
}
