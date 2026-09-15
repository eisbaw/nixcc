# Must-fail suite: the C this slice REFUSES, and the near-identical C it must
# still compile.
#
# The oracle differential can only compare programs both frontends accept, so
# everything outside slice 1 needs its own check. Without one, a parser that
# quietly guessed at `float', invented a layout for a struct, or compiled a
# string literal to something plausible would pass every other stage in this
# PoC -- the diff would simply never be run on it.
#
# THE PAIRING IS CODE, NOT A COMMENT. Every entry carries BOTH the source that
# must be refused and the control that must still compile, and the control
# differs from the reject in exactly one thing. Review found the previous
# shape -- two independent lists and a paragraph saying they were paired --
# had drifted to 17 rejects against 14 controls, with one reject unpaired and
# three sharing a control. A parser that threw on everything would have been
# caught by the count and not by the pairing, which is the wrong reason.
#
# AND `expect' IS DISTINCT PER ENTRY. Four entries used to share the generic
# fragment "outside slice 1", two of them reaching the SAME throw site, so
# neither could tell itself from the other. A fragment that names the decision
# or the task behind a refusal is the robust kind; a fragment that is an
# ordinary English word is not, because messages.sh greps nix's whole output.
#
# WHY EVERY REFUSAL IS A `throw' AND NEVER AN ATTRIBUTE MISS: builtins.tryEval
# does NOT catch an attribute-missing error (task-037). It propagates through
# and takes the whole file down, so a refusal spelled `table.${k}' would escape
# every check here -- and the suite would die rather than report. Every lookup
# in the frontend that could miss carries an explicit `or (throw ...)'; the
# inventory is in ops.nix's `check', simp.nix's `simplify', parse.nix's
# `ctorOf', `basicOf', `sclassName', `binops' and the ICON type table,
# listing.nix's `segName' and trees.nix's `opText'.
#
# `expect' cannot be checked here: tryEval returns success and value, never the
# message. messages.sh re-evaluates each reject and greps for it.
let
  b = builtins;
  cc = import ./compile.nix;

  # Declared and checked for EQUALITY. poc/lib/mutant.sh's argument about
  # mutation counts applies to tables too: a floor can be spent downward in
  # silence, and equality forces the edit that was wanted anyway.
  declaredCases = 25;

  cases = [
    # --- float, which decision-006 says must be REFUSED, not miscompiled ---
    {
      what = "a floating constant";
      src = "int f(void){ int x; x = 1.5; return x; }";
      control = "int f(void){ int x; x = 15; return x; }";
      expect = "floating-point constant `1.5'";
    }
    {
      what = "a floating constant names the decision that deferred it";
      src = "int f(void){ int x; x = 1.5; return x; }";
      control = "int f(void){ int x; x = 15; return x; }";
      expect = "decision-006, task-015";
    }
    {
      what = "a floating constant is refused WITH ITS SOURCE LINE";
      src = "int f(void)\n{\n    int x;\n    x = 2.5e3;\n    return x;\n}\n";
      control = "int f(void)\n{\n    int x;\n    x = 2500;\n    return x;\n}\n";
      expect = "line 4: parse: floating-point constant `2.5e3'";
    }
    {
      what = "a `float' return type";
      src = "float f(void){ return 0; }";
      control = "int f(void){ return 0; }";
      expect = "`float' declarations are deferred";
    }
    {
      what = "a `double' local, which compiles IDENTICALLY to lcc if it is not refused";
      src = "int f(void){ double x; double y; x = y; return 1; }";
      control = "int f(void){ long x; long y; x = y; return 1; }";
      expect = "`double' declarations are deferred";
    }
    {
      # Spread over lines so its `expect' can pin the POSITION as well as the
      # message, which is what keeps it distinct from the return-type case
      # above: the refusal text names only the type keyword, so two float
      # declarations on line 1 would say exactly the same thing.
      what = "a `float' parameter";
      src = "extern int g(\n  float x\n);\nint f(void){ return 0; }\n";
      control = "extern int g(\n  int x\n);\nint f(void){ return 0; }\n";
      expect = "line 2: parse: `float' declarations are deferred";
    }
    {
      what = "a `long double' local";
      src = "int f(void){ long double d; return 0; }";
      control = "int f(void){ long d; d = 0; return 0; }";
      expect = "`long double' declarations are deferred";
    }

    # --- type specifiers lcc rejects -------------------------------------
    {
      what = "`short float', which lcc rejects and which we used to make a `short'";
      src = "int f(void){ short float x; return 0; }";
      control = "int f(void){ short x; x = 0; return 0; }";
      expect = "invalid type specification";
    }
    {
      # `short float' is ALSO a float declaration, so it is refused twice over
      # and cannot tell the two guards apart. This one is caught by the
      # combination check alone, which is what makes a mutation of that check
      # visible. Spread over lines so its fragment can pin the position and
      # stay distinct from the `short float' case's.
      what = "`long char', which only the combination check catches";
      src = "int f(void)\n{\n    long char c;\n    return 0;\n}\n";
      control = "int f(void)\n{\n    long c;\n    c = 0;\n    return 0;\n}\n";
      expect = "line 3: parse: invalid type specification";
    }
    {
      what = "`long long'";
      src = "int f(void){ long long n; return 0; }";
      control = "int f(void){ long n; n = 0; return 0; }";
      expect = "`long long' is outside slice 1";
    }

    # --- later slices ------------------------------------------------------
    {
      what = "a string literal";
      src = "extern int p(int); int f(void){ return p(\"hi\"); }";
      control = "extern int p(int); int f(void){ return p(1); }";
      expect = "string literals belong to slice 2 (task-028)";
    }
    {
      what = "a struct declaration";
      src = "struct s { int a; }; int f(void){ return 0; }";
      control = "int f(void){ int a; a = 1; return a; }";
      expect = "struct, union and enum types are outside slice 1";
    }
    {
      # Same throw site as the struct case, reached from a LOCAL declaration
      # rather than a file-scope one, so its fragment pins the line to stay
      # distinguishable from it.
      what = "an enum declaration, which reaches the same site by another route";
      src = "int f(void)\n{\n    enum e { A } x;\n    return 0;\n}\n";
      control = "int f(void)\n{\n    int A;\n    A = 0;\n    return A;\n}\n";
      expect = "line 3: parse: struct, union and enum types";
    }
    {
      what = "subscripting";
      src = "int f(int *v){ return v[0]; }";
      control = "int f(int v){ return v; }";
      expect = "subscripting belongs to slice 2/3";
    }
    {
      what = "pointer arithmetic";
      src = "int f(int *v){ int *p; p = v + 1; return 0; }";
      control = "int f(int v){ int p; p = v + 1; return 0; }";
      expect = "pointer arithmetic belongs to slice 2/3";
    }
    {
      what = "a struct member";
      src = "int f(int a){ return a.x; }";
      control = "int f(int a){ return a; }";
      expect = "struct members are outside slice 1";
    }
    {
      what = "a tentative global";
      src = "int g; int f(void){ return 0; }";
      control = "int g(void){ return 0; } int f(void){ return g(); }";
      expect = "tentative global `g' needs slice 3 (task-029)";
    }
    {
      what = "a global with an initialiser";
      src = "int g = 1; int f(void){ return 0; }";
      control = "int f(void){ int g = 1; return g; }";
      expect = "global initialisers belong to slice 3 (task-029)";
    }
    {
      what = "a local static";
      src = "int f(void){ static int n; return n; }";
      control = "int f(void){ int n; n = 0; return n; }";
      expect = "local statics belong to slice 3 (task-029)";
    }
    {
      what = "a switch statement";
      src = "int f(int a){ switch (a) { } return 0; }";
      control = "int f(int a){ if (a) return 1; return 0; }";
      expect = "`SWITCH' statements are outside slice 1";
    }
    {
      what = "a goto";
      src = "int f(int a){ goto out; out: return a; }";
      control = "int f(int a){ int out; out = a; return out; }";
      expect = "`GOTO' statements are outside slice 1";
    }
    {
      what = "a variadic prototype";
      src = "extern int p(int, ...); int f(void){ return p(1, 2); }";
      control = "extern int p(int, int); int f(void){ return p(1, 2); }";
      expect = "variadic functions are outside slice 1";
    }

    # --- C that lcc itself rejects ----------------------------------------
    {
      what = "a function defined twice";
      src = "int f(void){return 1;} int f(void){return 2;}";
      control = "int f(void){return 1;} int g(void){return 2;}";
      expect = "redefinition of `f'";
    }
    {
      what = "more arguments than the prototype takes";
      src = "int g(int); int f(void){ return g(1,2,3); }";
      control = "int g(int); int f(void){ return g(1); }";
      expect = "too many arguments";
    }
    {
      what = "an array size that is not positive once cast to int";
      src = "int f(void){ int a[4000000000u]; return 0; }";
      control = "int f(void){ int a[4]; return 0; }";
      expect = "is an illegal array size";
    }
  ];

  # deepSeq, because the frontend is lazy: tryEval of an unforced thunk
  # reports success for a program whose refusal has not been reached yet.
  compiles = src: (b.tryEval (b.deepSeq (cc.listingOf src) true)).success;

  results = map
    (c: c // { accepted = compiles c.src; controlCompiled = compiles c.control; })
    cases;

  wronglyAccepted = b.filter (r: r.accepted) results;
  wronglyRejected = b.filter (r: !r.controlCompiled) results;
  blankExpect = b.filter (r: r.expect == "" || b.stringLength r.expect < 8) cases;
  # A fragment shared by two entries cannot tell them apart, which is the same
  # argument run.sh's distinctness loop makes about mutations.
  duplicateExpect = b.filter
    (c: b.length (b.filter (d: d.expect == c.expect && d.what != c.what) cases) > 0)
    cases;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  inherit cases declaredCases;
  forceReject = i: b.deepSeq (cc.listingOf (b.elemAt cases i).src) 1;

  summary =
    if b.length cases != declaredCases then
      throw "HARNESS FAULT: must-fail holds ${toString (b.length cases)} cases, against the ${
        toString declaredCases} this file declares. Raise the declared number with the table."
    else if blankExpect != [ ] then
      throw "HARNESS FAULT: these cases have no usable `expect' fragment, so messages.sh would match anything: ${names blankExpect}"
    else if duplicateExpect != [ ] then
      throw "HARNESS FAULT: these cases share an `expect' fragment with another, so neither can tell itself apart: ${names duplicateExpect}"
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been refused but compiled fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these controls should have compiled but threw: ${names wronglyRejected}"
    else
      "must-fail: ${toString (b.length cases)} refusals, each with its own control and its own diagnostic\n";
}
