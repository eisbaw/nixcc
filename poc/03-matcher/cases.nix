# What the matcher is expected to do, written out rather than derived.
#
# Every node id and forest index below was read off real lcc output -- the
# .sym files under ir/, which run.sh regenerates from their .c and diffs, so a
# stale expectation cannot quietly stop referring to the node it names.
#
# The point of `selections` is that a labelling bug shows up as a named rule
# changing, not as assembly that happens to differ somewhere. The point of
# `duels` is stronger: each names two rules that both match the same subtree,
# and checks not only that the cheaper one won but that RAISING its cost flips
# the choice. Without that second half, "the cheaper one won" is equally
# consistent with a matcher that just takes the first rule in the table.
{
  # One function per file, so a case's expected assembly is all of it.
  functions = [
    { name = "expr"; fn = "f"; what = "arithmetic, the multiply/divide libcalls, a call and a conditional branch"; }
    { name = "loop"; fn = "sum"; what = "a while loop: labels, an unconditional jump, pointer arithmetic"; }
    { name = "field"; fn = "dist"; what = "a struct field, i.e. the reg+constant addressing mode"; }
    { name = "mod"; fn = "rem"; what = "the remainder libcall, whose sign rule is the easy one to get wrong"; }
    { name = "cond"; fn = "probe"; what = "a conditional expression, which puts a LABEL inside a forest"; }
    { name = "save"; fn = "hold"; what = "more registers held before a mid-forest label than after it"; }
    { name = "argcall"; fn = "nested"; what = "a libcall inside a call's FIRST argument, which is legal"; }
  ];

  # Acceptance criterion 4 and 9: these opcodes must appear in the corpus DAGs
  # AND be matched there by a rule for that opcode. Listing an opcode no test
  # file contains is a harness fault, not a pass.
  requiredOps = [
    "CNSTI4" "ADDRLP4" "ADDRGP4" "ADDRFP4" "INDIRI4" "INDIRP4" "ASGNI4" "ASGNP4"
    "ADDI4" "ADDP4" "SUBI4" "LSHI4" "MULI4" "DIVI4" "MODI4"
    "CALLI4" "RETI4" "ARGI4" "JUMPV"
    "LEI4" "LTI4" "GEI4" "EQI4"
  ];

  # RV32I has no M extension (decision-003). The oracle prints MUL/DIV inline
  # because it runs with mulops_calls=0 (decision-004), so the rule table is
  # where that difference has to be absorbed.
  libcalls = [
    { op = "MULI4"; rule = "reg_muli_libcall"; symbol = "__mulsi3"; }
    { op = "DIVI4"; rule = "reg_divi_libcall"; symbol = "__divsi3"; }
    { op = "MODI4"; rule = "reg_modi_libcall"; symbol = "__modsi3"; }
  ];


  # Mnemonics no rule may emit, because this target does not have them.
  forbiddenMnemonics = [ "mul " "mulh" "div " "divu" "rem " "remu" ];

  # --- labelling (acceptance criterion 2) --------------------------------
  selections = [
    {
      what = "a local's address is a frame displacement, free because the load folds it";
      file = "expr"; forest = 1; node = "2"; nt = "addr"; rule = "addr_addrlp"; cost = 0;
    }
    {
      what = "loading that local costs one lw and nothing else";
      file = "expr"; forest = 1; node = "10"; nt = "reg"; rule = "reg_indiri"; cost = 1;
    }
    {
      what = "a small constant is an immediate, at no cost of its own";
      file = "expr"; forest = 1; node = "11"; nt = "con"; rule = "con_cnst"; cost = 0;
    }
    {
      what = "x + y over two loaded values";
      file = "expr"; forest = 1; node = "3"; nt = "reg"; rule = "reg_addi_reg"; cost = 3;
    }
    {
      what = "x - 1: RV32I has no subtract-immediate, so the constant is materialised";
      file = "expr"; forest = 1; node = "9"; nt = "reg"; rule = "reg_subi"; cost = 3;
    }
    {
      what = "MULI4 is a call to __mulsi3, and is priced like one";
      file = "expr"; forest = 1; node = "13"; nt = "reg"; rule = "reg_muli_libcall"; cost = 12;
    }
    {
      what = "DIVI4 is a call to __divsi3";
      file = "expr"; forest = 1; node = "16"; nt = "reg"; rule = "reg_divi_libcall"; cost = 12;
    }
    {
      what = "a shift by a constant is slli";
      file = "expr"; forest = 1; node = "19"; nt = "reg"; rule = "reg_lshi_imm"; cost = 2;
    }
    {
      what = "the store through a global's address";
      file = "expr"; forest = 1; node = "22"; nt = "stmt"; rule = "stmt_asgni"; cost = 4;
    }
    {
      what = "lcc inverts `x > 10' into a branch-if-less-or-equal to the join label";
      file = "expr"; forest = 1; node = "25"; nt = "stmt"; rule = "stmt_lei4"; cost = 3;
    }
    {
      what = "an argument is deposited in its argument register";
      file = "expr"; forest = 2; node = "1"; nt = "stmt"; rule = "stmt_argi"; cost = 2;
    }
    {
      what = "a call to a known symbol";
      file = "expr"; forest = 2; node = "7"; nt = "reg"; rule = "reg_calli_direct"; cost = 4;
    }
    {
      what = "the return moves to a0 and jumps to the epilogue";
      file = "expr"; forest = 4; node = "1"; nt = "stmt"; rule = "stmt_reti"; cost = 2;
    }
    {
      what = "a zero constant is the x0 register, so it costs nothing";
      file = "loop"; forest = 2; node = "3"; nt = "reg"; rule = "reg_zero"; cost = 0;
    }
    {
      what = "the loop's back-edge jump";
      file = "loop"; forest = 3; node = "1"; nt = "stmt"; rule = "stmt_jumpv"; cost = 1;
    }
    {
      what = "scaling the index: v[i] shifts by two";
      file = "loop"; forest = 5; node = "7"; nt = "reg"; rule = "reg_lshi_imm"; cost = 2;
    }
    {
      what = "base + scaled index is a register add, not an addressing mode";
      file = "loop"; forest = 5; node = "6"; nt = "reg"; rule = "reg_addp_reg"; cost = 4;
    }
    {
      what = "i < n as a single branch";
      file = "loop"; forest = 7; node = "1"; nt = "stmt"; rule = "stmt_lti4"; cost = 3;
    }
    {
      what = "MODI4 is a call to __modsi3, priced like the other two libcalls";
      file = "mod"; forest = 0; node = "3"; nt = "reg"; rule = "reg_modi_libcall"; cost = 12;
    }
    {
      what = "`r < 0' inverts into branch-if-greater-or-equal, against the zero register";
      file = "mod"; forest = 0; node = "8"; nt = "stmt"; rule = "stmt_gei4"; cost = 2;
    }
    {
      what = "the conditional's test, also against the zero register";
      file = "cond"; forest = 1; node = "1"; nt = "stmt"; rule = "stmt_eqi4"; cost = 2;
    }
    {
      what = "the load lcc shares across the label inside that forest";
      file = "cond"; forest = 1; node = "2"; nt = "reg"; rule = "reg_indiri"; cost = 1;
    }
    {
      what = "pointer + constant field offset IS an addressing mode, and free";
      file = "field"; forest = 1; node = "5"; nt = "addr"; rule = "addr_addp"; cost = 1;
    }
    {
      what = "so p->y is one lw with the displacement folded in";
      file = "field"; forest = 1; node = "4"; nt = "reg"; rule = "reg_indiri"; cost = 2;
    }
  ];

  # --- cost-driven choice (acceptance criterion 5) ------------------------
  # `penalty` is added to the winner's cost in a perturbed copy of the table.
  # The loser must then win, and the emitted assembly must change accordingly.
  duels = [
    {
      what = "shift by a constant: slli, or materialise the constant and use sll";
      file = "expr"; forest = 1; node = "19"; nt = "reg";
      winner = "reg_lshi_imm"; loser = "reg_lshi_reg"; penalty = 5;
      winnerAsm = "slli s2,s2,2"; loserAsm = "sll s2,s2,s3";
    }
    {
      what = "a call to a known symbol, or materialise its address and jalr through it";
      file = "expr"; forest = 2; node = "7"; nt = "reg";
      winner = "reg_calli_direct"; loser = "reg_calli_indirect"; penalty = 5;
      winnerAsm = "call h"; loserAsm = "jalr s1";
    }
    {
      what = "a zero constant is the x0 register, not an `li'";
      file = "loop"; forest = 2; node = "3"; nt = "reg";
      winner = "reg_zero"; loser = "reg_from_con"; penalty = 2;
      winnerAsm = "sw zero,-64(s0)"; loserAsm = "li s11,0";
    }
    {
      what = "a struct field offset folds into the load, or becomes its own addi";
      file = "field"; forest = 1; node = "5"; nt = "addr";
      winner = "addr_addp"; loser = "addr_from_reg"; penalty = 3;
      winnerAsm = "lw s2,4(s11)"; loserAsm = "addi s2,s11,4";
    }
  ];

  # --- emitted assembly (acceptance criterion 3) --------------------------
  # Instructions the emitted body must contain, text it must not contain
  # anywhere, and how many instructions it is. `present` is matched as whole
  # lines; `absent` as substrings. `absent` is the half that catches a matcher
  # emitting everything and letting the assembler sort it out, and
  # `instructions` the half that catches one emitting the right things twice.
  # None of the three counts the prologue or epilogue, which are not the
  # matcher's work.
  emitted = [
    {
      file = "expr";
      present = [
        "lw s11,-56(s0)"           # b, the common subexpression, loaded once
        "call __mulsi3"
        "call __divsi3"
        "slli s2,s2,2"
        "add s2,s2,s11"
        "sub s2,s2,s3"
        "ble s10,s2,.Lf_2"
        "mv a0,s1"
        "mv a1,s1"
        "call h"
        "j .Lf_epilogue"
      ];
      absent = [ "mul " "div " "%" "jalr" ];
      instructions = 41;
      follows = [ ];
    }
    {
      file = "loop";
      present = [
        "sw zero,-64(s0)"
        "sw zero,-68(s0)"
        "j .Lsum_3"
        ".Lsum_2:"
        "blt s1,s2,.Lsum_2"
        "slli s3,s11,2"
      ];
      absent = [ "li s11,0" "%" ];
      instructions = 23;
      follows = [ ];
    }
    {
      file = "field";
      present = [ "lw s2,4(s11)" "lw s3,0(s11)" "sub s2,s2,s3" ];
      absent = [ "addi s2,s11,4" "%" ];
      instructions = 12;
      follows = [ ];
    }
    {
      file = "mod";
      present = [ "call __modsi3" "bge s1,zero,.Lrem_2" ".Lrem_2:" "sub s2,s2,s3" ];
      absent = [ "rem " "div " "%" ];
      instructions = 16;
      follows = [ ];
    }
    {
      file = "cond";
      present = [ "beq s11,zero,.Lprobe_3" "j .Lprobe_4" ".Lprobe_4:" ];
      absent = [ "%" ];
      instructions = 16;
      # The point of this case. `a' is a node lcc shares across the label, and
      # a register cannot be assumed live across a branch target, so the first
      # instruction after the join must RELOAD it. If the emitter carried its
      # common-subexpression table across the label it would reuse a register
      # filled on a path that may not have run.
      follows = [
        { label = ".Lprobe_4:"; instruction = "lw s11,-60(s0)"; }
      ];
    }
    {
      file = "save";
      present = [ "call __mulsi3" "beq s11,zero,.Lhold_3" "lw s10,-56(s0)" ];
      absent = [ "%" ];
      instructions = 20;
      follows = [ { label = ".Lhold_4:"; instruction = "lw s11,-60(s0)"; } ];
    }
    {
      file = "argcall";
      present = [ "call __mulsi3" "mv a0,s1" "li s1,1" "mv a1,s1" "call h" ];
      absent = [ "%" ];
      instructions = 12;
      follows = [ ];
    }
  ];

  # --- execution (run.sh) --------------------------------------------------
  # Each case is linked against runtime.s and drivers/<name>.s, run in the Nix
  # RV32I emulator, and its exit code compared with what the host compiler
  # makes of the SAME .c through drivers/<name>.c. The expected value is
  # written here too, so that both compilers agreeing on a wrong answer is
  # still a failure.
  execution = [
    { file = "expr"; expect = 72; why = "f(7,3): x=7+3=10, -1=9, *3=27, /3=9, <<2=36, g=36, h(36,36)=72"; }
    { file = "loop"; expect = 119; why = "sum of 3, -1, 10, 7, 100"; }
    { file = "field"; expect = 29; why = "dist({11,40}) = 40 - 11"; }
    { file = "mod"; expect = -2; why = "rem(-7,3): C truncates toward zero, so -7 % 3 is -1, the branch fires, -1-1 = -2"; }
    { file = "cond"; expect = 14; why = "probe(5,9) = 5 + (5 ? 9 : 5) = 14"; }
    { file = "save"; expect = 55; why = "hold(6,7) = 6 + (6 ? 7*7 : 6) = 55"; }
    { file = "argcall"; expect = 37; why = "nested(6) = h(6*6, 1) = 37"; }
  ];
}
