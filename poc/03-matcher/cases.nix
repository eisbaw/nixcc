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
    { name = "gsym"; fn = "pick"; what = "a global at a constant index, which lcc folds into one ADDRGP4 sym+N"; }
    { name = "chars"; fn = "scan"; what = "char and short: byte and halfword loads and stores, and the conversions over them"; }
  ];

  # Acceptance criterion 4 and 9: these opcodes must appear in the corpus DAGs
  # AND be matched there by a rule for that opcode. Listing an opcode no test
  # file contains is a harness fault, not a pass.
  requiredOps = [
    "CNSTI4" "ADDRLP4" "ADDRGP4" "ADDRFP4" "INDIRI4" "INDIRP4" "ASGNI4" "ASGNP4"
    "ADDI4" "ADDP4" "SUBI4" "LSHI4" "MULI4" "DIVI4" "MODI4"
    "CALLI4" "RETI4" "ARGI4" "JUMPV"
    "LEI4" "LTI4" "GEI4" "EQI4"
    # task-024: the narrow accesses, the word forms lcc emits for unsigned
    # int, and the conversions it wraps every one of them in.
    "INDIRI1" "INDIRU1" "INDIRI2" "INDIRU2" "INDIRU4"
    "ASGNI1" "ASGNU1" "ASGNI2" "ASGNU2" "ASGNU4"
    "CVII4" "CVUI4" "CVIU4" "CVII2" "CVUU1" "CVUU2"
    "CNSTI1"
  ];

  # WHICH INSTRUCTION EACH OPCODE LOWERS TO, and mostly the only place that
  # can say so. `opCovered' asserts that SOME rule for an opcode fired; it
  # never asserts which instruction that rule emits, and for most of the rows
  # below no executed answer does either.
  #
  # Measured, one rule at a time, by running ir/chars.c with the rule's
  # template changed and reading the emulator's exit code:
  #
  #   VISIBLE to the execution stage   reg_cvii4_1, reg_cvii4_2 (srai->srli),
  #                                    reg_cvui4_4, reg_cviu4_4 (mv->andi)
  #   BLIND                            every load and store row, and every
  #                                    narrowing conversion
  #
  # The loads are blind because lcc promotes every narrow access, so an
  # INDIRI1 always arrives under a CVII4 whose shift pair RE-NORMALISES the
  # register: `lb' and `lbu' leave the same 32 bits. The whole table with lb
  # and lbu exchanged still returns 1649. The narrowing conversions are blind
  # because `sb' and `sh' truncate anyway. Only a signed WIDENING is
  # observable today, and the rest becomes observable when task-033 fuses the
  # load and the conversion.
  #
  # So this is not a restatement of rules.nix, it is the substitute for an
  # oracle that does not exist yet -- and it catches a one-sided edit, which
  # is the realistic mistake. `mnemonic' is compared against the template's
  # first TOKEN, not as a substring, because `lb' is a prefix of `lbu' and a
  # substring test would pass the very swap this exists to catch.
  lowerings = [
    { op = "INDIRI1"; rule = "reg_indiri1"; mnemonic = "lb"; }
    { op = "INDIRU1"; rule = "reg_indiru1"; mnemonic = "lbu"; }
    { op = "INDIRI2"; rule = "reg_indiri2"; mnemonic = "lh"; }
    { op = "INDIRU2"; rule = "reg_indiru2"; mnemonic = "lhu"; }
    { op = "ASGNI1"; rule = "stmt_asgni1"; mnemonic = "sb"; }
    { op = "ASGNU1"; rule = "stmt_asgnu1"; mnemonic = "sb"; }
    { op = "ASGNI2"; rule = "stmt_asgni2"; mnemonic = "sh"; }
    { op = "ASGNU2"; rule = "stmt_asgnu2"; mnemonic = "sh"; }
    # The WORD forms lcc emits for unsigned int. They are here because they
    # are the rows with the least else holding them: nothing else in this
    # file names an instruction for them, and lowering INDIRU4 to `lbu'
    # passed every other check in the suite AND returned the right answer.
    { op = "INDIRU4"; rule = "reg_indiru"; mnemonic = "lw"; }
    { op = "ASGNU4"; rule = "stmt_asgnu"; mnemonic = "sw"; }
    # The conversions. Two of these four are execution-visible and two are
    # not; see the measurement above.
    { op = "CVII4"; rule = "reg_cvii4_1"; mnemonic = "slli"; }
    { op = "CVUI4"; rule = "reg_cvui4_1"; mnemonic = "andi"; }
    { op = "CVUU1"; rule = "reg_cvuu1"; mnemonic = "andi"; }
    { op = "CVII1"; rule = "reg_cvii1"; mnemonic = "slli"; }
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
      # The rule table does NOT split `tbl+4' into an `la' and an `addi': the
      # node carries one symbol and `acon_addrgp' takes it verbatim, which is
      # why this costs what a bare global costs. What resolves the
      # displacement is poc/04-assembler, at layout time (task-023).
      what = "a global at a constant index is one symbol, at the price of one";
      file = "gsym"; forest = 0; node = "2"; nt = "acon"; rule = "acon_addrgp"; cost = 0;
    }
    {
      what = "so materialising its address is the same single `la'";
      file = "gsym"; forest = 0; node = "2"; nt = "reg"; rule = "reg_from_acon"; cost = 2;
    }
    {
      what = "a signed char is loaded with lb, which sign-extends it";
      file = "chars"; forest = 4; node = "7"; nt = "reg"; rule = "reg_indiri1"; cost = 5;
    }
    {
      what = "and an unsigned one with lbu, from the same addressing mode at the same price";
      file = "chars"; forest = 4; node = "13"; nt = "reg"; rule = "reg_indiru1"; cost = 5;
    }
    {
      # The two conversions over those two loads cost DIFFERENT amounts, and
      # that is the RV32I fact: widening a signed byte is a shift pair and
      # widening an unsigned one is a single `andi'.
      what = "widening the signed byte is a shift pair, so two instructions";
      file = "chars"; forest = 4; node = "6"; nt = "reg"; rule = "reg_cvii4_1"; cost = 7;
    }
    {
      what = "widening the unsigned byte is one mask, so one";
      file = "chars"; forest = 4; node = "12"; nt = "reg"; rule = "reg_cvui4_1"; cost = 6;
    }
    {
      what = "a halfword load carries its sign the same way, through lh";
      file = "chars"; forest = 7; node = "7"; nt = "reg"; rule = "reg_indiri2"; cost = 3;
    }
    {
      what = "and lhu for the unsigned one";
      file = "chars"; forest = 7; node = "10"; nt = "reg"; rule = "reg_indiru2"; cost = 3;
    }
    {
      # The conversion opcode is CVII4 here and at the byte above it, and the
      # shift amount differs. What tells them apart is the node's own symbol,
      # which is the whole reason `srcSize' is a predicate.
      what = "widening a signed halfword shifts by 16, where the byte shifted by 24";
      file = "chars"; forest = 7; node = "6"; nt = "reg"; rule = "reg_cvii4_2"; cost = 5;
    }
    {
      what = "storing a byte is `sb', whatever the value above the byte is";
      file = "chars"; forest = 7; node = "12"; nt = "stmt"; rule = "stmt_asgni1"; cost = 4;
    }
    {
      what = "a character constant is typed by its destination, so CNSTI1 and not CNSTI4";
      file = "chars"; forest = 7; node = "14"; nt = "con"; rule = "con_cnst1"; cost = 0;
    }
    {
      # int-to-unsigned at the same width changes nothing about the bits, and
      # the rule still emits a move rather than folding to nothing -- see the
      # conversion block in rules.nix for why.
      what = "int to unsigned at width 4 is a reinterpretation, priced as one move";
      file = "chars"; forest = 8; node = "4"; nt = "reg"; rule = "reg_cviu4_4"; cost = 2;
    }
    {
      # Narrowing does not need the predicate: CVII1 says "to one signed
      # byte" in the opcode, and where it came FROM does not change the
      # shift. The pair beside it above does need one.
      what = "narrowing an int to a signed char needs no source width at all";
      file = "chars"; forest = 7; node = "17"; nt = "reg"; rule = "reg_cvii1"; cost = 3;
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
    {
      file = "gsym";
      # Four different displacements off one base, including the bare base,
      # so a displacement dropped or applied to the wrong element shows up
      # here and not only in the answer.
      present = [
        "la s1,tbl+4"
        "la s3,tbl+8"
        "la s1,tbl+12"
        "la s2,tbl"
        "sw s2,0(s1)"
        "sub s1,s1,s2"
      ];
      # The other place this could have been fixed: splitting the symbol in
      # the rule table and emitting the displacement as its own `addi'
      # (task-023 weighed the two). It is not what happens, and a table that
      # started doing it would change these instruction counts silently.
      absent = [ "%" "addi s1,s1,4" "addi s2,s2,8" ];
      instructions = 17;
      follows = [ ];
    }
    {
      file = "chars";
      # One line per narrow access, and the four loads in BOTH signednesses.
      # This is where a swapped lb/lbu becomes visible as EMITTED TEXT, since
      # it is invisible in the answer (see `narrowLoads' above for why) --
      # though it is `narrowLoads' and not this list that says which opcode
      # each mnemonic belongs to.
      present = [
        "lb s3,0(s3)"
        "lbu s3,0(s3)"
        "lh s3,0(s3)"
        "lhu s3,0(s3)"
        "sb s2,0(s1)"
        "sh s2,0(s1)"
        # The extensions RV32I has no instruction for: a shift pair for a
        # signed widening, a mask for an unsigned byte one.
        "slli s3,s3,24"
        "srai s3,s3,24"
        "andi s3,s3,255"
        "srli s3,s3,16"
      ];
      # `sw sN,0(s1)' is the line that appears if a byte or halfword store
      # is widened: s1 is where this function materialises a global's
      # address, and every store through it must be narrow. A shift-by-8
      # would have been a vacuous assertion -- no rule in the table can emit
      # one -- so it is not here.
      absent = [ "%" "sw s2,0(s1)" ];
      instructions = 91;
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
    { file = "gsym"; expect = 116; why = "pick(20) on tbl={4,0,100,0}: tbl[1]=20, tbl[3]=20+100=120, and 120-tbl[0]=116"; }
    {
      file = "chars";
      expect = 1649;
      # The signed and unsigned readings of the SAME bytes, which is the
      # number lb-against-lbu changes: over 0xf0,0x01,0x7f,0x80 the signed
      # sum is -16+1+127-128 = -16 and the unsigned one 240+1+127+128 = 496,
      # so the loop contributes 480 and a swapped pair moves the answer by
      # 512. The halfword 0x8001 reads -32767 and 32769, adding 2, so
      # s = 482; then 482 + sbuf[0]=7 + shalf[1]=482 + u=226 + uhalf[1]=482.
      # 0xf0,0x01,0x7f,0x80 read signed sum to -16 and read unsigned to 496,
      # so the loop contributes 480; the halfword 0x8001 reads -32767 and
      # 32769, adding 2. That gives s = 482, and the return is
      # 482 + sbuf[0]=7 + sbuf[2]=(signed char)482=-30 + shalf[1]=482
      # + u=226 + uhalf[1]=482.
      #
      # What this number does NOT depend on is which of lb/lbu each load
      # used: every one of them is promoted by a conversion that
      # re-normalises the register. Swapping the pair leaves 1649. The load's
      # sign is checked in `narrowLoads' above, against the table, for
      # exactly that reason.
      why = "scan(4): 480 from the byte pairs, 2 from the halfword pair, then 482+7-30+482+226+482";
    }
  ];
}
