# Hand-written expectations for the preprocessor.
#
# WHAT LIVES HERE RATHER THAN IN THE DIFFERENTIAL. oracle.nix compares 43
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
  ];

  # ---- the input the memory ladder measures -----------------------------
  # n functions, each one using macros and sitting inside a conditional, on
  # top of a macro table whose entries name each other. Memory, not speed, is
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
            b = a * SCALE + LIMIT;
        #if LIMIT > 50
            b = b + ONE;
        #else
            b = b - ONE * ZERO;
        #endif
            return b + ZERO;
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
  tables = [
    {
      what = "a #define inside a skipped group does not reach the table";
      src = "#if 0\n#define SKIPPED 1\n#endif\n#define KEPT 2\n";
      macros = { KEPT = [ "2" ]; };
    }
    {
      what = "#undef removes the entry rather than emptying it";
      src = "#define A 1\n#define B 2\n#undef A\n";
      macros = { B = [ "2" ]; };
    }
    {
      what = "the body is stored as tokens, in order";
      src = "#define E 1 + 2 * 3\n";
      macros = { E = [ "1" "+" "2" "*" "3" ]; };
    }
    {
      what = "an empty body is an empty token list, not an absent entry";
      src = "#define E\n";
      macros = { E = [ ]; };
    }
  ];
}
