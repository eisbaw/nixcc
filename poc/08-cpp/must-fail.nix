# Must-fail suite: what this preprocessor REFUSES, and the near-identical
# input it must still accept.
#
# cases.nix and oracle.nix can only compare input that preprocesses
# successfully, so every refusal needs its own check here. Without one, a
# preprocessor that quietly ignored `#include', invented a value for a
# function-like macro, or treated `#endif' with nothing open as a no-op would
# pass every other stage in this PoC -- the differential would simply never be
# run on it.
#
# THE PAIRING IS CODE, NOT A COMMENT. Every entry carries BOTH the input that
# must be refused and the control that must still go through, and the control
# differs from the reject in exactly one thing. poc/07-parser/must-fail.nix
# learned this the hard way: two independent lists and a paragraph claiming
# they were paired had drifted to 17 rejects against 14 controls.
#
# AND `expect' IS DISTINCT PER ENTRY. A fragment shared by two entries cannot
# tell them apart. A fragment that names a TASK or a DECISION is the robust
# kind; an ordinary English word is not, because messages.sh greps nix's
# output.
#
# WHICH REFUSALS NAME A TASK. Everything this slice DEFERS names the slice
# that will do it -- task-013.02 for function-like macros and for `#'/`##',
# task-013.03 and task-070 for `#include', task-014 for a directive the
# minimal preprocessor does not implement at all, task-008 for the phase-2
# splice, task-071 for the nesting cap. Refusals of MALFORMED INPUT -- an
# `#endif' with nothing open, a `#line' with no number -- defer nothing and
# name only what is wrong, because pointing a user at a task that will never
# be done is worse than pointing them at nothing.
#
# WHY EVERY REFUSAL IS A `throw' AND NEVER AN ATTRIBUTE MISS: builtins.tryEval
# does NOT catch an attribute-missing error (task-037). It propagates through
# and takes this whole file down with it, so a refusal spelled `table.${k}'
# would escape every check here. cpp.nix's lookups that can miss are
# `isUnsigned' and the macro table, and both carry an explicit `or'.
#
# `expect' cannot be checked here: tryEval returns success and value, never the
# message. messages.sh re-evaluates each reject and greps for it.
let
  b = builtins;
  cpp = import ./cpp.nix;

  # Declared and checked for EQUALITY. poc/lib/mutant.sh's argument about
  # mutation counts applies to tables too.
  declaredCases = 35;

  # A chain of n macros each naming the next. Built rather than written out:
  # the cap is 200 deep and nobody is typing that.
  chain = n:
    b.concatStringsSep "" (b.genList (i: "#define M${toString i} M${toString (i + 1)}\n") n)
    + "#define M${toString n} 1\nint x = M0;\n";

  cases = [
    # --- the later slices, each naming the slice ------------------------
    {
      what = "#include with angle brackets";
      src = "#include <stdio.h>\nint x;\n";
      # The same directive inside a group that is not compiled is inert, which
      # is both the control and the rule that makes `#if 0' fencing work.
      control = "#if 0\n#include <stdio.h>\n#endif\nint x;\n";
      expect = "`#include' is task-013.03";
    }
    {
      what = "#include names the decision that blocks it";
      src = "#include \"local.h\"\nint x;\n";
      control = "#if 0\n#include \"local.h\"\n#endif\nint x;\n";
      expect = "task-070";
    }
    {
      what = "a function-like macro";
      # The control differs by ONE character: a space before the `(' makes the
      # same text an object-like macro whose body starts with a parenthesis,
      # which is C89's rule and the only thing that tells the two apart.
      src = "#define F(x) x + 1\nint y = F(2);\n";
      control = "#define F (x) x + 1\nint y = 2;\n";
      expect = "is a function-like macro, which slice 1 does not do";
    }
    {
      what = "the # stringify operator in a replacement list";
      # Object-like on both sides, so the one difference is the `#'. gcc
      # allows a `#' in an object-like body, where it means nothing; we
      # refuse it, because a `#' that reached the parser would be reported
      # as unpreprocessed input rather than as the operator it was meant to
      # be.
      src = "#define S # x\nint y;\n";
      control = "#define S x\nint y;\n";
      expect = "stringify is task-013.02";
    }
    {
      what = "the ## paste operator in a replacement list";
      src = "#define J a ## b\nint y;\n";
      control = "#define J a b\nint y;\n";
      expect = "token paste is task-013.02";
    }
    {
      what = "a directive the minimal preprocessor does not implement";
      src = "#pragma once\nint x;\n";
      control = "#if 0\n#pragma once\n#endif\nint x;\n";
      expect = "`#pragma' is not a directive slice 1 implements";
    }
    {
      what = "#error, which is a directive and still not one of ours";
      src = "#error this build is not supported\nint x;\n";
      control = "#if 0\n#error this build is not supported\n#endif\nint x;\n";
      expect = "`#error' is not a directive slice 1 implements";
    }
    {
      # The fragment here is the TASK, not the directive's name: task-014 is
      # where what the minimal preprocessor leaves out is recorded, and a
      # refusal that stopped naming it would leave the omission unfiled. The
      # two cases above pin the directive's name; this one pins the task.
      what = "an unimplemented directive still points at the task that records the omission";
      src = "#ident \"tag\"\nint x;\n";
      control = "#if 0\n#ident \"tag\"\n#endif\nint x;\n";
      expect = "tracked in task-014";
    }
    {
      what = "a continuation that joins two token characters";
      # ISO C phase 2 makes `abcd' of this; poc/02-lexer makes `ab' and `cd'.
      # The control puts one space before the backslash, which makes the two
      # readings agree and is the whole difference.
      src = "int ab\\\ncd;\n";
      control = "int ab \\\ncd;\n";
      expect = "task-008";
    }
    {
      what = "a macro chain nested past the expansion cap";
      src = chain 250;
      control = chain 50;
      expect = "task-071";
    }

    # --- the conditional stack ------------------------------------------
    {
      what = "#endif with nothing open";
      src = "int x;\n#endif\n";
      control = "int x;\n#if 1\n#endif\n";
      expect = "`#endif' with no matching `#if'";
    }
    {
      what = "#else with nothing open";
      src = "int x;\n#else\nint y;\n#endif\n";
      control = "#if 0\nint x;\n#else\nint y;\n#endif\n";
      expect = "`#else' with no matching `#if'";
    }
    {
      what = "#elif with nothing open";
      src = "int x;\n#elif 1\nint y;\n#endif\n";
      control = "#if 0\nint x;\n#elif 1\nint y;\n#endif\n";
      expect = "`#elif' with no matching `#if'";
    }
    {
      what = "a #if that is never closed";
      src = "#if 1\nint x;\n";
      control = "#if 1\nint x;\n#endif\n";
      expect = "conditional(s) still open";
    }
    {
      what = "#elif after #else";
      src = "#if 0\n#else\n#elif 1\nint x;\n#endif\n";
      control = "#if 0\n#elif 1\nint x;\n#endif\n";
      expect = "`#elif' after `#else'";
    }
    {
      what = "a second #else for the same #if";
      src = "#if 0\n#else\n#else\nint x;\n#endif\n";
      control = "#if 0\n#else\nint x;\n#endif\n";
      expect = "a second `#else'";
    }
    {
      # The control is the SAME junk inside a group that is not being
      # compiled, which 6.8.1 says is examined only for nesting -- so this
      # pair tests the refusal and the skipped-group rule with one change.
      what = "#endif with something after it";
      src = "#if 1\nint x;\n#endif 1\n";
      control = "#if 0\nint x;\n#endif 1\nint y;\n";
      expect = "`#endif' takes no operands";
    }
    {
      what = "#else with something after it";
      src = "#if 1\nint x;\n#else 1\nint y;\n#endif\n";
      control = "#if 1\nint x;\n#else\nint y;\n#endif\n";
      expect = "`#else' takes no operands";
    }

    # --- #if expressions --------------------------------------------------
    {
      what = "#if with no expression at all";
      src = "#if\nint x;\n#endif\n";
      control = "#if 1\nint x;\n#endif\n";
      expect = "`#if' with no expression";
    }
    {
      what = "a division by zero that is actually reached";
      # The control is the SAME division behind a false `&&', which must not
      # be evaluated -- so this pair tests the refusal and the short circuit
      # with one change.
      src = "#if 1 && (1 / 0)\nint x;\n#endif\n";
      control = "#if 0 && (1 / 0)\nint x;\n#endif\nint y;\n";
      expect = "`/' by zero in a `#if'";
    }
    {
      what = "a remainder by zero";
      src = "#if 1 % 0\nint x;\n#endif\n";
      control = "#if 1 % 3\nint x;\n#endif\n";
      expect = "`%' by zero in a `#if'";
    }
    {
      what = "an unbalanced parenthesis";
      src = "#if (1 + 2\nint x;\n#endif\n";
      control = "#if (1 + 2)\nint x;\n#endif\n";
      expect = "unbalanced `(' in the `#if'";
    }
    {
      what = "tokens left over after the expression";
      src = "#if 1 2\nint x;\n#endif\n";
      control = "#if 1 + 2\nint x;\n#endif\n";
      expect = "is left over at the end of the `#if'";
    }
    {
      what = "a floating constant in a #if, which names the decision that deferred float";
      src = "#if 1.5 > 1\nint x;\n#endif\n";
      control = "#if 15 > 1\nint x;\n#endif\n";
      expect = "decision-006";
    }
    {
      what = "a string literal in a #if";
      src = "#if \"yes\"\nint x;\n#endif\n";
      control = "#if 'y'\nint x;\n#endif\n";
      expect = "is an integer constant expression";
    }
    {
      what = "defined with no name after it";
      src = "#if defined ==\nint x;\n#endif\n";
      control = "#if defined X == 0\nint x;\n#endif\n";
      expect = "`defined' must be followed by an identifier";
    }
    {
      # poc/06-constants CLAMPS a constant too big for its type and records
      # why. There is no warning channel here, so a clamped value would
      # silently decide which arm a `#if' takes: 4294967296 becomes
      # 4294967295 and the comparison below becomes TRUE.
      what = "a constant in a #if that had to be clamped to fit";
      src = "#if 4294967296 == 4294967295\nint x;\n#endif\n";
      control = "#if 4294967295 == 4294967295\nint x;\n#endif\n";
      expect = "in a `#if' expression: overflow in constant";
    }
    {
      what = "a #line number that had to be clamped to fit";
      src = "int a;\n#line 99999999999\nint b;\n";
      control = "int a;\n#line 999\nint b;\n";
      expect = "does not name a line: overflow in constant";
    }
    {
      what = "#define of `defined', which C89 forbids by name";
      src = "#define defined 1\nint x;\n";
      control = "#define defines 1\nint x;\n";
      expect = "cannot be a macro name";
    }
    {
      what = "a shift count outside the width this evaluator computes in";
      src = "#if (1 << 32) == 0\nint x;\n#endif\n";
      control = "#if (1 << 31) != 0\nint x;\n#endif\n";
      expect = "has no defined answer to give";
    }

    # --- malformed directives ---------------------------------------------
    {
      what = "#define with no name";
      src = "#define\nint x;\n";
      control = "#define N\nint x;\n";
      expect = "`#define' with no macro name";
    }
    {
      what = "#define of something that is not an identifier";
      src = "#define + 2\nint x;\n";
      control = "#define P 2\nint x;\n";
      expect = "is not a macro name";
    }
    {
      what = "a redefinition with a different replacement list";
      src = "#define N 1\n#define N 2\nint x = N;\n";
      control = "#define N 1\n#define N 1\nint x = N;\n";
      expect = "is redefined with a different replacement list";
    }
    {
      what = "#undef with more than one name";
      src = "#define A 1\n#undef A B\nint x;\n";
      control = "#define A 1\n#undef A\nint x;\n";
      expect = "`#undef' takes exactly one identifier";
    }
    {
      what = "#line with a line number of zero";
      src = "int x;\n#line 0\nint y;\n";
      control = "int x;\n#line 1\nint y;\n";
      expect = "asks for a line number below 1";
    }
  ];

  # deepSeq, because the preprocessor is lazy: tryEval of an unforced thunk
  # reports success for input whose refusal has not been reached yet.
  goes = src: (b.tryEval (b.deepSeq (cpp.tokensOf { inherit src; file = "t.c"; }) true)).success;

  results = map (c: c // { accepted = goes c.src; controlWent = goes c.control; }) cases;

  wronglyAccepted = b.filter (r: r.accepted) results;
  wronglyRejected = b.filter (r: !r.controlWent) results;
  blankExpect = b.filter (r: b.stringLength r.expect < 8) cases;
  duplicateExpect = b.filter
    (c: b.length (b.filter (d: d.expect == c.expect && d.what != c.what) cases) > 0)
    cases;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  inherit cases declaredCases;
  forceReject = i: b.deepSeq (cpp.tokensOf { inherit ((b.elemAt cases i)) src; file = "t.c"; }) 1;

  summary =
    if b.length cases != declaredCases then
      throw "HARNESS FAULT: must-fail holds ${toString (b.length cases)} cases, against the ${
        toString declaredCases} this file declares. Raise the declared number with the table."
    else if blankExpect != [ ] then
      throw "HARNESS FAULT: these cases have no usable `expect' fragment, so messages.sh would match anything: ${names blankExpect}"
    else if duplicateExpect != [ ] then
      throw "HARNESS FAULT: these cases share an `expect' fragment with another, so neither can tell itself apart: ${names duplicateExpect}"
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been refused but preprocessed fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these controls should have preprocessed but threw: ${names wronglyRejected}"
    else
      "must-fail: ${toString (b.length cases)} refusals, each with its own control and its own diagnostic\n";
}
