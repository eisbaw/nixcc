# Must-fail suite: the C this slice REFUSES, and the near-identical C it must
# still compile.
#
# The oracle differential can only compare programs both frontends accept, so
# everything outside slice 1 needs its own check. Without one, a parser that
# quietly guessed at `float', invented a layout for a struct, or compiled a
# string literal to something plausible would pass every other stage in this
# PoC -- the diff would simply never be run on it.
#
# EVERY REJECT IS PAIRED WITH A CONTROL, and the controls are chosen to differ
# from their rejects in one thing. `int x; x = 1.5;' against `int x; x = 15;'
# says the FLOATING CONSTANT was refused; a parser that threw on everything
# would fail the control and could not pass this file.
#
# WHY EVERY REFUSAL IS A `throw' AND NEVER AN ATTRIBUTE MISS: builtins.tryEval
# does NOT catch an attribute-missing error (task-037). It propagates through
# and takes the whole file down, so a refusal spelled `table.${k}' would escape
# every check here -- and the suite would die rather than report. Two places in
# this frontend would otherwise be attribute misses, `ops.check' and simp.nix's
# case table, and both carry an explicit `or (throw ...)'.
#
# And `expect' cannot be checked here: tryEval returns success and value, never
# the message. messages.sh re-evaluates each reject and greps for it.
let
  b = builtins;
  cc = import ./compile.nix;

  # Declared counts, checked for EQUALITY. poc/lib/mutant.sh's argument about
  # mutation counts applies to tables too: a floor can be spent downward in
  # silence, and equality forces the edit that was wanted anyway.
  declaredRejects = 17;
  declaredControls = 14;

  rejects = [
    # Float is a deferred CHOICE, so the message has to name the decision and
    # the task. A bare "unsupported" leaves the next reader unable to tell a
    # gap from a plan -- decision-006 says so in as many words.
    {
      what = "a floating constant";
      src = "int f(void){ int x; x = 1.5; return x; }";
      expect = "decision-006";
    }
    {
      what = "a floating constant names the rejection task too";
      src = "int f(void){ int x; x = 1.5; return x; }";
      expect = "task-015";
    }
    {
      what = "a floating constant is refused WITH ITS SOURCE LINE";
      src = "int f(void)\n{\n    int x;\n    x = 2.5e3;\n    return x;\n}\n";
      expect = "on line 4";
    }
    {
      what = "a `float' declaration";
      src = "float f(void){ return 0; }";
      expect = "float";
    }
    {
      what = "a string literal";
      src = "extern int p(int); int f(void){ return p(\"hi\"); }";
      expect = "task-028";
    }
    {
      what = "a struct declaration";
      src = "struct s { int a; }; int f(void){ return 0; }";
      expect = "outside slice 1";
    }
    {
      what = "an enum declaration";
      src = "enum e { A }; int f(void){ return 0; }";
      expect = "outside slice 1";
    }
    {
      what = "subscripting";
      src = "int f(int *v){ return v[0]; }";
      expect = "slice 2/3";
    }
    {
      what = "pointer arithmetic";
      src = "int f(int *v){ int *p; p = v + 1; return 0; }";
      expect = "slice 2/3";
    }
    {
      what = "a tentative global";
      src = "int g; int f(void){ return 0; }";
      expect = "task-029";
    }
    {
      what = "a global with an initialiser";
      src = "int g = 1; int f(void){ return 0; }";
      expect = "task-029";
    }
    {
      what = "a local static";
      src = "int f(void){ static int n; return n; }";
      expect = "task-029";
    }
    {
      what = "a switch statement";
      src = "int f(int a){ switch (a) { } return 0; }";
      expect = "outside slice 1";
    }
    {
      what = "a goto";
      src = "int f(int a){ goto out; out: return a; }";
      expect = "outside slice 1";
    }
    {
      what = "an undeclared identifier";
      src = "int f(void){ return nosuch; }";
      expect = "undeclared identifier";
    }
    {
      what = "a variadic prototype";
      src = "extern int p(int, ...); int f(void){ return p(1, 2); }";
      expect = "variadic";
    }
    {
      what = "a missing semicolon";
      src = "int f(void){ int x x = 1; return x; }";
      expect = "syntax error";
    }
  ];

  # Each control is its reject with the one offending thing removed.
  controls = [
    { what = "an integer constant, against the floating one"; src = "int f(void){ int x; x = 15; return x; }"; }
    { what = "an int return type, against `float'"; src = "int f(void){ return 0; }"; }
    { what = "an int argument, against the string literal"; src = "extern int p(int); int f(void){ return p(1); }"; }
    { what = "an ordinary declaration, against the struct one"; src = "int f(void){ int a; a = 1; return a; }"; }
    { what = "a plain int local, against the enum declaration"; src = "int f(void){ int A; A = 0; return A; }"; }
    { what = "a parameter read directly, against subscripting"; src = "int f(int v){ return v; }"; }
    { what = "integer arithmetic, against the pointer kind"; src = "int f(int v){ int p; p = v + 1; return p; }"; }
    { what = "a function, against the tentative global"; src = "int g(void){ return 0; } int f(void){ return g(); }"; }
    { what = "a local initialiser, against the global one"; src = "int f(void){ int g = 1; return g; }"; }
    { what = "an automatic local, against the static one"; src = "int f(void){ int n; n = 0; return n; }"; }
    { what = "an if, against the switch"; src = "int f(int a){ if (a) return 1; return 0; }"; }
    { what = "a labelled-looking name used as a variable, against the goto"; src = "int f(int a){ int out; out = a; return out; }"; }
    { what = "a declared identifier, against the undeclared one"; src = "int f(void){ int nosuch; nosuch = 1; return nosuch; }"; }
    { what = "a fixed prototype, against the variadic one"; src = "extern int p(int, int); int f(void){ return p(1, 2); }"; }
  ];

  # deepSeq, because the frontend is lazy: tryEval of an unforced thunk
  # reports success for a program whose refusal has not been reached yet.
  compiles = r: (b.tryEval (b.deepSeq (cc.listingOf r.src) true)).success;

  rejectResults = map (r: { inherit (r) what; accepted = compiles r; }) rejects;
  controlResults = map (r: { inherit (r) what; compiled = compiles r; }) controls;

  wronglyAccepted = b.filter (r: r.accepted) rejectResults;
  wronglyRejected = b.filter (r: !r.compiled) controlResults;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  inherit rejects declaredRejects;
  forceReject = i: b.deepSeq (cc.listingOf (b.elemAt rejects i).src) 1;

  summary =
    if b.length rejectResults != declaredRejects || b.length controlResults != declaredControls then
      throw "HARNESS FAULT: must-fail tables hold ${toString (b.length rejectResults)} rejects and ${
        toString (b.length controlResults)} controls, against the ${toString declaredRejects} and ${
        toString declaredControls} this file declares. Raise the declared numbers with the tables."
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been refused but compiled fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these should have compiled but threw: ${names wronglyRejected}"
    else
      "must-fail: ${toString (b.length rejectResults)} reject cases, ${
        toString (b.length controlResults)} control cases\n";
}
