# Must-fail suite: the paths check.nix cannot reach, because check.nix can only
# look at inputs the matcher handles.
#
# Every reject is paired with a CONTROL that must still succeed, and the
# controls sit next to their rejects (a two-register pool against a three-register
# one, a bad nonterminal against the same table unmodified) so that a control
# passing is evidence the specific rule fired rather than evidence that the
# implementation did not throw at everything. An implementation that threw
# unconditionally could not pass this file.
#
# Counts are taken from the result lists, never from the source tables: a
# harness that filtered `[ ]` instead of `rejects` would report zero and trip
# the floor rather than pass while testing nothing.
#
# `expect` is a fragment that must appear in the thrown message. It cannot be
# checked here -- builtins.tryEval returns success and value, never the message
# -- so messages.sh re-evaluates each reject out here and greps. Without that
# step, a matcher whose every diagnostic read "error" would pass a file whose
# whole subject is refusing to emit wrong code.
let
  b = builtins;
  parse = import ./parse.nix;
  table = import ./rules.nix;

  minRejects = 33;
  minControls = 18;

  # --- rule-table surgery --------------------------------------------------
  edit = id: f: table // {
    rules = map (r: if r.id == id then f r else r) table.rules;
  };
  without = id: table // { rules = b.filter (r: r.id != id) table.rules; };
  withoutAll = ids: table // { rules = b.filter (r: !(b.elem r.id ids)) table.rules; };

  build = args: file:
    let e = import ./emit.nix args; in
    (e.compile (parse.parse (b.readFile file))).asm;

  expr = ./ir/expr.sym;
  field = ./ir/field.sym;
  chars = ./ir/chars.sym;
  voidcall = ./ir/voidcall.sym;

  rejects = [
    # --- the rule table is data, so it is also data that can be wrong -------
    {
      what = "a rule names a nonterminal nothing declares";
      expect = "names a nonterminal that is not declared";
      run = build { table = edit "reg_indiri" (r: r // { nt = "rgister"; }); } expr;
    }
    {
      what = "two rules share an id";
      expect = "is used twice";
      run = build { table = edit "reg_indirp" (r: r // { id = "reg_indiri"; }); } expr;
    }
    {
      what = "a rule has no id at all";
      expect = "is missing its `id'";
      run = build { table = edit "reg_indiri" (r: b.removeAttrs r [ "id" ]); } expr;
    }
    {
      what = "a rule has no cost";
      expect = "is missing its `cost'";
      run = build { table = edit "reg_indiri" (r: b.removeAttrs r [ "cost" ]); } expr;
    }
    {
      what = "a rule has no template";
      expect = "is missing its `tmpl'";
      run = build { table = edit "reg_indiri" (r: b.removeAttrs r [ "tmpl" ]); } expr;
    }
    {
      what = "a negative rule cost, which the chain closure cannot converge on";
      expect = "has a negative cost";
      run = build { table = edit "addr_from_reg" (r: r // { cost = -1; }); } expr;
    }
    {
      what = "a table with no call markers, which would disable the argument guard";
      expect = "the rule table's `callMarkers' is empty";
      run = build { table = table // { callMarkers = [ ]; }; } expr;
    }
    {
      what = "a table missing a field the matcher reads";
      expect = "the rule table has no `regNt'";
      run = build { table = b.removeAttrs table [ "regNt" ]; } expr;
    }
    {
      what = "a start nonterminal the table does not declare";
      expect = "start or register nonterminal `statement' is not declared";
      run = build { table = table // { start = "statement"; }; } expr;
    }
    {
      what = "a target missing part of the interface burg calls back into";
      expect = "the target does not provide `operand'";
      run =
        let
          e = import ./emit.nix { };
          fn = parse.parse (b.readFile expr);
          frame = e.frameOf fn;
          burg = import ./burg.nix {
            inherit table;
            target = b.removeAttrs (e.targetFor fn frame) [ "operand" ];
          };
        in
        burg.select fn;
    }
    {
      what = "a chain rule with two nonterminals on the right";
      expect = "must have exactly one nonterminal on the right";
      run = build { table = edit "addr_from_reg" (r: r // { kids = [ "reg" "reg" ]; }); } expr;
    }
    {
      what = "a declared nonterminal no rule can produce";
      expect = "is declared but no rule produces it";
      run = build { table = table // { nonterminals = table.nonterminals ++ [ "fpreg" ]; }; } expr;
    }
    {
      what = "an opcode the table has no rule for";
      expect = "no rule produces `stmt' from ASGNI4(ADDRFP4,INDIRI4)";
      run = build { table = without "reg_indiri"; } expr;
    }
    {
      what = "a template escape that means nothing";
      expect = "unknown escape %q";
      run = build { table = edit "reg_indiri" (r: r // { tmpl = "lw %c,%q\n"; }); } expr;
    }
    {
      what = "a template reaching for a second kid a one-kid rule has not got";
      expect = "uses %1 but the rule has 1 kid(s)";
      run = build { table = edit "reg_indiri" (r: r // { tmpl = "lw %c,%1\n"; }); } expr;
    }
    {
      what = "a statement template asking for a destination register";
      expect = "uses %c outside an instruction";
      run = build { table = edit "stmt_asgni" (r: r // { tmpl = "sw %c,%0\n"; }); } expr;
    }
    {
      # The table exactly as it was before task-025. The chain rule
      # `stmt: reg' takes the listed call, hands a null destination down to a
      # template saying `mv %c,a0', and the refusal has to name the C rather
      # than the template -- which is what this pins.
      #
      # BOTH rows have to go. Remove only the direct one and the indirect row
      # takes the node instead, materialising the callee's address and
      # jalr-ing through it: correct code, dearer, and not this case.
      what = "a discarded call result with no statement rule to take it";
      expect = "CALLI4 is a call whose result is discarded here";
      run = build { table = withoutAll [ "stmt_calli_direct" "stmt_calli_indirect" ]; } voidcall;
    }
    {
      what = "a template asking for an argument register outside an argument";
      expect = "uses %A outside an argument";
      run = build { table = edit "reg_indiri" (r: r // { tmpl = "lw %A,%0\n"; }); } expr;
    }
    {
      what = "a predicate the matcher does not implement";
      expect = "unknown rule predicate";
      run = build { table = edit "con_cnst" (r: r // { when = { inrange = [ 0 1 ]; }; }); } expr;
    }
    {
      # Two predicates in one `when' used to apply the first and drop the
      # rest, silently, because the labeller asked for them in an if/else-if
      # chain. It is a table fault now, checked once on the table.
      what = "two predicates in one `when', which are not combined";
      expect = "exactly one predicate is allowed";
      run = build { table = edit "con_cnst" (r: r // { when = { range = [ 0 1 ]; srcSize = 4; }; }); } expr;
    }
    {
      # The hazard rules.nix pays a `mv' to avoid, written as a rule so that
      # the comment explaining it is a throw instead.
      what = "a fragment rule producing a register from a kid's own register";
      expect = "the evaluation registers are reused between statements";
      run = build { table = edit "reg_cviu4_4" (r: r // { cost = 0; tmpl = "%0"; }); } chars;
    }
    {
      # The rule for the OTHER source width still exists and still matches
      # the same opcode, so this is a refusal that only a table keyed on the
      # node's own symbol can produce (task-024).
      what = "a conversion whose source width no rule covers";
      expect = "the node with no rule at all is CVII4(INDIRI1)";
      run = build { table = without "reg_cvii4_1"; } chars;
    }

    # --- registers -----------------------------------------------------------
    {
      what = "an expression nested deeper than the evaluation registers allow";
      expect = "evaluation registers";
      run = build { depthRegs = [ "s1" "s2" ]; } field;
    }
    {
      what = "more live common subexpressions than there are registers to hold them";
      expect = "common subexpressions";
      run = build { cseRegs = [ ]; } expr;
    }
    {
      what = "the two register pools overlapping";
      expect = "in both the evaluation and the common-subexpression register pool";
      run = build { depthRegs = [ "s1" "s2" ]; cseRegs = [ "s2" ]; } expr;
    }

    # --- the parser ----------------------------------------------------------
    {
      what = "a line shape the listing format does not have";
      expect = "unrecognised line `wibble 3'";
      run = parse.parse (b.readFile expr + "\nwibble 3");
    }
    {
      what = "a node referring to a number its forest does not define";
      expect = "which its forest does not define";
      run = parse.parse (b.replaceStrings [ "3. INDIRI4 #4" ] [ "3. INDIRI4 #94" ] (b.readFile expr));
    }
    {
      what = "a reference count that disagrees with the references present";
      expect = "but the forest references it";
      run = parse.parse (b.replaceStrings [ "count=10 x" ] [ "count=11 x" ] (b.readFile expr));
    }
    {
      what = "a node listed before the kid it references";
      expect = "references a node that comes AFTER it in the list";
      run = parse.parse (b.replaceStrings
        [ "5. ADDRFP4 a\n4. INDIRI4 #5" ] [ "4. INDIRI4 #5\n5. ADDRFP4 a" ] (b.readFile expr));
    }
    {
      what = "a forest that numbers two nodes the same";
      expect = "repeats a node number";
      run = parse.parse (b.replaceStrings [ "4. ADDRFP4 b" ] [ "2. ADDRFP4 b" ] (b.readFile expr));
    }
    {
      what = "a listing holding more than one function";
      expect = "expected exactly one function in this listing, found 2";
      run = parse.parse (b.readFile expr + b.readFile field);
    }

    # --- the frame -----------------------------------------------------------
    {
      what = "an ADDRLP4 naming something that is neither a local nor a parameter";
      expect = "which is neither a parameter nor a local";
      run = build { } (b.toFile "renamed.sym"
        (b.replaceStrings [ "local x type=int" ] [ "local xx type=int" ] (b.readFile expr)));
    }
    {
      what = "a parameter this PoC does not know how to lay out";
      expect = "lays out 4-byte scalars only";
      run = build { } (b.toFile "wide.sym"
        (b.replaceStrings [ "callee b type=int" ] [ "callee b type=double" ] (b.readFile expr)));
    }

    # --- reduction -----------------------------------------------------------
    {
      what = "an argument that calls something after an earlier one is placed";
      expect = "emits a call, and 1 argument register(s) are already placed";
      run = build { } ./ir/argmul.sym;
    }
  ];

  # Controls. Each is the reject next to it with the fault taken back out, so
  # a blanket-throwing implementation cannot pass this file either.
  controls = [
    { what = "the real table compiles the arithmetic case"; run = build { } expr; }
    { what = "the real table compiles the addressing case"; run = build { } field; }
    { what = "the real table compiles the discarded-call case"; run = build { } voidcall; }
    {
      what = "the real table compiles the case with both source widths in it";
      run = build { } chars;
    }
    {
      what = "renaming a rule's id, but consistently, is fine";
      run = build { table = edit "reg_indiri" (r: r // { id = "load_word"; }); } expr;
    }
    {
      what = "one predicate in a `when' is fine, only two are not";
      run = build { table = edit "con_cnst" (r: r // { when = { range = [ (-2048) 2047 ]; }; }); } expr;
    }
    {
      what = "a fragment producing a register from a fixed register name is fine";
      run = build { table = edit "reg_zero" (r: r // { tmpl = "zero"; }); } expr;
    }
    {
      what = "a zero rule cost is fine, only a negative one is not";
      run = build { table = edit "addr_from_reg" (r: r // { cost = 0; }); } expr;
    }
    {
      what = "the target with its whole interface present";
      run =
        let
          e = import ./emit.nix { };
          fn = parse.parse (b.readFile expr);
          burg = import ./burg.nix {
            inherit table;
            target = e.targetFor fn (e.frameOf fn);
          };
        in
        burg.select fn;
    }
    {
      what = "raising a rule's cost changes the choice, not the legality";
      run = build { table = edit "reg_lshi_imm" (r: r // { cost = r.cost + 5; }); } expr;
    }
    {
      what = "a chain rule with exactly one nonterminal is fine";
      run = build { table = edit "addr_from_reg" (r: r // { kids = [ "reg" ]; }); } expr;
    }
    {
      what = "three evaluation registers are enough for the addressing case";
      run = build { depthRegs = [ "s1" "s2" "s3" ]; } field;
    }
    {
      what = "three common-subexpression registers are enough for the arithmetic case";
      run = build { cseRegs = [ "s11" "s10" "s9" ]; } expr;
    }
    {
      what = "a 4-byte parameter type is laid out";
      run = build { } (b.toFile "ptr.sym"
        (b.replaceStrings [ "callee b type=int" ] [ "callee b type=unsigned" ] (b.readFile expr)));
    }
    { what = "a listing with exactly one function parses"; run = parse.parse (b.readFile field); }
    {
      # The same expression in the OTHER argument: the libcall runs before
      # anything is in a0, so there is nothing to clobber. Sitting next to its
      # reject is what makes the reject evidence of a rule rather than of a
      # blanket refusal.
      what = "a call in the first argument, where nothing has been placed yet";
      run = build { } ./ir/argcall.sym;
    }
    {
      what = "the same listing with its references left alone";
      run = parse.parse (b.readFile expr);
    }
    {
      what = "a reference count that agrees with the references present";
      run = parse.parse (b.replaceStrings [ "count=10 x" ] [ "count=10  x" ] (b.readFile expr));
    }
    {
      what = "kids listed before the nodes that reference them, as lcc writes them";
      run = parse.parse (b.replaceStrings
        [ "5. ADDRFP4 a\n4. INDIRI4 #5" ] [ "5. ADDRFP4 a\n4. INDIRI4  #5" ] (b.readFile expr));
    }
  ];

  # deepSeq, because everything here is lazy: `tryEval (compile ...)` alone
  # reports success for an input whose error is still an unforced thunk.
  survives = c: (b.tryEval (b.deepSeq c.run true)).success;

  rejectResults = map (c: { inherit (c) what; accepted = survives c; }) rejects;
  controlResults = map (c: { inherit (c) what; ok = survives c; }) controls;

  wronglyAccepted = b.filter (r: r.accepted) rejectResults;
  wronglyRejected = b.filter (r: !r.ok) controlResults;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  # messages.sh reads this to check the thrown text, which Nix cannot see.
  inherit rejects;

  summary =
    if b.length rejectResults < minRejects || b.length controlResults < minControls then
      throw "HARNESS FAULT: must-fail tables shrank to ${toString (b.length rejectResults)} rejects and ${
        toString (b.length controlResults)} controls"
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been refused but compiled fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these should have compiled but threw: ${names wronglyRejected}"
    else
      "must-fail: ${toString (b.length rejectResults)} reject cases, ${
        toString (b.length controlResults)} control cases\n";
}
