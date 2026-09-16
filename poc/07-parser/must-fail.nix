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
  declaredCases = 37;

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
      # task-047: lcc's own lexer does not JOIN a narrow literal to a wide one
      # -- it stops at the width change and reports a syntax error -- so both
      # frontends refuse this and they refuse it in different words. That is a
      # deviation and it is recorded as one: there is no case behind a rule for
      # the joined type, so the house answer is to refuse rather than invent.
      what = "adjacent string literals of different widths";
      src = "int f(void){ char *s; s = \"a\" L\"b\"; return s[0]; }";
      control = "int f(void){ char *s; s = \"a\" \"b\"; return s[0]; }";
      expect = "different widths are joined here";
    }
    # --- TYPE IDENTITY, which is what criterion #1 of task-058 is ---------
    # These three are the whole argument for the `sym' field on an aggregate
    # type. The IR diff CANNOT see any of them: lcc prints the tag name, so
    # the listings would agree, and all three programs are rejected by lcc --
    # which means the differential never runs on them at all. A frontend that
    # compared aggregates structurally would accept all three, and nothing
    # else in this suite would notice.
    {
      what = "two DIFFERENT anonymous structs with identical members, assigned to each other";
      src = "int f(void){ struct { int a; } x; struct { int a; } y; x = y; return x.a; }";
      control = "int f(void){ struct { int a; } x; struct { int a; } y; x.a = y.a; return x.a; }";
      # lcc's own diagnostic, verbatim: the two SPELLINGS are identical and
      # only the tag symbol tells the types apart.
      expect = "`struct defined at 1' and `struct defined at 1'";
    }
    {
      # THE ONE THAT WOULD MISCOMPILE RATHER THAN MISDIAGNOSE, and so the one
      # worth having. The two assignments above are caught twice over -- the
      # second time by `cast', which has no STRUCT arm and would refuse them
      # whatever assign() said. A POINTER assignment has no such second line:
      # `cast' from one four-byte pointer to another is a retype and nothing
      # else, so a frontend that thought these two types were the same would
      # COMPILE this, and every `x->a' after it would read struct B's layout
      # through a struct A pointer.
      # The two structs are ANONYMOUS and declared on the same line, so their
      # spellings are identical, their sizes are identical, and the ONLY thing
      # that separates them is the tag symbol. A tagged pair would be
      # separated by `name' as well, which is the older mechanism and would
      # mask what this is testing.
      what = "a pointer to one anonymous struct assigned to a pointer to another";
      src = "int f(void){ struct { int a; } x; struct { int b; } *p; p = &x; return p->b; }";
      control = "struct P { int a; }; int f(void){ struct P x; struct P *p; p = &x; return p->a; }";
      expect = "`pointer to struct defined at 1' and `pointer to struct defined at 1'";
    }
    {
      what = "a tag redeclared in an inner scope, which is a DIFFERENT type of the same name";
      src = "struct P { int a; }; int f(struct P *o){ struct P { int a; }; struct P in; in = *o; return in.a; }";
      control = "struct P { int a; }; int f(struct P *o){ struct P in; in = *o; return in.a; }";
      expect = "illegal types `struct P' and `struct P'";
    }

    # --- the compound-type surface slice 4a does NOT cover ----------------
    {
      what = "a bit field";
      src = "struct P { unsigned a : 3; }; int f(void){ return 0; }";
      control = "struct P { unsigned a; }; int f(void){ return 0; }";
      expect = "bit fields belong to slice 4b (task-059)";
    }
    {
      what = "a forward-declared tag used before its members are known";
      src = "struct P; int f(struct P *p){ return 0; }";
      control = "struct P { int a; }; int f(struct P *p){ return p->a; }";
      expect = "line 1: parse: `incomplete struct P' has no members yet";
    }
    {
      # The SAME throw site as the case above, reached from a field list
      # rather than from a parameter list, so its fragment pins the line. This
      # is the one that costs a linked list, and it is here so that the cost
      # is written down as a test rather than as a sentence.
      what = "a self-referential struct, which is what task-066 actually costs";
      src = "struct N {\n    int v;\n    struct N *next;\n};\nint f(struct N *p){ return p->v; }\n";
      control = "struct N {\n    int v;\n    int next;\n};\nint f(struct N *p){ return p->v; }\n";
      expect = "line 3: parse: `incomplete struct N' has no members yet";
    }
    {
      what = "a typedef of an aggregate with no tag, whose spelling lcc looks up at print time";
      src = "typedef struct { int a; } T; int f(T *t){ return t->a; }";
      control = "typedef struct P { int a; } T; int f(T *t){ return t->a; }";
      expect = "`typedef' of an aggregate with no tag";
    }
    {
      what = "DEFINING a function that returns a struct by value";
      src = "struct P { int a; }; struct P mk(void){ struct P p; p.a = 1; return p; }";
      control = "struct P { int a; }; int mk(void){ struct P p; p.a = 1; return p.a; }";
      expect = "needs the hidden return parameter (task-068)";
    }
    {
      # The other half of task-068, and a separate throw site: a function
      # declared elsewhere can be CALLED without ever being defined here.
      what = "CALLING a function that returns a struct by value";
      src = "struct P { int a; }; extern struct P mk(void); int f(void){ struct P p; p = mk(); return p.a; }";
      control = "struct P { int a; }; extern int mk(void); int f(void){ struct P p; p.a = mk(); return p.a; }";
      expect = "builds a CALLB (task-068)";
    }
    {
      what = "a braced initialiser for a local aggregate";
      src = "struct P { int a; }; int f(void){ struct P p = { 1 }; return p.a; }";
      control = "struct P { int a; }; int f(struct P *q){ struct P p = *q; return p.a; }";
      expect = "a braced initialiser belongs to slice 3 (task-029)";
    }

    # --- compound-type C that lcc itself rejects --------------------------
    {
      # The CONTROL is the interesting half. enode.c's asgn() clears the tag's
      # `cfields' bit around an assignment and puts it back, which is the only
      # thing that lets an INITIALISER of a struct with a const member
      # compile; the reject is the same struct assigned to a line later.
      what = "assigning to a struct that has a const member";
      src = "struct C { const int a; int b; }; int f(struct C *d){ struct C c; c = *d; return c.a; }";
      control = "struct C { const int a; int b; }; int f(struct C *d){ struct C c = *d; return c.a; }";
      expect = "assignment to const identifier `c'";
    }
    {
      what = "a member the struct does not have";
      src = "struct P { int a; }; int f(struct P *p){ return p->z; }";
      control = "struct P { int a; }; int f(struct P *p){ return p->a; }";
      expect = "unknown field `z' of `struct P'";
    }
    {
      what = "`struct' with neither a tag nor a body";
      src = "int f(void){ struct ; return 0; }";
      control = "int f(void){ struct S { int a; } s; s.a = 1; return s.a; }";
      expect = "missing struct tag";
    }
    {
      # decl.c accepts a specifier with no declarator only when it named
      # something that can be referred to later. An anonymous aggregate cannot
      # be, so the declaration is empty and lcc says so.
      what = "an anonymous struct declared and never named";
      src = "struct { int a; };\nint f(void){ return 0; }\n";
      control = "struct P { int a; };\nint f(void){ return 0; }\n";
      expect = "line 1: empty declaration";
    }
    {
      # Pointer arithmetic on a pointer to an INCOMPLETE type. lcc errors and
      # so do we, which is the point: the scaling in enode.c's addtree is by
      # the pointee's size, and a size of zero would make `p + 1' mean `p'
      # rather than mean nothing.
      what = "arithmetic on a `void *', whose element has no size";
      src = "int f(void){ void *p; p = 0; p = p + 1; return 0; }";
      control = "int f(void){ char *p; p = 0; p = p + 1; return 0; }";
      expect = "unknown size for type `void'";
    }
    {
      what = "subtracting two pointers that do not point at the same type";
      src = "int f(int *a, char *b){ return a - b; }";
      control = "int f(int *a, int *b){ return a - b; }";
      expect = "operands of - have illegal types";
    }
    {
      what = "a member selected from something that is not a struct";
      src = "int f(int a){ return a.x; }";
      control = "int f(int a){ return a; }";
      expect = "left operand of . has incompatible type";
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
