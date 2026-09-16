# Hand-written token tables. One source of truth for the lexer test: `src` is
# fed to lex.nix and `expect` is the "KIND:text" form of the tokens it must
# produce, EOI dropped. Written out by hand rather than recorded from the
# lexer, so a wrong lexer cannot bless its own output.
#
# Several entries below encode a DELIBERATE divergence from ISO C, because they
# encode lcc's behaviour instead; each says so. See lex.nix's header.
let
  c = what: src: expect: { inherit what src expect; };
in
{
  # --- token kind and text, EOI dropped ---------------------------------
  tokens = [
    # --- the shapes named in the task -------------------------------------
    (c "hex integer" "0x1f" [ "ICON:0x1f" ])
    (c "plain character constant" "'a'" [ "ICON:'a'" ])
    (c "escaped character constant" "'\\n'" [ "ICON:'\\n'" ])
    (c "string with an escaped quote" "\"a\\\"b\"" [ "SCON:\"a\\\"b\"" ])
    (c "arrow" "p->x" [ "ID:p" "DEREF:->" "ID:x" ])
    (c "increment" "i++" [ "ID:i" "INCR:++" ])
    # lcc has no compound-assignment tokens at all: expr.c peeks at the raw next
    # character instead. A parser recovers `<<=` from LSHIFT followed by a '='
    # whose ws is "".
    (c "shift-assign is two tokens in lcc" "a<<=b" [ "ID:a" "LSHIFT:<<" "=:=" "ID:b" ])
    (c "add-assign is two tokens in lcc" "a+=b" [ "ID:a" "+:+" "=:=" "ID:b" ])
    (c "divide-assign is two tokens in lcc" "a/=b" [ "ID:a" "/:/" "=:=" "ID:b" ])
    (c "ellipsis" "f(int,...)" [ "ID:f" "(:(" "INT:int" ",:," "ELLIPSIS:..." "):)" ])
    (c "block comment containing a line comment" "a/* x // y */b" [ "ID:a" "ID:b" ])
    (c "line comment containing a block open" "a// /* b\nc" [ "ID:a" "ID:c" ])
    (c "line comment at end of input, no newline" "a//comment" [ "ID:a" ])
    (c "block comment at end of input, closed" "a/*c*/" [ "ID:a" ])

    # --- maximal munch ----------------------------------------------------
    (c "a+++b munches ++ first" "a+++b" [ "ID:a" "INCR:++" "+:+" "ID:b" ])
    (c "a---b munches -- first" "a---b" [ "ID:a" "DECR:--" "-:-" "ID:b" ])
    (c "two dots are not an ellipsis" "a..b" [ "ID:a" ".:." ".:." "ID:b" ])
    (c "four dots" "...." [ "ELLIPSIS:..." ".:." ])
    (c "shift versus compare" "a>>b>c" [ "ID:a" "RSHIFT:>>" "ID:b" ">:>" "ID:c" ])
    (c "not-equal versus not" "!a!=b" [ "!:!" "ID:a" "NEQ:!=" "ID:b" ])
    (c "logical versus bitwise" "a&&b&c||d|e" [
      "ID:a"
      "ANDAND:&&"
      "ID:b"
      "&:&"
      "ID:c"
      "OROR:||"
      "ID:d"
      "|:|"
      "ID:e"
    ])

    # --- numbers ----------------------------------------------------------
    (c "zero" "0" [ "ICON:0" ])
    (c "octal" "0777" [ "ICON:0777" ])
    (c "unsigned long suffix" "42UL" [ "ICON:42UL" ])
    (c "hex with suffix" "0xFFul" [ "ICON:0xFFul" ])
    # 0x1e ends in 'e' but is hex, so the '+' is a separate token. lcc's hex
    # scanner stops at '+' the same way; C's pp-number rule would not.
    (c "hex ending in e is not an exponent" "0x1e+5" [ "ICON:0x1e" "+:+" "ICON:5" ])
    (c "float with exponent" "1e5" [ "FCON:1e5" ])
    (c "float with signed exponent" "1E+5" [ "FCON:1E+5" ])
    (c "float with negative exponent and suffix" "1.5e-3f" [ "FCON:1.5e-3f" ])
    (c "leading dot float" ".5" [ "FCON:.5" ])
    (c "trailing dot float" "5." [ "FCON:5." ])
    (c "dot then identifier is member access" "a.b" [ "ID:a" ".:." "ID:b" ])
    (c "number then dot then number" "1.2" [ "FCON:1.2" ])
    (c "subtraction is not a signed exponent" "1-5" [ "ICON:1" "-:-" "ICON:5" ])

    # --- identifiers and keywords -----------------------------------------
    (c "keyword" "while" [ "WHILE:while" ])
    (c "keyword prefix is an identifier" "whilex" [ "ID:whilex" ])
    (c "if versus ifdef" "ifdef" [ "ID:ifdef" ])
    (c "int versus intx" "intx" [ "ID:intx" ])
    (c "leading underscore" "_x1" [ "ID:_x1" ])
    (c "lcc extension keywords" "__typecode __firstarg" [ "TYPECODE:__typecode" "FIRSTARG:__firstarg" ])
    (c "L alone is an identifier" "L" [ "ID:L" ])
    (c "L followed by an identifier" "Lx" [ "ID:Lx" ])

    # --- literals ---------------------------------------------------------
    (c "empty string" "\"\"" [ "SCON:\"\"" ])
    (c "string holding a slash-slash" "\"a//b\"" [ "SCON:\"a//b\"" ])
    (c "string holding a comment opener" "\"/*\"" [ "SCON:\"/*\"" ])
    (c "string ending in an escaped backslash" "\"a\\\\\"" [ "SCON:\"a\\\\\"" ])
    (c "escaped single quote" "'\\''" [ "ICON:'\\''" ])
    (c "escaped backslash character" "'\\\\'" [ "ICON:'\\\\'" ])
    (c "octal escape" "'\\0'" [ "ICON:'\\0'" ])
    (c "wide character constant" "L'x'" [ "ICON:L'x'" ])
    (c "wide string" "L\"x\"" [ "SCON:L\"x\"" ])
    (c "adjacent strings stay separate tokens" "\"a\" \"b\"" [ "SCON:\"a\"" "SCON:\"b\"" ])

    # --- trivia -----------------------------------------------------------
    (c "empty input" "" [ ])
    (c "whitespace only" "  \n\t " [ ])
    (c "comment only" "/* nothing */" [ ])
    (c "comment with stars inside" "a/** x **/b" [ "ID:a" "ID:b" ])
    (c "slash-star-slash does not close itself" "a/*/ */b" [ "ID:a" "ID:b" ])
    (c "two comments back to back" "a/*x*//*y*/b" [ "ID:a" "ID:b" ])
    (c "division is not a comment" "a/b" [ "ID:a" "/:/" "ID:b" ])
    (c "comment in the middle of an expression" "a/*c*/+b" [ "ID:a" "+:+" "ID:b" ])

    # --- preprocessor leftovers, which raw C89 sources are full of ---------
    (c "include line" "#include <stdio.h>" [
      "#:#"
      "ID:include"
      "<:<"
      "ID:stdio"
      ".:."
      "ID:h"
      ">:>"
    ])
    (c "stringise and paste operators" "#a##b" [ "#:#" "ID:a" "#:#" "#:#" "ID:b" ])
    # Backslash-newline is trivia BETWEEN tokens only. ISO C splices it in
    # translation phase 2, before tokenising, so real C would make this one
    # identifier `ab`. See task-008; raw lcc sources only ever use it to continue
    # a #define, where the difference does not show.
    (c "backslash-newline between tokens" "a\\\nb" [ "ID:a" "ID:b" ])
    (c "macro continuation" "#define A 1 \\\n + 2" [
      "#:#"
      "ID:define"
      "ID:A"
      "ICON:1"
      "+:+"
      "ICON:2"
    ])

    # --- integer suffixes. lcc's icon() takes at most one u and one l, in
    # either order, and ppnumber() errors on anything left over -----------
    (c "unsigned suffix" "1u" [ "ICON:1u" ])
    (c "long suffix" "1L" [ "ICON:1L" ])
    (c "unsigned long" "1ul" [ "ICON:1ul" ])
    (c "long unsigned" "1LU" [ "ICON:1LU" ])
    (c "hexadecimal with both suffixes" "0xFFul" [ "ICON:0xFFul" ])
    (c "float suffix" "1e5f" [ "FCON:1e5f" ])
    (c "long double suffix" "1.0L" [ "FCON:1.0L" ])
  ];

  # --- line numbers. Nothing else in this directory checks them, and a
  # lexer that answered "line 1" to everything would pass every other test
  # here. Each entry lists LINE:KIND for every token INCLUDING EOI, so the
  # line the file ends on is pinned too.
  lines = [
    (c "one token per line" "a\nb\nc" [ "1:ID" "2:ID" "3:ID" "3:EOI" ])
    (c "newlines inside a block comment" "a/*\n\n*/b" [ "1:ID" "3:ID" "3:EOI" ])
    (c "token after a line comment" "a//x\nb" [ "1:ID" "2:ID" "2:EOI" ])
    (c "backslash-newline between tokens" "a\\\nb" [ "1:ID" "2:ID" "2:EOI" ])
    (c "trailing newline moves EOI on" "a\n" [ "1:ID" "2:EOI" ])
    (c "blank lines only" "\n\n\n" [ "4:EOI" ])
    (c "comment only, spanning lines" "/*\n*/" [ "2:EOI" ])
    (c "empty input" "" [ "1:EOI" ])
  ];

  # --- the two derived flags a preprocessor reads off every token, and
  # nothing else in this directory looks at. A lexer that set `bol' on every
  # token, or on none, passes every other case in this file: the flags are not
  # in `brief', not in the line table and not in the round trip. Each entry
  # lists FLAGS:KIND for every token including EOI -- `B' for bol, `G' for
  # glue, `-' for neither.
  #
  # Every case below was checked against `gcc -E' before it was written down,
  # because the rule these flags encode is a rule about what gcc calls a
  # directive. See lex.nix's triviaStep.
  starts = [
    (c "the first token in a file starts a line and the next does not"
      "a b" [ "B-:ID" "--:ID" "--:EOI" ])
    (c "a trailing newline ends the last line, so EOI starts one"
      "a\nb\n" [ "B-:ID" "B-:ID" "B-:EOI" ])
    # ISO C phase 2 makes `ab' of this; this lexer makes two tokens and flags
    # the join (task-008), which is the one case the preprocessor refuses.
    (c "a continuation and nothing else glues two tokens together"
      "a\\\nb" [ "B-:ID" "-G:ID" "--:EOI" ])
    (c "a space before the continuation means the tokens were already apart"
      "a \\\nb" [ "B-:ID" "--:ID" "--:EOI" ])
    (c "and so does a space after it"
      "a\\\n b" [ "B-:ID" "--:ID" "--:EOI" ])
    (c "two continuations in a row still glue"
      "a\\\n\\\nb" [ "B-:ID" "-G:ID" "--:EOI" ])
    # A newline inside a block comment does not end a logical line, which is
    # what lets a directive carry a multi-line comment in the middle of it.
    (c "a newline inside a block comment does not end a line"
      "a/*\n*/b" [ "B-:ID" "--:ID" "--:EOI" ])
    (c "the newline that ends a line comment does end a line"
      "a//x\nb" [ "B-:ID" "B-:ID" "--:EOI" ])
    (c "a directive's own tokens do not each start a line"
      "#define A 1\n" [ "B-:#" "--:ID" "--:ID" "--:ICON" "B-:EOI" ])
    # gcc -E, measured: the `#' here is NOT a directive, because the only
    # newline before it is inside the comment.
    (c "a block comment spanning a line does not make the next `#' a directive"
      "int a; /* x\n */ #define A 1\n"
      [ "B-:INT" "--:ID" "--:;" "--:#" "--:ID" "--:ID" "--:ICON" "B-:EOI" ])
    # And, measured the same way: it IS one when it is the file's first token,
    # because there is nothing before it but whitespace.
    (c "a leading comment still leaves the file's first `#' a directive"
      "/* x\n*/ #define A 1\n"
      [ "B-:#" "--:ID" "--:ID" "--:ICON" "B-:EOI" ])
  ];
}
