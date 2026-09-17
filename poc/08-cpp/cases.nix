# Hand-written expectations for the preprocessor.
#
# WHAT LIVES HERE RATHER THAN IN THE DIFFERENTIAL. oracle.nix compares 48
# translation units against gcc -E and is the stronger test of the two, so
# this file is deliberately NOT a second copy of it. It holds the three kinds
# of case a differential cannot carry:
#
#   * where we KNOW we differ from gcc and mean to. `#if' arithmetic is C89
#     6.8.1's -- every signed type widened to `long', which is 4 bytes on RV32
#     (decision-003) -- while gcc has used intmax_t since C99. `1 << 31' is
#     negative here and positive there. A case like that cannot be in a
#     differential, because the reference would have to be wrong for it to
#     pass.
#   * what gcc will not read at all. `gcc -std=c89' rejects `//' outright, so
#     a `//' comment in front of a directive has no oracle.
#   * what is not in the token stream. Line NUMBERS and the rendered
#     linemarker text are the output of this stage that the differential
#     throws away, and they are what criterion #3 is about.
#
# THE ARMS OF EVERY CONDITIONAL DIFFER. ir/unsig.c in this project returned
# the same number whether it called the signed or the unsigned divide, because
# its divisor was 7. The preprocessor's version of that mistake is a `#if'
# whose two arms emit the same tokens, or a macro that expands to its own
# name: both are green under a preprocessor that never chose anything. So
# `taken' and `untaken' below are distinct identifiers, and the table asserts
# which one came out.
let
  b = builtins;

  # One expansion case: source in, `kind:text' stream out.
  e = what: src: expect: { inherit what src expect; };

  # One conditional case. The source is built rather than written so that the
  # two arms cannot accidentally be made identical, which is the failure this
  # whole table is arranged against.
  c = what: expr: value: {
    inherit what;
    src = "#if ${expr}\nint taken;\n#else\nint untaken;\n#endif\n";
    expect = [ "INT:int" (if value then "ID:taken" else "ID:untaken") ";:;" ];
    inherit expr value;
  };
in
rec {
  # ---- object-like expansion -------------------------------------------
  expansions = [
    (e "a macro with a one-token body"
      "#define N 5\nint x = N;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:5" ";:;" ])

    (e "a macro with a multi-token body"
      "#define P 1 + 2\nint x = P;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:1" "+:+" "ICON:2" ";:;" ])

    # The body is substituted as TOKENS, not as text, so it is not
    # re-parenthesised: `3 * P' is 3 * 1 + 2, which is C's answer too.
    (e "a multi-token body substitutes without parentheses"
      "#define P 1 + 2\nint x = 3 * P;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:3" "*:*" "ICON:1" "+:+" "ICON:2" ";:;" ])

    (e "a macro whose body names another macro"
      "#define INNER 7\n#define OUTER INNER + 1\nint x = OUTER;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:7" "+:+" "ICON:1" ";:;" ])

    (e "a chain three deep, defined in the order that needs rescanning"
      "#define A B\n#define B C\n#define C 9\nint x = A;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:9" ";:;" ])

    # A macro may be used before the macros its body names are defined: the
    # body is expanded at the point of USE, not at the point of definition.
    (e "a body naming a macro defined after it"
      "#define OUTER INNER\n#define INNER 4\nint x = OUTER;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:4" ";:;" ])

    (e "an empty body expands to nothing at all"
      "#define GONE\nint GONE x;\n"
      [ "INT:int" "ID:x" ";:;" ])

    (e "a name that is not a macro is left alone"
      "#define N 5\nint NN = 1;\nint N_ = 2;\n"
      [ "INT:int" "ID:NN" "=:=" "ICON:1" ";:;" "INT:int" "ID:N_" "=:=" "ICON:2" ";:;" ])

    (e "a macro name inside a string literal is not a macro"
      "#define N 5\nchar *s = \"N\";\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"N\"" ";:;" ])

    # To the preprocessor a keyword is an identifier, and poc/02-lexer gives
    # `int' the kind INT rather than ID -- so a lookup keyed on the token's
    # KIND would miss both of these.
    (e "a macro whose body is a keyword"
      "#define INTEGER int\nINTEGER x;\n"
      [ "INT:int" "ID:x" ";:;" ])

    (e "a macro NAMED after a keyword"
      "#define signed unsigned\nsigned int x;\n"
      [ "UNSIGNED:unsigned" "INT:int" "ID:x" ";:;" ])

    # The hide set. Each of these would not terminate without it, and each
    # leaves a different name standing.
    (e "a self-referential macro expands once and stops"
      "#define SELF SELF\nint x = SELF;\n"
      [ "INT:int" "ID:x" "=:=" "ID:SELF" ";:;" ])

    (e "two mutually referential macros stop on the second"
      "#define PING PONG\n#define PONG PING\nint x = PING;\n"
      [ "INT:int" "ID:x" "=:=" "ID:PING" ";:;" ])

    (e "a macro that names itself after something else expands the something"
      "#define INNER 5\n#define OUTER INNER + OUTER\nint x = OUTER;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:5" "+:+" "ID:OUTER" ";:;" ])

    # #undef, with a body that CHANGES afterwards: an #undef that did nothing
    # would be invisible against a redefinition to the same body.
    (e "#undef makes a name ordinary again"
      "#define N 5\nint a = N;\n#undef N\nint b = N;\n"
      [ "INT:int" "ID:a" "=:=" "ICON:5" ";:;" "INT:int" "ID:b" "=:=" "ID:N" ";:;" ])

    (e "a name may be redefined with a different body after #undef"
      "#define N 5\n#undef N\n#define N 6\nint a = N;\n"
      [ "INT:int" "ID:a" "=:=" "ICON:6" ";:;" ])

    (e "#undef of a name that was never defined is not an error"
      "#undef NEVER\nint a = 1;\n"
      [ "INT:int" "ID:a" "=:=" "ICON:1" ";:;" ])

    (e "an identical redefinition is allowed, as C89 6.8.3 says"
      "#define N 1 + 2\n#define N 1 + 2\nint a = N;\n"
      [ "INT:int" "ID:a" "=:=" "ICON:1" "+:+" "ICON:2" ";:;" ])

    # ---- lines, comments and continuations ----------------------------
    (e "a directive continued with a backslash-newline is one directive"
      "#define LONG 1 + \\\n    2\nint x = LONG;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:1" "+:+" "ICON:2" ";:;" ])

    (e "a comment spanning a newline does not end a directive"
      "#define B /* one\n   two */ 8\nint x = B;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:8" ";:;" ])

    # gcc -std=c89 rejects `//' outright, so this pair has no oracle and
    # lives here. The rule is the same one: a newline that is not inside a
    # block comment ends the logical line, and the `#' after it starts one.
    (e "a // comment before a directive still leaves it a directive"
      "int a;\n// remark\n#define N 3\nint b = N;\n"
      [ "INT:int" "ID:a" ";:;" "INT:int" "ID:b" "=:=" "ICON:3" ";:;" ])

    (e "a block comment that spans a line does NOT make the next `#' a directive"
      "int a; /* one\n   two */ #define N 3\n"
      [ "INT:int" "ID:a" ";:;" "#:#" "ID:define" "ID:N" "ICON:3" ])

    (e "the null directive does nothing"
      "int a;\n#\nint b;\n"
      [ "INT:int" "ID:a" ";:;" "INT:int" "ID:b" ";:;" ])

    # ---- the conditional family, as token streams ----------------------
    (e "#ifdef takes the first arm and #ifndef the second"
      "#define ON 1\n#ifdef ON\nint yes;\n#else\nint no;\n#endif\n#ifndef ON\nint absent;\n#else\nint present;\n#endif\n"
      [ "INT:int" "ID:yes" ";:;" "INT:int" "ID:present" ";:;" ])

    (e "an #elif chain fires exactly its first true arm"
      "#define L 3\n#if L > 10\nint a;\n#elif L > 2\nint b;\n#elif L > 1\nint c;\n#else\nint d;\n#endif\n"
      [ "INT:int" "ID:b" ";:;" ])

    (e "a true inner #if inside a false outer one stays silent, and so does its #else"
      "#if 0\n#if 1\nint inner;\n#else\nint innerelse;\n#endif\nint outer;\n#endif\nint after;\n"
      [ "INT:int" "ID:after" ";:;" ])

    (e "a skipped group is not evaluated, so nonsense and refused directives are inert"
      "#if 0\n#if ) nonsense (\n#endif\n#include <nowhere.h>\n#error never\n#define NEVER 1\n#endif\n#ifdef NEVER\nint defined;\n#else\nint undefined;\n#endif\n"
      [ "INT:int" "ID:undefined" ";:;" ])

    (e "#defines inside a taken group take effect"
      "#if 1\n#define IN 7\n#endif\nint x = IN;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:7" ";:;" ])

    (e "a macro defined in one arm and used after the #endif"
      "#if 0\n#define V 1\n#else\n#define V 2\n#endif\nint x = V;\n"
      [ "INT:int" "ID:x" "=:=" "ICON:2" ";:;" ])

    # The operand of `defined' is a NAME and must not be expanded first: HAVE
    # expands to 0, so a preprocessor that expanded it would ask `defined 0'.
    (e "the operand of defined() is not macro-expanded"
      "#define HAVE 0\n#if defined(HAVE)\nint yes;\n#else\nint no;\n#endif\n"
      [ "INT:int" "ID:yes" ";:;" ])

    (e "a macro is expanded inside a #if expression"
      "#define L 4\n#if L * 2 == 8\nint yes;\n#else\nint no;\n#endif\n"
      [ "INT:int" "ID:yes" ";:;" ])

    (e "an identifier that is not a macro is 0 in a #if"
      "#if UNSET\nint yes;\n#else\nint no;\n#endif\n"
      [ "INT:int" "ID:no" ";:;" ])

    (e "a #if on a macro that expands to a non-zero constant"
      "#define SET 1\n#if SET\nint yes;\n#else\nint no;\n#endif\n"
      [ "INT:int" "ID:yes" ";:;" ])

    # ---- function-like macros: parameters and arguments ----------------
    (e "a function-like macro substitutes its argument"
      "#define F(x) x + 1\nint y = F(2);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:2" "+:+" "ICON:1" ";:;" ])

    (e "a parameter used twice is substituted twice"
      "#define TWICE(x) x + x\nint y = TWICE(3);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:3" "+:+" "ICON:3" ";:;" ])

    (e "two parameters are substituted in their own places"
      "#define SUB(a,b) a - b\nint y = SUB(9,4);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:9" "-:-" "ICON:4" ";:;" ])

    # As with an object-like body, an argument is substituted as TOKENS and
    # is not re-parenthesised: `SUB(1 + 1,1)' is 1 + 1 - 1, which is C's
    # answer too and the reason every macro in real code is full of brackets.
    (e "an argument is substituted without parentheses round it"
      "#define SUB(a,b) a - b\nint y = SUB(1 + 1,1);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:1" "+:+" "ICON:1" "-:-" "ICON:1" ";:;" ])

    (e "an empty argument substitutes nothing at all"
      "#define BOTH(a,b) [a|b]\nint y[] = BOTH(,2);\n"
      [ "INT:int" "ID:y" "[:[" "]:]" "=:=" "[:[" "|:|" "ICON:2" "]:]" ";:;" ])

    # The pair that says the PARENTHESIS DEPTH is what splits arguments and
    # not the comma alone: `SECOND((1,2),3)' has two commas and two
    # arguments, and a splitter that ignored the depth would make three and
    # fail the count check.
    (e "a comma inside parentheses belongs to the argument it sits in"
      "#define SECOND(a,b) b\nint y = SECOND((1,2),3);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:3" ";:;" ])

    (e "and that argument keeps its own parentheses when it is substituted"
      "#define FIRST(a,b) a\nint y = FIRST((1,2),3);\n"
      [ "INT:int" "ID:y" "=:=" "(:(" "ICON:1" ",:," "ICON:2" "):)" ";:;" ])

    (e "a macro with no parameters takes an empty argument list"
      "#define Z() 9\nint y = Z();\n"
      [ "INT:int" "ID:y" "=:=" "ICON:9" ";:;" ])

    (e "a function-like macro name not followed by `(' is an ordinary identifier"
      "#define F(x) x + 1\nint F = 2;\n"
      [ "INT:int" "ID:F" "=:=" "ICON:2" ";:;" ])

    # WHAT MAKES A MACRO FUNCTION-LIKE is the `(' being ADJACENT to the name.
    # These two differ by one space and are two different macros: the second
    # is object-like and its body BEGINS with a parenthesis. C89 6.8.3.
    (e "a space before the `(' makes an object-like macro instead"
      "#define F (x) x + 1\nint y = F;\n"
      [ "INT:int" "ID:y" "=:=" "(:(" "ID:x" "):)" "ID:x" "+:+" "ICON:1" ";:;" ])

    # And adjacency is adjacency AFTER ISO C's phase 2: the `(' here carries
    # a line continuation as its trivia rather than nothing at all, which is
    # what poc/02-lexer's `glue' flag says. Without that clause this is
    # quietly an object-like macro and `G(2)' is a token stream nobody wrote.
    (e "a `(' behind a continuation is still adjacent, so this is function-like"
      "#define G\\\n(x) x + 1\nint y = G(2);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:2" "+:+" "ICON:1" ";:;" ])

    (e "and a space before the backslash makes it object-like again"
      "#define G \\\n(x) x + 1\nint y = G;\n"
      [ "INT:int" "ID:y" "=:=" "(:(" "ID:x" "):)" "ID:x" "+:+" "ICON:1" ";:;" ])

    # ...and a name at the very end of a line is an ordinary identifier when
    # the line after it cannot be opening an argument list. The case where it
    # COULD -- the next line beginning with `(' -- is refused naming task-077,
    # and must-fail.nix holds that half.
    (e "a function-like macro name ending a line is an identifier if no `(' follows"
      "#define F(a) a\nint y = F\n;\n"
      [ "INT:int" "ID:y" "=:=" "ID:F" ";:;" ])

    # The `(' may come from a frame the expander is still rescanning...
    (e "the name may come from an expansion and the `(' from the source"
      "#define G F\n#define F(x) (x)\nint y = G (9);\n"
      [ "INT:int" "ID:y" "=:=" "(:(" "ICON:9" "):)" ";:;" ])

    # ...but it may not be MADE by one. The test is on the raw next token,
    # which is what gcc does: `F LP 3 )' comes out as `F ( 3 )'.
    (e "a `(' that a macro would expand to does not open an argument list"
      "#define LP (\n#define F(x) (x)\nint y = F LP 3 );\n"
      [ "INT:int" "ID:y" "=:=" "ID:F" "(:(" "ICON:3" "):)" ";:;" ])

    # WHAT THIS DOES AND DOES NOT SAY, because the name it wanted to have
    # would have been a lie. It says an argument that names a macro comes out
    # expanded; it does NOT say the argument was expanded BEFORE it was
    # substituted, because the raw `V' would be rescanned inside the frame and
    # expand there anyway. The case that separates pre-expansion from
    # rescanning is the two-level stringify idiom below -- `#' takes its
    # operand raw, so `XSTR(V)' is "7" only if the argument was expanded on
    # the way in. Found by mutating rather than by reading.
    (e "an argument that names a macro comes out expanded"
      "#define V 7\n#define ID(x) x\nint y = ID(V);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:7" ";:;" ])

    (e "a nested invocation inside an argument is expanded too"
      "#define ID(x) x\nint y = ID(ID(ID(5)));\n"
      [ "INT:int" "ID:y" "=:=" "ICON:5" ";:;" ])

    # The body is `a * 10 + b' and not `max(a,b)', which is what it was until
    # review pointed out that max is COMMUTATIVE: with the two parameters
    # substituted into each other's places the case came out byte-identical,
    # which is ir/unsig.c's divisor of 7 wearing a `#if' hat, in the file
    # whose own header warns about it.
    (e "a function-like macro is expanded inside a #if expression"
      "#define BLEND(a,b) ((a) * 10 + (b))\n#if BLEND(3,5) == 35\nint yes;\n#else\nint no;\n#endif\n"
      [ "INT:int" "ID:yes" ";:;" ])

    # ---- the # operator --------------------------------------------------
    (e "the # operator stringifies its argument as it was written"
      "#define STR(x) #x\nchar *s = STR(a + b);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a + b\"" ";:;" ])

    (e "# collapses internal whitespace to exactly one space"
      "#define STR(x) #x\nchar *s = STR(a     +      b);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a + b\"" ";:;" ])

    (e "# keeps adjacency where the argument was written with none"
      "#define STR(x) #x\nchar *s = STR(a+b);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a+b\"" ";:;" ])

    # A comment is whitespace, so it is ONE space -- and it is one space even
    # when it spans a newline, because a newline inside a block comment does
    # not end the logical line the invocation is on (poc/02-lexer's `nlAt').
    (e "a comment inside the argument is whitespace, and so is one space"
      "#define STR(x) #x\nchar *s = STR(a/* two\n   words */b);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a b\"" ";:;" ])

    # C89 6.8.3.2 inserts a `\' before every `"' and `\' inside a literal.
    # The string-literal case is in the differential corpus, where gcc checks
    # it rather than a hand-spelled expectation; this is the character
    # constant, where the escaping is still visible and still readable.
    (e "# escapes the backslash inside a character constant"
      "#define STR(x) #x\nchar *s = STR('\\n');\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"'\\\\n'\"" ";:;" ])

    (e "the argument of # is NOT macro-expanded first"
      "#define V 7\n#define STR(x) #x\nchar *s = STR(V);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"V\"" ";:;" ])

    (e "and the two-level idiom is what expands it"
      "#define V 7\n#define STR(x) #x\n#define XSTR(x) STR(x)\nchar *s = XSTR(V);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"7\"" ";:;" ])

    # THE CASE THAT CAUGHT A SILENT MISCOMPILE, found by cross-model review.
    # `#' reproduces the spelling its argument was WRITTEN with, and an
    # argument can come out of another macro's replacement list -- so the
    # tokens a replacement list hands on have to carry their own trivia. An
    # expansion that gave every body token one space instead produced
    # "file . c : 12", which is a wrong string literal in the compiled
    # program with no diagnostic anywhere. Every other stringify case here
    # passes an argument written at the USE site, where the trivia is the
    # source's own, so none of them could see it.
    (e "# reproduces the spelling of an argument that came out of a macro body"
      "#define Q(x) #x\n#define WHERE Q(file.c:12)\nchar *s = WHERE;\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"file.c:12\"" ";:;" ])

    (e "and the same for an argument whose tokens are punctuators"
      "#define Q(x) #x\n#define P Q(a->b)\nchar *s = P;\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a->b\"" ";:;" ])

    (e "an empty argument stringifies to an empty literal"
      "#define STR(x) #x\nchar *s = STR();\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"\"" ";:;" ])

    # ---- the ## operator -------------------------------------------------
    (e "the ## operator pastes two tokens into one"
      "#define CAT(a,b) a##b\nint y = CAT(1,2);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:12" ";:;" ])

    # THIS IS THE RULE task-013.02's criterion #3 STATES THE OTHER WAY ROUND,
    # and the criterion is the half that is wrong. C89 3.8.3.3 says "the
    # resulting token is available for further macro replacement";
    # lcc/cpp/macro.c's expand() runs doconcat() and then backs its row up
    # over everything it inserted, so the pasted token is rescanned; and
    # `gcc -std=c89 -E -P' turns this very source into `int y = 42;'. Since
    # criterion #5 is a differential against gcc, the two criteria cannot
    # both hold, so the standard's rule is what is implemented and the
    # criterion is left for the author to settle.
    (e "the token a paste produces IS re-examined for macro names"
      "#define CAT(a,b) a##b\n#define XY 42\nint y = CAT(X,Y);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:42" ";:;" ])

    # WHAT THIS CAN AND CANNOT SEE. Concatenation is associative, so `123'
    # comes out whether the chain folds left or right; what the case does
    # discriminate is the ORDER OF THE OPERANDS, because concatenation is not
    # commutative. A fold that pasted each new operand in front of the
    # accumulator gives `321'. The name says operands rather than
    # associativity so the next reader does not trust a claim it cannot make.
    (e "a chain of pastes joins its operands in the order they were written"
      "#define THREE(a,b,c) a##b##c\nint y = THREE(1,2,3);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:123" ";:;" ])

    # The standard's placemarker, without a token to stand for it: an empty
    # operand leaves the other side alone. `A' is then rescanned, which is
    # what makes this 1 rather than `A'.
    (e "a paste with an empty operand keeps the other side"
      "#define CAT(a,b) a##b\n#define A 1\nint y = CAT(A,);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:1" ";:;" ])

    (e "and with both operands empty it produces nothing"
      "#define CAT(a,b) a##b\nint y[] = { CAT(,) 5 };\n"
      [ "INT:int" "ID:y" "[:[" "]:]" "=:=" "{:{" "ICON:5" "}:}" ";:;" ])

    # The other half of "except where it is an operand of # or ##": if the
    # operand were expanded first this would be `7x'.
    (e "the operand of ## is not macro-expanded first either"
      "#define V 7\n#define CAT(a,b) a##b\nint y = CAT(V,x);\n"
      [ "INT:int" "ID:y" "=:=" "ID:Vx" ";:;" ])

    # `##' is two `#' tokens to poc/02-lexer, so what makes them ONE operator
    # is that nothing stands between them -- and a line continuation is
    # nothing, after ISO C's phase 2. gcc reads this as `a##b' and so does
    # this preprocessor; the `glue' flag is what carries the difference.
    (e "a ## split by a line continuation is still one ## operator"
      "#define CAT(a,b) a#\\\n#b\nint y = CAT(1,2);\n"
      [ "INT:int" "ID:y" "=:=" "ICON:12" ";:;" ])

    (e "an object-like macro may paste as well"
      "#define OBJCAT a##b\n#define ab 9\nint y = OBJCAT;\n"
      [ "INT:int" "ID:y" "=:=" "ICON:9" ";:;" ])

    (e "a paste may make a punctuator out of two"
      "#define CAT(a,b) a##b\nint y;\ny CAT(+,+);\n"
      [ "INT:int" "ID:y" ";:;" "ID:y" "INCR:++" ";:;" ])

    # ---- the blue paint, now that a macro can take arguments -------------
    (e "a function-like macro does not re-expand inside its own expansion"
      "#define REC(x) REC(x) + 1\nint y = REC(2);\n"
      [ "INT:int" "ID:y" "=:=" "ID:REC" "(:(" "ICON:2" "):)" "+:+" "ICON:1" ";:;" ])

    (e "two function-like macros that name each other stop on the second"
      "#define PING(x) PONG(x)\n#define PONG(x) PING(x)\nint y = PING(2);\n"
      [ "INT:int" "ID:y" "=:=" "ID:PING" "(:(" "ICON:2" "):)" ";:;" ])

    # The paint has to be on the token `##' MANUFACTURED, not merely on the
    # tokens the body was written with, or this expands for ever.
    (e "a name that a paste rebuilds is painted too"
      "#define CAT(a,b) a##b\n#define SELF CAT(SE,LF)\nint y = SELF;\n"
      [ "INT:int" "ID:y" "=:=" "ID:SELF" ";:;" ])

    (e "a painted name followed by `(' is not an invocation"
      "#define ID(x) x\nint y = ID(ID)(7);\n"
      [ "INT:int" "ID:y" "=:=" "ID:ID" "(:(" "ICON:7" "):)" ";:;" ])

    # ---- FIVE SILENT MISCOMPILES A CROSS-MODEL REVIEW FOUND --------------
    #
    # Every one of these passed the 48-unit gcc differential, which says the
    # corpus lacked the shapes that distinguish them and not that the
    # differential is broken. They are here AND in the corpus now.
    #
    # THE FIRST IS NOT A WHITESPACE QUESTION AND IS THE WORST OF THEM: it
    # changes which code is compiled. `A' arrives from expanding AB and
    # carries the paint {AB}; `B' comes from the source and does not. The
    # pasted token's hide set is C89 6.8.3.4's INTERSECTION of the two, so AB
    # is not hidden and is rescanned; union them instead and the expansion is
    # `1+AB', the leftover identifier evaluates to 0, and this `#if' is FALSE
    # where gcc's is TRUE. A wrong arm, silently.
    #
    # It also refutes a claim made in this project's own notes -- that hiding
    # too much is always LOUD because the frontend refuses the leftover name.
    # In a `#if' there is no frontend: an identifier that is left standing is
    # worth zero and the arithmetic simply comes out different.
    (e "a paste inherits only the paint its two operands share"
      "#define AB 1+A\n#define CAT(a,b) a##b\n#define EXP(a,b) CAT(a,b)\n#if EXP(AB,B) == 2\nint taken;\n#else\nint untaken;\n#endif\n"
      [ "INT:int" "ID:taken" ";:;" ])

    # THE SAME SHAPE AS TEXT, and it is here because the `#if' above cannot
    # tell three different defects apart: a paste that inherits the union, an
    # argument that was not expanded before substitution, and a chain that
    # folds the wrong way all leave a leftover identifier, all of which are
    # zero, so all three take the `#else' and produce the same three tokens.
    # As text the three come out as `1 + AB', `ABB' and `B1 + A', which is
    # what lets the mutation for each name its own symptom.
    (e "and the same paste written where its expansion is visible"
      "#define AB 1+A\n#define CAT(a,b) a##b\n#define EXP(a,b) CAT(a,b)\nint z = EXP(AB,B);\n"
      [ "INT:int" "ID:z" "=:=" "ICON:1" "+:+" "ICON:1" "+:+" "ID:A" ";:;" ])

    # THE OTHER FOUR ARE ONE RULE ASKED IN FOUR PLACES: trivia belongs to the
    # POSITION and not to the token. Each of these was a wrong string literal
    # in the compiled program with no diagnostic behind it.
    #
    # The argument takes the boundary its PARAMETER OCCURRENCE had, not the
    # one it was written with at the invocation: `b' follows `(' with nothing
    # in front of it, and `x' in `Q(a x)' has a space.
    (e "a stringified argument takes the spacing of the parameter it replaced"
      "#define Q(x) #x\n#define F(x) Q(a x)\nchar *s = F(b);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a b\"" ";:;" ])

    # THE TWO SOURCES OF A SEPARATOR, SIDE BY SIDE IN ONE ARGUMENT. `p' takes
    # the boundary the PARAMETER OCCURRENCE had and `q' keeps the one it was
    # written with at the INVOCATION, so "a p q" has one of each in it. That
    # is also what tells a preprocessor that lost the parameter's boundary
    # ("ap q") from one that stopped collapsing whitespace at all ("apq") --
    # a case that used only the first kind gives "ab" under both.
    (e "an argument's separators come from two places at once"
      "#define Q(x) #x\n#define F(x) Q(a x)\nchar *s = F(p q);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a p q\"" ";:;" ])

    # And a deleted element does not delete its boundary: `x' went away and
    # the space in front of it is still the boundary between `a' and `+'.
    (e "an empty argument leaves its boundary behind"
      "#define Q(x) #x\n#define G(x) Q(a x+b)\nchar *s = G();\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a +b\"" ";:;" ])

    # The first token of a replacement list takes the INVOCATION's boundary:
    # the space in `#define V 7' is written before the list, so it is not in
    # it, and `V' in `a+V' has none.
    (e "the first token of a replacement list takes the invocation's spacing"
      "#define Q(x) #x\n#define XQ(x) Q(x)\n#define V 7\nchar *s = XQ(a+V);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a+7\"" ";:;" ])

    # A token `##' manufactured occupies the position of its LEFT operand,
    # so it takes that operand's boundary rather than a default space. Note
    # that `lexAll' cannot catch this one: "z+ foo" is a perfectly good
    # string literal, so validating that the result lexes as one SCON says
    # nothing about whether its CONTENT is right.
    (e "a pasted token takes the boundary of the operand it replaced"
      "#define Q(x) #x\n#define F(p,q) Q(z+p##q)\nchar *s = F(f,oo);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"z+foo\"" ";:;" ])

    # AND THE SAME RULE ONE LEVEL IN. When the left operand is more than one
    # token the pasted token is NOT the first of its chain, so the chain's
    # boundary does not reach it and it has to take the boundary of the token
    # it replaced -- the LAST of the left operand. The pair is written both
    # ways round because only one of them discriminates: with `a b' the token
    # replaced had a space and the default space is right by accident, and
    # with `a+b' it had none.
    (e "a pasted token deep in a sequence takes the boundary of the token it replaced"
      "#define Q(x) #x\n#define F(p,q) Q(z+p##q)\nchar *s = F(a+b,c);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"z+a+bc\"" ";:;" ])

    (e "and the accident that hides it: a left operand whose last token had a space"
      "#define Q(x) #x\n#define F(p,q) Q(z+p##q)\nchar *s = F(a b,c);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"z+a bc\"" ";:;" ])

    # AND THE FIFTH IS A DIFFERENT QUESTION: not whose boundary it is, but
    # whether it is whitespace at all. ISO C's phase 2 removes a
    # backslash-newline WITHOUT putting a space in its place, which is what
    # poc/02-lexer's `glue' flag records. Both places it can appear:
    (e "a continuation inside a stringified argument is not whitespace"
      "#define Q(x) #x\nchar *s = Q(a\\\n+b);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a+b\"" ";:;" ])

    (e "and neither is one inside the replacement list the argument came from"
      "#define Q(x) #x\n#define XQ(x) Q(x)\n#define B a\\\n+b\nchar *s = XQ(B);\n"
      [ "CHAR:char" "*:*" "ID:s" "=:=" "SCON:\"a+b\"" ";:;" ])

    # A KNOWN DIVERGENCE, PINNED HERE SO IT IS NOT SILENT (task-080). C89
    # 6.8.3.4 gives the replacement of a FUNCTION-LIKE macro the hide set
    # `(HS(name) INTERSECT HS(rparen)) UNION {name}'. The intersection is the
    # only thing that lets a name stop being hidden when an invocation reaches
    # out of the frame it was born in and into the source, and this expander
    # does not compute it -- the closing parenthesis's hide set is thrown away
    # by `gather'. So we hide MORE than the standard does and stop a level
    # early. gcc gives `2*9*g' for this; we give `2*f(9)'.
    #
    # It is under-expansion rather than a wrong value -- the name is left
    # standing, and the frontend then refuses it as undeclared -- but it is a
    # real divergence and the differential corpus deliberately does not carry
    # it, because the corpus is meant to be green. This case has to CHANGE
    # when task-080 lands rather than quietly start failing.
    (e "task-080: a macro is hidden where the standard would have unhidden it"
      "#define f(a) a*g\n#define g(a) f(a)\nint z = f(2)(9);\n"
      [ "INT:int" "ID:z" "=:=" "ICON:2" "*:*" "ID:f" "(:(" "ICON:9" "):)" ";:;" ])
  ];

  # ---- #if constant expressions ----------------------------------------
  conditions = [
    (c "integer precedence: multiply binds tighter than add" "1 + 2 * 3 == 7" true)
    (c "the wrong precedence would give 9" "1 + 2 * 3 == 9" false)
    (c "division associates left" "8 / 4 / 2 == 1" true)
    (c "parentheses override precedence" "(1 + 2) * 3 == 9" true)
    (c "remainder" "17 % 5 == 2" true)
    (c "division truncates toward zero, as C does" "-7 / 2 == -3" true)
    (c "and so does the remainder" "-7 % 2 == -1" true)
    (c "unary minus" "-5 + 5 == 0" true)
    (c "unary plus" "+5 == 5" true)
    (c "the complement of zero is all ones" "~0 == -1" true)
    (c "logical not" "!0" true)
    (c "logical not of a non-zero value" "!7" false)
    (c "bitwise and" "(6 & 3) == 2" true)
    (c "bitwise or" "(6 | 3) == 7" true)
    (c "bitwise exclusive or" "(6 ^ 3) == 5" true)
    (c "bitwise or binds looser than exclusive or" "(1 | 2 ^ 3) == 1" true)
    (c "a left shift" "(1 << 4) == 16" true)
    (c "a right shift" "(256 >> 4) == 16" true)
    (c "a right shift of a negative value is arithmetic, not a division" "(-1 >> 1) == -1" true)
    (c "and truncating division would have given zero" "(-1 / 2) == 0" true)
    (c "shifting binds looser than adding" "(1 << 2 + 1) == 8" true)
    (c "the conditional operator takes its then arm" "(2 ? 10 : 20) == 10" true)
    (c "and its else arm" "(0 ? 10 : 20) == 20" true)
    (c "a nested conditional operator" "(1 ? 0 ? 1 : 2 : 3) == 2" true)
    (c "relational operators" "3 > 2 && 2 >= 2 && 1 < 2 && 2 <= 2" true)
    (c "equality binds looser than relational" "1 < 2 == 1" true)
    (c "&& binds tighter than ||" "0 && 0 || 1" true)
    (c "a character constant is an integer" "'a' == 97" true)
    (c "an escape in a character constant" "'\\n' == 10" true)
    (c "plain char is signed on this target, so '\\377' is -1" "'\\377' == -1" true)

    # Signedness. This is the pair ir/unsig.c's divisor of 7 would have hidden:
    # the same comparison with and without a `u' on one operand.
    (c "a signed comparison" "-1 < 0" true)
    (c "one unsigned operand makes the comparison unsigned" "-1 < 0u" false)
    (c "and the same comparison the other way round" "-1 > 0u" true)
    (c "unsigned division" "(7u / 2u) == 3" true)
    # The pair above is blind and the corpus's was the same pair: both
    # operands are positive, so signed and unsigned division give the same
    # answer and the conversion is never exercised. Demonstrated by review --
    # replacing the unsigned branch with the signed one passed every check
    # here and all 43 differential units. A NEGATIVE left operand is what
    # separates them: as unsigned, -1 is 4294967295 and the quotient is huge;
    # as signed, -1 / 2 truncates to 0. ir/unsig.c's divisor of 7, again.
    (c "an unsigned divide converts a negative left operand first" "(-1 / 2u) > 1" true)
    (c "and so does an unsigned remainder" "(-1 % 2u) == 1" true)
    # The two above are also broken by a mutation that stops the arithmetic
    # WRAPPING, because `-1' reaches its bit pattern through `wrap'. This one
    # does not: plain char is signed on this target, so `'\377'' arrives from
    # poc/06-constants already negative and is converted without wrapping --
    # which leaves the conversion as the only thing that can be wrong.
    (c "an unsigned divide converts without needing the wrap" "('\\377' / 2u) > 1" true)
    (c "a large unsigned value compares above a small one" "4294967295u > 1" true)
    # Both operands matter, and this is the pair that says so: the left one is
    # SIGNED and above INT_MAX, the right one unsigned, so the conversion has
    # to be driven by the right operand's type. gcc agrees about this one --
    # it is the C89-versus-intmax width that we differ on, not the usual
    # arithmetic conversions.
    (c "a signed value above INT_MAX compares equal to its unsigned twin" "2147483647 + 1 == 2147483648u" true)
    (c "an L suffix does not change the value" "10L == 10" true)
    (c "a UL suffix makes it unsigned" "(0UL - 1) > 0" true)

    # WHERE WE DIFFER FROM GCC AND MEAN TO. C89 6.8.1 computes `#if' in
    # long/unsigned long, and long is 4 bytes here, so these wrap at 32 bits.
    # gcc has used intmax_t since C99 and gets the other answer for all three.
    (c "arithmetic wraps at 32 bits, as C89 on a 4-byte long requires" "2147483647 + 1 < 0" true)
    (c "a left shift into the sign bit is negative" "(1 << 31) < 0" true)
    (c "and shifting it back out again is arithmetic" "(1 << 31 >> 31) == -1" true)
    (c "an unsigned add wraps to zero rather than growing a 33rd bit" "4294967295u + 1 == 0" true)
    # The one that cannot be done the naive way at all: (2^32-1)^2 is about
    # 1.8e19, past the 63-bit ceiling where Nix THROWS "integer overflow"
    # (decision-001). mulmod multiplies in 16-bit halves so that no
    # intermediate ever gets there, and this is the case that reaches it.
    (c "an unsigned multiply that would overflow a Nix integer" "(4294967295u * 4294967295u) == 1" true)

    # Short-circuiting is not an optimisation here: the right operand must
    # not be EVALUATED, or these divide by zero and the whole file throws.
    (c "&& does not evaluate its right operand when the left is false" "0 && (1 / 0)" false)
    (c "|| does not evaluate its right operand when the left is true" "1 || (1 / 0)" true)
    (c "the conditional operator evaluates only the arm it takes" "(0 ? (1 / 0) : 5) == 5" true)

    # defined(), in a table of its own shape: the operand exists or it does not.
    (c "defined on a name that was never defined is false" "defined FOO" false)
    (c "a long chain of ors" "0 || 0 || 0 || 1" true)
    (c "a long chain of ands" "1 && 1 && 1 && 0" false)
  ];

  # ---- line numbers and linemarkers -------------------------------------
  # The differential compares token streams, which is exactly what a `#line'
  # does NOT change. These are the cases that would otherwise have no test.
  relocations = [
    {
      what = "#line moves the numbering of every line after it";
      src = "int a;\n#line 100\nint b;\nint c;\n";
      lines = [ "1:int" "1:a" "1:;" "100:int" "100:b" "100:;" "101:int" "101:c" "101:;" ];
      render = "# 1 \"t.c\"\nint a;\n# 100 \"t.c\"\n int b;\n int c;\n";
    }
    {
      what = "#line with a file name changes the file too";
      src = "int a;\n#line 100 \"other.c\"\nint b;\n";
      lines = [ "1:int" "1:a" "1:;" "100:int" "100:b" "100:;" ];
      render = "# 1 \"t.c\"\nint a;\n# 100 \"other.c\"\n int b;\n";
    }
    {
      what = "the `# n \"file\"' spelling lcc's resynch() reads is accepted too";
      src = "int a;\n# 42 \"in.c\"\nint b;\n";
      lines = [ "1:int" "1:a" "1:;" "42:int" "42:b" "42:;" ];
      render = "# 1 \"t.c\"\nint a;\n# 42 \"in.c\"\n int b;\n";
    }
    {
      what = "a directive line leaves a gap that the next linemarker closes";
      src = "int a;\n#define N 1\nint b = N;\n";
      lines = [ "1:int" "1:a" "1:;" "3:int" "3:b" "3:=" "3:1" "3:;" ];
      render = "# 1 \"t.c\"\nint a;\n# 3 \"t.c\"\n int b = 1;\n";
    }
    {
      what = "a skipped group leaves a gap too";
      src = "int a;\n#if 0\nint b;\n#endif\nint c;\n";
      lines = [ "1:int" "1:a" "1:;" "5:int" "5:c" "5:;" ];
      render = "# 1 \"t.c\"\nint a;\n# 5 \"t.c\"\n int c;\n";
    }
    {
      what = "an expansion carries the line of its USE, not of its definition";
      src = "#define N 1\nint a;\nint b;\nint c = N;\n";
      lines = [ "2:int" "2:a" "2:;" "3:int" "3:b" "3:;" "4:int" "4:c" "4:=" "4:1" "4:;" ];
      render = "# 2 \"t.c\"\n int a;\n int b;\n int c = 1;\n";
    }
    {
      what = "a logical line spanning two physical ones is rendered as one, and the marker corrects it";
      src = "int a = 1 + \\\n    2;\nint b;\n";
      lines = [ "1:int" "1:a" "1:=" "1:1" "1:+" "2:2" "2:;" "3:int" "3:b" "3:;" ];
      render = "# 1 \"t.c\"\nint a = 1 + 2;\n# 3 \"t.c\"\n int b;\n";
    }
    {
      what = "adjacency survives rendering, which is what keeps `<<=' one operator to lcc";
      src = "int a;\na <<= 2;\na << = 2;\n";
      lines = [ "1:int" "1:a" "1:;" "2:a" "2:<<" "2:=" "2:2" "2:;" "3:a" "3:<<" "3:=" "3:2" "3:;" ];
      render = "# 1 \"t.c\"\nint a;\n a <<= 2;\n a << = 2;\n";
    }
    {
      # AN ARGUMENT TAKES THE BOUNDARY ITS PARAMETER HAD, not the one it was
      # written with at the invocation. All three invocations below pass the
      # same argument with the same (empty) spacing in front of it, and the
      # three come out differently because the three replacement lists put
      # different whitespace in front of the parameter. That is C89 6.8.3's
      # rule and gcc's output byte for byte -- `a b;', `a+b;', `- 1;'.
      #
      # An earlier version of this case asserted the opposite, that an
      # argument keeps its own spacing, and passed. It was wrong about the
      # rule and the token streams are identical either way, so nothing but
      # the exact text could have said so -- which is why this case is here
      # and not in the differential.
      what = "an argument takes the boundary its parameter occurrence had";
      src = "#define AFTER(x) a x\n#define TIGHT(x) a+x\n#define MINUS(x) - x\nAFTER(b);\nTIGHT(b);\nMINUS(1);\n";
      lines = [ "4:a" "4:b" "4:;" "5:a" "5:+" "5:b" "5:;" "6:-" "6:1" "6:;" ];
      render = "# 4 \"t.c\"\n a b;\n a+b;\n - 1;\n";
    }
    {
      # And the same question asked of `##', which is the operator that
      # deliberately CREATES a token across a boundary. `1 CAT(+,+)+ 2'
      # pastes `++' and then meets a `+' that was written with no space:
      # `+++' re-lexes to `++' and `+', so it may be written closed up, and
      # gcc renders it closed up too.
      what = "a pasted token is rendered against its neighbour only where the two still lex apart";
      src = "#define CAT(a,b) a##b\nint i;\ni = 1 CAT(+,+)+ 2;\n";
      lines = [ "2:int" "2:i" "2:;" "3:i" "3:=" "3:1" "3:++" "3:+" "3:2" "3:;" ];
      render = "# 2 \"t.c\"\n int i;\n i = 1 +++ 2;\n";
    }
  ];

  # ---- the input the memory ladder measures -----------------------------
  # n functions, each one using object-like AND function-like macros -- the
  # second so the ladder measures what slice 2 added rather than what slice 1
  # cost -- and each sitting inside a conditional, on top of a macro table
  # whose entries name each other. Memory, not speed, is
  # what this project spends (decision-001, decision-007), and the figure that
  # matters is what the preprocessor adds to the token list the lexer already
  # built -- so memory.py measures the same source twice, once lexed and once
  # preprocessed, and reports the difference.
  #
  # The conditional arms differ in what they emit, for the reason the tables
  # above do: a ladder over input that preprocesses to itself would measure a
  # preprocessor that did nothing.
  synthetic = n:
    let
      defs = ''
        #define ZERO 0
        #define ONE 1
        #define STEP (ONE + ONE)
        #define LIMIT 100
        #define SCALED(v) ((v) * SCALE + LIMIT)
        #define TAG(n) tmp ## n
        #if LIMIT > 10
        #define SCALE STEP
        #else
        #define SCALE ONE
        #endif
      '';
      fn = i: ''
        int f${toString i}(int a)
        {
            int b;
            int TAG(${toString i});
            b = SCALED(a);
            TAG(${toString i}) = b + ZERO;
        #if LIMIT > 50
            b = b + ONE;
        #else
            b = b - ONE * ZERO;
        #endif
            return b + TAG(${toString i});
        }
      '';
    in
    defs + b.concatStringsSep "" (b.genList fn n);

  # The other axis, and the one that is NOT linear. An attrset updated with
  # `//' copies every existing binding, so n `#define's copy n^2/2 of them --
  # poc/07-parser/store.nix's finding, wearing an attrset hat instead of a
  # list one. `synthetic' above holds the macro count at six however many
  # lines it makes, so it cannot see this; this one holds the LINES down and
  # grows the table. task-072 carries what it would take to fix.
  #
  # One short function at the end, so the table is not merely built but
  # LOOKED UP, and so the file produces tokens at all.
  syntheticMacros = n:
    b.concatStringsSep ""
      (b.genList (i: "#define M${toString i} ${toString i}\n") n)
    + "int f(int a)\n{\n    return a + M0 + M${toString (n - 1)};\n}\n";

  # ---- what the macro table holds ---------------------------------------
  # The token stream cannot see a macro that is defined and never used, so a
  # `#define' inside a group that should have been skipped would be invisible
  # until something happened to use it.
  #
  # `params' is null for an object-like macro and a LIST for a function-like
  # one, and the empty list is a third thing again: `#define Z() 1' takes no
  # arguments and `#define Z 1' takes no argument list at all. Nothing in a
  # token stream distinguishes a macro whose parameters were dropped from one
  # that never had any until something invokes it, which is why the table
  # carries them.
  tables = [
    {
      what = "a #define inside a skipped group does not reach the table";
      src = "#if 0\n#define SKIPPED 1\n#endif\n#define KEPT 2\n";
      macros = { KEPT = { params = null; body = [ "2" ]; }; };
    }
    {
      what = "#undef removes the entry rather than emptying it";
      src = "#define A 1\n#define B 2\n#undef A\n";
      macros = { B = { params = null; body = [ "2" ]; }; };
    }
    {
      what = "the body is stored as tokens, in order";
      src = "#define E 1 + 2 * 3\n";
      macros = { E = { params = null; body = [ "1" "+" "2" "*" "3" ]; }; };
    }
    {
      what = "an empty body is an empty token list, not an absent entry";
      src = "#define E\n";
      macros = { E = { params = null; body = [ ]; }; };
    }
    {
      what = "a function-like macro's parameters are stored, in order, beside its body";
      src = "#define F(a, b) b - a\n";
      macros = { F = { params = [ "a" "b" ]; body = [ "b" "-" "a" ]; }; };
    }
    {
      # The three shapes, side by side, because they differ only in the
      # parameter list: `#define Z 1' is object-like, `#define Z() 1' takes
      # an empty argument list, and `#define Z (1)' is object-like again with
      # a parenthesis in its body. C89 6.8.3 turns on one space.
      what = "an empty parameter list is not the same thing as no parameter list";
      src = "#define P 1\n#define Q() 1\n#define R (1)\n";
      macros = {
        P = { params = null; body = [ "1" ]; };
        Q = { params = [ ]; body = [ "1" ]; };
        R = { params = null; body = [ "(" "1" ")" ]; };
      };
    }
    {
      # `#' and `##' stay in the stored body as the tokens they were written
      # with; what is compiled once is the PLAN beside them, and the body is
      # what a redefinition is compared against.
      what = "the # and ## operators stay in the body as written";
      src = "#define S(x) # x ## y\n";
      macros = { S = { params = [ "x" ]; body = [ "#" "x" "#" "#" "y" ]; }; };
    }
  ];
}
