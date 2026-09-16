# An lburg machine description for RV32I, written as Nix data.
#
# This is the whole point of the PoC. lcc selects instructions from a table of
# rules -- nonterminal, tree pattern, cost, template -- and nothing else; see
# lcc/src/mips.md, whose shape this deliberately copies:
#
#     addr: ADDI4(reg,acon)  "%1($%0)"
#     reg:  INDIRI4(addr)    "lw $%c,%0\n"  1
#
# becomes
#
#     { nt = "addr"; op = "ADDI4"; kids = [ "reg" "con" ]; tmpl = "%1(%0)"; }
#     { nt = "reg";  op = "INDIRI4"; kids = [ "addr" ]; cost = 1; tmpl = "lw %c,%0\n"; }
#
# There is no emission code anywhere: burg.nix knows how to expand a template
# and nothing about RISC-V. Adding an instruction means adding a row here.
#
# Template escapes, the same set mips.md uses:
#   %0 %1  the reduced kids' result text
#   %c     the register this node's value is produced in
#   %a     the node's own operand text -- a constant's value, a global's name,
#          a local's frame offset, a branch's target label. Which of those it
#          is depends on the opcode, exactly as in lcc, where the md's own
#          local()/address()/defsymbol() decide what a symbol's x.name says.
#   %A     the argument register an ARG node must deposit its value in
#   %E     the enclosing function's epilogue label
#   %%     a literal percent, so that %hi()/%lo() relocations stay writable
#
# A template containing a newline is an INSTRUCTION: it is emitted, and its
# result text is %c. A template without one is a FRAGMENT: nothing is emitted
# and the expansion itself is the result text, which is how an addressing mode
# gets folded into its parent's instruction. That is lcc's own convention.
#
# A rule with no `op` is a CHAIN rule: it rewrites one nonterminal into
# another, and `kids = [ "from" ]`.
#
# `when` is a predicate on the node, the counterpart of lburg's cost
# expressions (`range(a, 0, 0)` in mips.md). It is data, not a function:
# burg.nix interprets it. Two are implemented: `range`, on a constant's value,
# and `srcSize`, on a conversion's SOURCE width -- see the conversion block
# below for why the second one has to exist.
#
# MULI4/DIVI4/MODI4 -- and their unsigned twins MULU4/DIVU4/MODU4 -- are NOT
# instructions here. RV32I has no M extension (decision-003), so they are
# libcalls into __mulsi3/__divsi3/__modsi3/__udivsi3/__umodsi3. The oracle
# prints them inline because it runs with mulops_calls=0 (decision-004); a rule
# table is exactly the right place to absorb that difference, and doing it here
# rather than by rewriting the DAG is itself evidence for the approach.
let
  # Sizes and costs are in "instructions", the unit lburg mds use.
  callCost = 4; # jal + the pipeline it costs, roughly
  libcallCost = 10; # argument moves + call + result move, plus a nudge so
  # anything cheaper is preferred if it ever exists
in
{
  # The nonterminal a statement reduces from, and the one that means "in a
  # register". burg.nix reads both from here rather than spelling them, so
  # this table -- and not the matcher -- is what names them.
  start = "stmt";
  regNt = "reg";

  # Every nonterminal the table produces, declared so a typo in a rule's `nt`
  # or `kids` is a throw rather than a silently unmatchable rule.
  nonterminals = [ "stmt" "reg" "con" "acon" "addr" ];

  # REGULAR EXPRESSIONS matched against emitted code, meaning "this calls
  # something", and
  # therefore destroys the argument registers and every caller-saved one.
  # burg.nix derives that property from the templates through these markers
  # instead of keeping its own list of call opcodes, which had already drifted
  # out of step with the rules below. On a target with a hardware multiplier,
  # MULI4's template stops saying `call' and stops being a call, with nothing
  # else to edit.
  callMarkers = [ "call " "jalr " ];

  rules = [
    # --- leaves -----------------------------------------------------------
    # A constant small enough for an I-type immediate field. RV32I immediates
    # are 12-bit signed.
    {
      id = "con_cnst";
      nt = "con";
      op = "CNSTI4";
      kids = [ ];
      cost = 0;
      tmpl = "%a";
      when = { range = [ (-2048) 2047 ]; };
    }
    # x0 reads as zero, so a zero constant needs no instruction at all. This
    # competes with `con: CNSTI4` + `reg: con` (cost 1) and wins on cost --
    # the direct analogue of mips.md's `reg: CNSTI4 "# reg\n" range(a, 0, 0)`.
    {
      id = "reg_zero";
      nt = "reg";
      op = "CNSTI4";
      kids = [ ];
      cost = 0;
      tmpl = "zero";
      when = { range = [ 0 0 ]; };
    }
    # The fallback for constants too wide for an immediate field. `li` is a
    # GNU as pseudo-instruction that expands to lui+addi when it has to.
    { id = "reg_cnst_wide"; nt = "reg"; op = "CNSTI4"; kids = [ ]; cost = 2; tmpl = "li %c,%a\n"; }

    # A one-byte constant. lcc types a character constant by its
    # DESTINATION, so `buf[0] = '\n'` arrives as CNSTI1 rather than CNSTI4
    # (poc/05-loop/hello.c is where this first appeared). Its value always
    # fits an immediate field, so there is no wide fallback beside it and a
    # CNSTI1 outside the range would be refused rather than truncated.
    {
      id = "con_cnst1";
      nt = "con";
      op = "CNSTI1";
      kids = [ ];
      cost = 0;
      tmpl = "%a";
      when = { range = [ (-2048) 2047 ]; };
    }

    # An UNSIGNED constant, which lcc spells differently from a signed one:
    # sym.c prints it as `0x...' from 32768 up and in decimal below that
    # (`(v.u&~0x7FFF) ? "0x%X" : "%U"' -- the mask is bit 15 INCLUSIVE). Two
    # consequences, and both are load-bearing:
    #
    #   * the `range' predicate reads `emit.nix''s `constValue', which parses
    #     DECIMAL only and returns null for a hex spelling, so `con_cnstu'
    #     simply never matches one. That is not a gap: the cut is at 32768 and
    #     this range stops at 2047, so every value this rule could accept is
    #     printed in decimal anyway.
    #   * the wide fallback hands `%a' to the assembler verbatim, hex and
    #     all, and poc/04-assembler's `parseInt' reads `0x...'. So
    #     `li %c,0xffffff0a' assembles; it is `encode.u32' that decides what
    #     the 32-bit pattern is, which is where decision-001's overflow rule
    #     belongs.
    #
    # The range is [0, 2047] and not [-2048, 2047]: an unsigned constant's
    # listed value is its UNSIGNED reading, so a negative bound could only be
    # matched by a value that is not there, and 2047 is the largest positive
    # immediate the I-type field holds.
    {
      id = "con_cnstu";
      nt = "con";
      op = "CNSTU4";
      kids = [ ];
      cost = 0;
      tmpl = "%a";
      when = { range = [ 0 2047 ]; };
    }
    {
      id = "reg_zerou";
      nt = "reg";
      op = "CNSTU4";
      kids = [ ];
      cost = 0;
      tmpl = "zero";
      when = { range = [ 0 0 ]; };
    }
    { id = "reg_cnstu_wide"; nt = "reg"; op = "CNSTU4"; kids = [ ]; cost = 2; tmpl = "li %c,%a\n"; }

    { id = "acon_addrgp"; nt = "acon"; op = "ADDRGP4"; kids = [ ]; cost = 0; tmpl = "%a"; }

    # A local or an incoming parameter is a displacement off the frame
    # pointer, so it folds straight into a load or store.
    { id = "addr_addrlp"; nt = "addr"; op = "ADDRLP4"; kids = [ ]; cost = 0; tmpl = "%a(s0)"; }
    { id = "addr_addrfp"; nt = "addr"; op = "ADDRFP4"; kids = [ ]; cost = 0; tmpl = "%a(s0)"; }
    # ... but taking its address needs a real instruction.
    { id = "reg_addrlp"; nt = "reg"; op = "ADDRLP4"; kids = [ ]; cost = 1; tmpl = "addi %c,s0,%a\n"; }
    { id = "reg_addrfp"; nt = "reg"; op = "ADDRFP4"; kids = [ ]; cost = 1; tmpl = "addi %c,s0,%a\n"; }

    # --- chain rules ------------------------------------------------------
    { id = "reg_from_con"; nt = "reg"; kids = [ "con" ]; cost = 1; tmpl = "li %c,%0\n"; }
    { id = "reg_from_acon"; nt = "reg"; kids = [ "acon" ]; cost = 2; tmpl = "la %c,%0\n"; }
    { id = "addr_from_reg"; nt = "addr"; kids = [ "reg" ]; cost = 0; tmpl = "0(%0)"; }
    # Evaluate a value and drop it: lcc's `stmt: reg ""`.
    { id = "stmt_from_reg"; nt = "stmt"; kids = [ "reg" ]; cost = 0; tmpl = ""; }

    # --- addressing -------------------------------------------------------
    # The classic lburg win: reg+const folds into the load's displacement
    # instead of becoming its own `addi`.
    { id = "addr_addi"; nt = "addr"; op = "ADDI4"; kids = [ "reg" "con" ]; cost = 0; tmpl = "%1(%0)"; }
    { id = "addr_addp"; nt = "addr"; op = "ADDP4"; kids = [ "reg" "con" ]; cost = 0; tmpl = "%1(%0)"; }

    # --- memory -----------------------------------------------------------
    { id = "reg_indiri"; nt = "reg"; op = "INDIRI4"; kids = [ "addr" ]; cost = 1; tmpl = "lw %c,%0\n"; }
    { id = "reg_indirp"; nt = "reg"; op = "INDIRP4"; kids = [ "addr" ]; cost = 1; tmpl = "lw %c,%0\n"; }
    { id = "reg_indiru"; nt = "reg"; op = "INDIRU4"; kids = [ "addr" ]; cost = 1; tmpl = "lw %c,%0\n"; }
    { id = "stmt_asgni"; nt = "stmt"; op = "ASGNI4"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sw %1,%0\n"; }
    { id = "stmt_asgnp"; nt = "stmt"; op = "ASGNP4"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sw %1,%0\n"; }
    { id = "stmt_asgnu"; nt = "stmt"; op = "ASGNU4"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sw %1,%0\n"; }

    # --- narrow memory: char and short (task-024) -------------------------
    # THE SIGN IS IN THE INSTRUCTION, not in a conversion after it. `lb'
    # sign-extends its byte into the whole register and `lbu' zero-extends
    # it, so signed and unsigned char are two different rows here and not one
    # row plus a fix-up.
    #
    # Swapping the pair is nonetheless INVISIBLE to anything that runs today,
    # and the honest place to say so is here. lcc promotes every narrow load,
    # so the conversion above re-normalises the register and `lb' and `lbu'
    # leave the same 32 bits; measured, the whole table with the two
    # exchanged still returns 1649 from ir/chars.c. cases.nix's `lowerings'
    # is what checks it, against this table, until task-033 fuses the load
    # and the conversion and the load becomes the extension.
    #
    # Stores do not care: `sb' writes the low byte whatever is above it, so
    # the signed and unsigned rows differ only in which opcode they match.
    { id = "reg_indiri1"; nt = "reg"; op = "INDIRI1"; kids = [ "addr" ]; cost = 1; tmpl = "lb %c,%0\n"; }
    { id = "reg_indiru1"; nt = "reg"; op = "INDIRU1"; kids = [ "addr" ]; cost = 1; tmpl = "lbu %c,%0\n"; }
    { id = "reg_indiri2"; nt = "reg"; op = "INDIRI2"; kids = [ "addr" ]; cost = 1; tmpl = "lh %c,%0\n"; }
    { id = "reg_indiru2"; nt = "reg"; op = "INDIRU2"; kids = [ "addr" ]; cost = 1; tmpl = "lhu %c,%0\n"; }
    { id = "stmt_asgni1"; nt = "stmt"; op = "ASGNI1"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sb %1,%0\n"; }
    { id = "stmt_asgnu1"; nt = "stmt"; op = "ASGNU1"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sb %1,%0\n"; }
    { id = "stmt_asgni2"; nt = "stmt"; op = "ASGNI2"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sh %1,%0\n"; }
    { id = "stmt_asgnu2"; nt = "stmt"; op = "ASGNU2"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sh %1,%0\n"; }

    # --- conversions (task-024) -------------------------------------------
    # lcc wraps every narrow access in one of these, so a rule table with the
    # loads above and none of these would refuse rather than narrow silently
    # -- the right failure, still a failure.
    #
    # WHERE THE WIDTHS ARE. A conversion opcode carries its DESTINATION width
    # in its own name and its SOURCE width in the node's symbol: CVII4 with a
    # `1' is "sign-extend from one byte" and CVII4 with a `2' is "from two",
    # and those are different instructions. The opcode alone cannot decide,
    # which is why `srcSize' exists as a predicate and why the widening rows
    # come in pairs. The narrowing rows need no predicate: their destination
    # is in the opcode and the source width does not change what they emit.
    #
    # RV32I has no sign-extend or zero-extend instruction, so every one of
    # these is a shift pair or a mask -- except at width 4, where the
    # conversion is a reinterpretation between int and unsigned and the value
    # is already right. That case still emits `mv' rather than folding to
    # nothing: a zero-cost fragment would hand this node's users whatever
    # register its KID was reduced into, and the depth registers are reused
    # between statements. burg.nix REFUSES such a rule on the table, so this
    # is a throw and not only a comment. All four of the moves ir/chars.c
    # emits are currently self-moves, because a one-kid node's kid is reduced
    # at the same depth -- the hazard is real and unexercised at once, and
    # making it free needs the register allocator (task-016), not this file.
    #
    # mips.md needs no `srcSize' for these because it puts ARITHMETIC in the
    # template -- `sll $%c,$%0,8*(4-%a)' -- and lets the assembler compute
    # the shift from the width. These templates have no arithmetic, so one
    # row per width is the substitute.
    #
    # NOT DONE, deliberately: mips.md's fused two-level patterns, where
    # `reg: CVII4(INDIRI1(addr))' is one `lb' because the load already
    # sign-extended. burg.nix matches one level of tree, so fusing needs
    # either nested patterns or a nonterminal per extension state. The
    # unfused form below is correct and costs two extra instructions per
    # narrow load: 23 of the 91 instructions ir/chars.c compiles to are
    # extensions, plus 4 self-moves from the width-4 rules below. Filed as
    # task-033 rather than smuggled in here.
    #
    # It has a consequence worth knowing before reading the sign paragraph
    # above: because the conversion re-normalises the register, `lb' and
    # `lbu' leave the same 32 bits behind and NO executed answer can tell
    # them apart today. cases.nix's `narrowLoads' checks that against this
    # table instead, and says so.
    #
    # WHICH CELLS ARE MISSING, and why. This block covers exactly the
    # conversions lcc emits for the corpus: CVUI4 at widths 1, 2 and 4,
    # CVIU4 at 4, and the narrowing CVII1/CVII2/CVUU1/CVUU2. CVUU4 has no
    # row at all and CVIU4 none below width 4, because no C in the corpus
    # produces them. That is a trace of what has been seen, not a
    # specification of what exists -- an absent cell is a loud refusal
    # naming the opcode, which is the right failure, but a reader auditing
    # for completeness should expect to add rows rather than find them.
    {
      id = "reg_cvii4_1";
      nt = "reg";
      op = "CVII4";
      kids = [ "reg" ];
      cost = 2;
      tmpl = "slli %c,%0,24\nsrai %c,%c,24\n";
      when = { srcSize = 1; };
    }
    {
      id = "reg_cvii4_2";
      nt = "reg";
      op = "CVII4";
      kids = [ "reg" ];
      cost = 2;
      tmpl = "slli %c,%0,16\nsrai %c,%c,16\n";
      when = { srcSize = 2; };
    }
    {
      id = "reg_cvui4_1";
      nt = "reg";
      op = "CVUI4";
      kids = [ "reg" ];
      cost = 1;
      tmpl = "andi %c,%0,255\n";
      when = { srcSize = 1; };
    }
    {
      id = "reg_cvui4_2";
      nt = "reg";
      op = "CVUI4";
      kids = [ "reg" ];
      cost = 2;
      tmpl = "slli %c,%0,16\nsrli %c,%c,16\n";
      when = { srcSize = 2; };
    }
    # Width 4 both ways: unsigned and int are the same 32 bits, so this is a
    # reinterpretation and the only work is the move explained above.
    {
      id = "reg_cvui4_4";
      nt = "reg";
      op = "CVUI4";
      kids = [ "reg" ];
      cost = 1;
      tmpl = "mv %c,%0\n";
      when = { srcSize = 4; };
    }
    {
      id = "reg_cviu4_4";
      nt = "reg";
      op = "CVIU4";
      kids = [ "reg" ];
      cost = 1;
      tmpl = "mv %c,%0\n";
      when = { srcSize = 4; };
    }
    # Narrowing. The destination width is in the opcode, so no predicate.
    { id = "reg_cvii1"; nt = "reg"; op = "CVII1"; kids = [ "reg" ]; cost = 2; tmpl = "slli %c,%0,24\nsrai %c,%c,24\n"; }
    { id = "reg_cvii2"; nt = "reg"; op = "CVII2"; kids = [ "reg" ]; cost = 2; tmpl = "slli %c,%0,16\nsrai %c,%c,16\n"; }
    { id = "reg_cvuu1"; nt = "reg"; op = "CVUU1"; kids = [ "reg" ]; cost = 1; tmpl = "andi %c,%0,255\n"; }
    # 0xffff does not fit `andi''s 12-bit immediate, so the halfword mask is a
    # shift pair where the byte mask is one instruction.
    { id = "reg_cvuu2"; nt = "reg"; op = "CVUU2"; kids = [ "reg" ]; cost = 2; tmpl = "slli %c,%0,16\nsrli %c,%c,16\n"; }

    # --- integer arithmetic ----------------------------------------------
    { id = "reg_addi_imm"; nt = "reg"; op = "ADDI4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "addi %c,%0,%1\n"; }
    { id = "reg_addi_reg"; nt = "reg"; op = "ADDI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "add %c,%0,%1\n"; }
    { id = "reg_addp_imm"; nt = "reg"; op = "ADDP4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "addi %c,%0,%1\n"; }
    { id = "reg_addp_reg"; nt = "reg"; op = "ADDP4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "add %c,%0,%1\n"; }
    # No `subi`: RV32I has none, and the front end has already folded what it
    # could. SUBI4 against a constant therefore goes through `li`.
    { id = "reg_subi"; nt = "reg"; op = "SUBI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "sub %c,%0,%1\n"; }
    { id = "reg_lshi_imm"; nt = "reg"; op = "LSHI4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "slli %c,%0,%1\n"; }
    { id = "reg_lshi_reg"; nt = "reg"; op = "LSHI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "sll %c,%0,%1\n"; }
    { id = "reg_rshi_imm"; nt = "reg"; op = "RSHI4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "srai %c,%0,%1\n"; }
    { id = "reg_rshi_reg"; nt = "reg"; op = "RSHI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "sra %c,%0,%1\n"; }

    # --- bitwise and unary (task-051) --------------------------------------
    # One RV32I instruction each, in both the register and the immediate
    # form, exactly like the adds above. `andi'/`ori'/`xori' sign-extend
    # their 12-bit field, which is why `con' stops at 2047: a mask wider than
    # that is materialised by `reg_cnst_wide' and uses the register form.
    { id = "reg_bandi_imm"; nt = "reg"; op = "BANDI4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "andi %c,%0,%1\n"; }
    { id = "reg_bandi_reg"; nt = "reg"; op = "BANDI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "and %c,%0,%1\n"; }
    { id = "reg_bori_imm"; nt = "reg"; op = "BORI4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "ori %c,%0,%1\n"; }
    { id = "reg_bori_reg"; nt = "reg"; op = "BORI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "or %c,%0,%1\n"; }
    { id = "reg_bxori_imm"; nt = "reg"; op = "BXORI4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "xori %c,%0,%1\n"; }
    { id = "reg_bxori_reg"; nt = "reg"; op = "BXORI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "xor %c,%0,%1\n"; }

    # RV32I HAS NEITHER OF THESE as an instruction, and both are written out
    # rather than spelled as the `neg'/`not' pseudo-instructions
    # poc/04-assembler also implements. The expansion is the whole content of
    # the rule -- `sub' from the zero register and `xor' with all ones -- and
    # writing it here keeps it in the table, where a reader auditing what this
    # target can do sees it, instead of in the assembler's pseudo-instruction
    # list where it looks like an instruction that exists.
    { id = "reg_negi"; nt = "reg"; op = "NEGI4"; kids = [ "reg" ]; cost = 1; tmpl = "sub %c,zero,%0\n"; }
    { id = "reg_bcomi"; nt = "reg"; op = "BCOMI4"; kids = [ "reg" ]; cost = 1; tmpl = "xori %c,%0,-1\n"; }

    # --- the multiply/divide libcalls (decision-003) -----------------------
    # These read as instructions in the oracle's listing and are not ones.
    # Nothing else in the compiler needs to know: the difference lives in
    # three rows of this table.
    {
      id = "reg_muli_libcall";
      nt = "reg";
      op = "MULI4";
      kids = [ "reg" "reg" ];
      cost = libcallCost;
      tmpl = "mv a0,%0\nmv a1,%1\ncall __mulsi3\nmv %c,a0\n";
    }
    {
      id = "reg_divi_libcall";
      nt = "reg";
      op = "DIVI4";
      kids = [ "reg" "reg" ];
      cost = libcallCost;
      tmpl = "mv a0,%0\nmv a1,%1\ncall __divsi3\nmv %c,a0\n";
    }
    {
      id = "reg_modi_libcall";
      nt = "reg";
      op = "MODI4";
      kids = [ "reg" "reg" ];
      cost = libcallCost;
      tmpl = "mv a0,%0\nmv a1,%1\ncall __modsi3\nmv %c,a0\n";
    }

    # --- the U-typed opcodes (task-051) -------------------------------------
    # lcc types every operator by its OPERANDS, so `unsigned' arithmetic
    # arrives as a parallel family of opcodes -- ADDU4 beside ADDI4, RSHU4
    # beside RSHI4 -- and a table with only the I-typed half refuses every C
    # program that says `unsigned'. Most of these rows are the signed row with
    # the letter changed, and saying so is more honest than implying they are
    # all interesting. FOUR ARE NOT, and they are the reason this block cannot
    # be generated from the signed one:
    #
    #   RSHU4   is `srl', a LOGICAL shift, where RSHI4 is `sra' -- in both
    #           the immediate and the register form, so that is two rows.
    #           Selecting `sra' here compiles, assembles, runs, and gives the
    #           wrong answer for every value with bit 31 set -- and for no
    #           other value, so a test whose data stays small cannot see it.
    #   DIVU4   and MODU4 are __udivsi3/__umodsi3, NOT the signed routines.
    #           Same argument: they agree on every operand below 2^31.
    #   the four ORDERING comparisons are `bltu'/`bgeu' and their two swapped
    #           forms, not `blt'/`bge'. Same argument again. EQU4 and NEU4 are
    #           not in this list: equality orders nothing, so they are `beq'
    #           and `bne' exactly as the signed pair is.
    #
    # cases.nix's `pairs' table is where that four-against-the-rest split is
    # written down as data and checked against these templates, in both
    # directions -- so a row that stopped differing, and a row that started,
    # are each a named failure rather than a comment nobody re-read.
    #
    # MULU4 deliberately shares __mulsi3 with MULI4: the low 32 bits of a
    # product do not depend on how the operands are read, which is why one
    # shift-and-add routine answers both. That is a claim about two's
    # complement, not an approximation.
    #
    # THERE IS NO NEGU4 ROW because there is no NEGU4: lcc's ops.h gives NEG
    # the I and F kinds and not U, so `-u' on an unsigned operand arrives as
    # BCOMU4 followed by ADDU4(.,CNSTU4 1) -- two's complement written out in
    # the IR. Checked against rcc-rv32 rather than reasoned from the header.
    # An absent row is a loud refusal naming the opcode, so a reader auditing
    # for completeness should expect to add rows rather than find them.
    { id = "reg_addu_imm"; nt = "reg"; op = "ADDU4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "addi %c,%0,%1\n"; }
    { id = "reg_addu_reg"; nt = "reg"; op = "ADDU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "add %c,%0,%1\n"; }
    { id = "reg_subu"; nt = "reg"; op = "SUBU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "sub %c,%0,%1\n"; }
    { id = "reg_lshu_imm"; nt = "reg"; op = "LSHU4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "slli %c,%0,%1\n"; }
    { id = "reg_lshu_reg"; nt = "reg"; op = "LSHU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "sll %c,%0,%1\n"; }
    # THE ONE ROW IN THIS BLOCK THAT IS NOT ITS SIGNED TWIN. `srl', not `sra'.
    { id = "reg_rshu_imm"; nt = "reg"; op = "RSHU4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "srli %c,%0,%1\n"; }
    { id = "reg_rshu_reg"; nt = "reg"; op = "RSHU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "srl %c,%0,%1\n"; }
    { id = "reg_bandu_imm"; nt = "reg"; op = "BANDU4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "andi %c,%0,%1\n"; }
    { id = "reg_bandu_reg"; nt = "reg"; op = "BANDU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "and %c,%0,%1\n"; }
    { id = "reg_boru_imm"; nt = "reg"; op = "BORU4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "ori %c,%0,%1\n"; }
    { id = "reg_boru_reg"; nt = "reg"; op = "BORU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "or %c,%0,%1\n"; }
    { id = "reg_bxoru_imm"; nt = "reg"; op = "BXORU4"; kids = [ "reg" "con" ]; cost = 1; tmpl = "xori %c,%0,%1\n"; }
    { id = "reg_bxoru_reg"; nt = "reg"; op = "BXORU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "xor %c,%0,%1\n"; }
    { id = "reg_bcomu"; nt = "reg"; op = "BCOMU4"; kids = [ "reg" ]; cost = 1; tmpl = "xori %c,%0,-1\n"; }

    {
      id = "reg_mulu_libcall";
      nt = "reg";
      op = "MULU4";
      kids = [ "reg" "reg" ];
      cost = libcallCost;
      tmpl = "mv a0,%0\nmv a1,%1\ncall __mulsi3\nmv %c,a0\n";
    }
    {
      id = "reg_divu_libcall";
      nt = "reg";
      op = "DIVU4";
      kids = [ "reg" "reg" ];
      cost = libcallCost;
      tmpl = "mv a0,%0\nmv a1,%1\ncall __udivsi3\nmv %c,a0\n";
    }
    {
      id = "reg_modu_libcall";
      nt = "reg";
      op = "MODU4";
      kids = [ "reg" "reg" ];
      cost = libcallCost;
      tmpl = "mv a0,%0\nmv a1,%1\ncall __umodsi3\nmv %c,a0\n";
    }

    # --- calls ------------------------------------------------------------
    # A call to a known symbol beats materialising its address and jalr-ing
    # through it. Cost, not rule order, decides that.
    #
    # THE UNITS: `callCost' is the call itself, and every further instruction
    # a rule emits costs one more. So a value-producing call is callCost + 1
    # because it also moves a0, and an indirect one is one dearer again
    # because the address has to be in a register first. Nothing here is
    # cheaper for being in a statement position -- the statement rows below
    # are cheaper because they emit less.
    { id = "reg_calli_direct"; nt = "reg"; op = "CALLI4"; kids = [ "acon" ]; cost = callCost + 1; tmpl = "call %0\nmv %c,a0\n"; }
    { id = "reg_calli_indirect"; nt = "reg"; op = "CALLI4"; kids = [ "reg" ]; cost = callCost + 2; tmpl = "jalr %0\nmv %c,a0\n"; }
    { id = "stmt_callv_direct"; nt = "stmt"; op = "CALLV"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\n"; }
    { id = "stmt_callv_indirect"; nt = "stmt"; op = "CALLV"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\n"; }
    # A call whose int result is DISCARDED -- `wr(1, buf, 11);' as a
    # statement. lcc lists it as a root nothing references, so it reduces to
    # `stmt' and not to `reg'. Without these two rows the chain rule
    # `stmt: reg' took it instead and handed a null destination to a template
    # saying `mv %c,a0', which refused while naming the template rather than
    # the discarded return value (task-025).
    #
    # They are the `reg' rules with the result move dropped, and cost one less
    # for exactly that reason -- not because a statement is cheaper.
    #
    # THAT DIFFERENCE IS LOAD-BEARING, and not only tidy. `stmt: reg' can
    # also take this node, at the `reg' rule's cost plus nothing, so the
    # statement row wins by exactly the instruction it does not emit. Price
    # these the same as the `reg' rows and the choice becomes a tie decided
    # by the order the labeller happens to seed its map in; price them dearer
    # and the chain wins, the destination is null, and the whole thing
    # refuses. Measured both ways.
    #
    # CALLP4 and CALLD4 get no rows: nothing in the corpus produces either,
    # and neither has a `reg' rule to pair with, so both refuse (task-036).
    { id = "stmt_calli_direct"; nt = "stmt"; op = "CALLI4"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\n"; }
    { id = "stmt_calli_indirect"; nt = "stmt"; op = "CALLI4"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\n"; }
    { id = "stmt_argi"; nt = "stmt"; op = "ARGI4"; kids = [ "reg" ]; cost = 1; tmpl = "mv %A,%0\n"; }
    { id = "stmt_argp"; nt = "stmt"; op = "ARGP4"; kids = [ "reg" ]; cost = 1; tmpl = "mv %A,%0\n"; }

    # The U-typed call, argument and return. A word is a word whichever way it
    # is read, so these are the I-typed rows with the letter changed and the
    # same costs for the same reasons -- including the two `stmt' rows, which
    # are cheaper by exactly the result move they do not emit (task-025).
    { id = "reg_callu_direct"; nt = "reg"; op = "CALLU4"; kids = [ "acon" ]; cost = callCost + 1; tmpl = "call %0\nmv %c,a0\n"; }
    { id = "reg_callu_indirect"; nt = "reg"; op = "CALLU4"; kids = [ "reg" ]; cost = callCost + 2; tmpl = "jalr %0\nmv %c,a0\n"; }
    { id = "stmt_callu_direct"; nt = "stmt"; op = "CALLU4"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\n"; }
    { id = "stmt_callu_indirect"; nt = "stmt"; op = "CALLU4"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\n"; }
    { id = "stmt_argu"; nt = "stmt"; op = "ARGU4"; kids = [ "reg" ]; cost = 1; tmpl = "mv %A,%0\n"; }

    # --- control flow -----------------------------------------------------
    { id = "stmt_reti"; nt = "stmt"; op = "RETI4"; kids = [ "reg" ]; cost = 1; tmpl = "mv a0,%0\nj %E\n"; }
    { id = "stmt_retu"; nt = "stmt"; op = "RETU4"; kids = [ "reg" ]; cost = 1; tmpl = "mv a0,%0\nj %E\n"; }
    { id = "stmt_jumpv"; nt = "stmt"; op = "JUMPV"; kids = [ "acon" ]; cost = 1; tmpl = "j %0\n"; }

    # lcc emits the *inverted* test and branches to the join label, so
    # `if (x > 10)` arrives as LEI4(x, 10, L). One rule per comparison; the
    # branch target is the node's own symbol, i.e. %a.
    { id = "stmt_lei4"; nt = "stmt"; op = "LEI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "ble %0,%1,%a\n"; }
    { id = "stmt_lti4"; nt = "stmt"; op = "LTI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "blt %0,%1,%a\n"; }
    { id = "stmt_gei4"; nt = "stmt"; op = "GEI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bge %0,%1,%a\n"; }
    { id = "stmt_gti4"; nt = "stmt"; op = "GTI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "blt %1,%0,%a\n"; }
    { id = "stmt_eqi4"; nt = "stmt"; op = "EQI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "beq %0,%1,%a\n"; }
    { id = "stmt_nei4"; nt = "stmt"; op = "NEI4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bne %0,%1,%a\n"; }

    # And the unsigned four, which are DIFFERENT INSTRUCTIONS and not the same
    # ones on differently-typed operands: `bltu'/`bgeu' order the operands as
    # 32-bit magnitudes where `blt'/`bge' order them as two's-complement
    # integers, and the two disagree on exactly the values with bit 31 set.
    # A corpus whose unsigned data stays below 2^31 cannot tell them apart, so
    # ir/unsig.c's does not.
    #
    # `bleu' and `bgtu' are poc/04-assembler pseudo-instructions that swap the
    # operands of `bgeu' and `bltu'. The spelling follows the signed rows
    # above verbatim, swap and all, so that each pair reads as a pair: LEI4
    # uses the pseudo-instruction and GTI4 writes the swap out, and LEU4 and
    # GTU4 do the same.
    #
    # EQU4 and NEU4 are `beq'/`bne' with no unsigned form to choose between,
    # because equality does not order anything.
    { id = "stmt_leu4"; nt = "stmt"; op = "LEU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bleu %0,%1,%a\n"; }
    { id = "stmt_ltu4"; nt = "stmt"; op = "LTU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bltu %0,%1,%a\n"; }
    { id = "stmt_geu4"; nt = "stmt"; op = "GEU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bgeu %0,%1,%a\n"; }
    { id = "stmt_gtu4"; nt = "stmt"; op = "GTU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bltu %1,%0,%a\n"; }
    { id = "stmt_equ4"; nt = "stmt"; op = "EQU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "beq %0,%1,%a\n"; }
    { id = "stmt_neu4"; nt = "stmt"; op = "NEU4"; kids = [ "reg" "reg" ]; cost = 1; tmpl = "bne %0,%1,%a\n"; }
  ];
}
