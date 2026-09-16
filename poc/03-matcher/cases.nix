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
    { name = "lbuf"; fn = "pack"; what = "a LOCAL array at a constant index, which arrives as ADDRLP4 sym+N -- a frame slot plus a displacement, not a name"; }
    { name = "chars"; fn = "scan"; what = "char and short: byte and halfword loads and stores, and the conversions over them"; }
    { name = "voidcall"; fn = "emit"; what = "an int-returning function called for its effect, beside a void call"; }
    { name = "bits"; fn = "mask"; what = "the bitwise and unary operators, each in both its register and its immediate form"; }
    { name = "unsig"; fn = "wide"; what = "the U-typed opcodes, on data whose top bit is set: the logical shift, the unsigned branches and the two libcalls with no signed counterpart"; }
    { name = "udiv"; fn = "wrap"; what = "an unsigned DIVISOR above 2^31, which is what the runtime routines' own comparison turns on"; }
    { name = "ptr"; fn = "walk"; what = "the pointer opcodes: a null comparison, a pointer difference, the casts between a pointer and an unsigned, and a function that RETURNS a pointer"; }
  ];

  # Acceptance criterion 4 and 9: these opcodes must appear in the corpus DAGs
  # AND be matched there by a rule for that opcode. Listing an opcode no test
  # file contains is a harness fault, not a pass.
  requiredOps = [
    "CNSTI4" "ADDRLP4" "ADDRGP4" "ADDRFP4" "INDIRI4" "INDIRP4" "ASGNI4" "ASGNP4"
    "ADDI4" "ADDP4" "SUBI4" "LSHI4" "MULI4" "DIVI4" "MODI4"
    "CALLI4" "CALLV" "RETI4" "ARGI4" "JUMPV"
    "LEI4" "LTI4" "GEI4" "EQI4"
    # task-024: the narrow accesses, the word forms lcc emits for unsigned
    # int, and the conversions it wraps every one of them in.
    "INDIRI1" "INDIRU1" "INDIRI2" "INDIRU2" "INDIRU4"
    "ASGNI1" "ASGNU1" "ASGNI2" "ASGNU2" "ASGNU4"
    "CVII4" "CVUI4" "CVIU4" "CVII2" "CVUU1" "CVUU2"
    "CNSTI1"
    # task-051: the bitwise and unary operators, which RV32I has instructions
    # for, and the two it has not -- BCOMI4 is `xori' with all ones and NEGI4
    # is `sub' from the zero register.
    "BANDI4" "BORI4" "BXORI4" "BCOMI4" "NEGI4"
    # task-051: the U-typed family. These are not the I-typed opcodes on
    # differently-typed operands, they are separate opcodes with separate
    # rules, and for RSHU4, DIVU4, MODU4 and the four ordering comparisons
    # they are separate INSTRUCTIONS.
    "CNSTU4" "ADDU4" "SUBU4" "MULU4" "DIVU4" "MODU4" "LSHU4" "RSHU4"
    "BANDU4" "BORU4" "BXORU4" "BCOMU4"
    "LEU4" "LTU4" "GEU4" "GTU4" "EQU4" "NEU4"
    "ARGU4" "CALLU4" "RETU4"
    # task-051 again, and these are I-typed: ir/bits.c gave the corpus its
    # first signed `>>' and its first `<=' and `==', so the signed halves of
    # the pairs above are now selected somewhere rather than only described.
    "RSHI4" "GTI4" "NEI4"
    # task-054: the pointer opcodes. ARGP4 has had a row since task-025 and no
    # corpus case had ever selected it (task-053); the other five had no row at
    # all, so `p == 0' compiled to IR that diffed clean against lcc and was
    # then refused at instruction selection.
    "CNSTP4" "CVUP4" "CVPU4" "SUBP4" "RETP4" "ARGP4"
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

    # --- task-051 ---------------------------------------------------------
    # WHAT THESE ROWS DO AND DO NOT SAY. Each one names a rule and the
    # mnemonic its template must start with. That is a claim about the TABLE
    # and not about the reduction: it does not say the named rule is the one
    # the matcher selects, and a cheaper shadowing rule added beside it would
    # satisfy every row here. `selections' is what pins the choice; these rows
    # pin what the chosen row emits, which is the half no executed answer
    # reaches for most of the conversions above.
    #
    # Both forms of each operator are listed, because the immediate form and
    # the register form are separate rules and a one-sided edit is the
    # realistic mistake.
    { op = "RSHI4"; rule = "reg_rshi_imm"; mnemonic = "srai"; }
    { op = "RSHI4"; rule = "reg_rshi_reg"; mnemonic = "sra"; }
    { op = "RSHU4"; rule = "reg_rshu_imm"; mnemonic = "srli"; }
    { op = "RSHU4"; rule = "reg_rshu_reg"; mnemonic = "srl"; }
    { op = "LSHI4"; rule = "reg_lshi_imm"; mnemonic = "slli"; }
    { op = "LSHI4"; rule = "reg_lshi_reg"; mnemonic = "sll"; }
    { op = "LSHU4"; rule = "reg_lshu_imm"; mnemonic = "slli"; }
    { op = "LSHU4"; rule = "reg_lshu_reg"; mnemonic = "sll"; }
    { op = "SUBU4"; rule = "reg_subu"; mnemonic = "sub"; }
    # `andi' is a prefix of nothing here, but `ori' is a substring of `xori',
    # which is exactly why this check compares the template's first TOKEN and
    # not a substring.
    { op = "BANDI4"; rule = "reg_bandi_imm"; mnemonic = "andi"; }
    { op = "BANDI4"; rule = "reg_bandi_reg"; mnemonic = "and"; }
    { op = "BORI4"; rule = "reg_bori_imm"; mnemonic = "ori"; }
    { op = "BORI4"; rule = "reg_bori_reg"; mnemonic = "or"; }
    { op = "BXORI4"; rule = "reg_bxori_imm"; mnemonic = "xori"; }
    { op = "BXORI4"; rule = "reg_bxori_reg"; mnemonic = "xor"; }
    { op = "BANDU4"; rule = "reg_bandu_imm"; mnemonic = "andi"; }
    { op = "BANDU4"; rule = "reg_bandu_reg"; mnemonic = "and"; }
    { op = "BORU4"; rule = "reg_boru_imm"; mnemonic = "ori"; }
    { op = "BORU4"; rule = "reg_boru_reg"; mnemonic = "or"; }
    { op = "BXORU4"; rule = "reg_bxoru_imm"; mnemonic = "xori"; }
    { op = "BXORU4"; rule = "reg_bxoru_reg"; mnemonic = "xor"; }
    # The two RV32I has no instruction for at all.
    { op = "BCOMI4"; rule = "reg_bcomi"; mnemonic = "xori"; }
    { op = "BCOMU4"; rule = "reg_bcomu"; mnemonic = "xori"; }
    { op = "NEGI4"; rule = "reg_negi"; mnemonic = "sub"; }
    # The branches, signed beside unsigned. GTI4/GTU4 carry no row: their
    # templates SWAP the operands rather than changing the mnemonic, so the
    # mnemonic alone cannot tell a correct rule from one that dropped the
    # swap. What pins those two is the emitted text in `emitted'.
    { op = "LEI4"; rule = "stmt_lei4"; mnemonic = "ble"; }
    { op = "LTI4"; rule = "stmt_lti4"; mnemonic = "blt"; }
    { op = "GEI4"; rule = "stmt_gei4"; mnemonic = "bge"; }
    { op = "LEU4"; rule = "stmt_leu4"; mnemonic = "bleu"; }
    { op = "LTU4"; rule = "stmt_ltu4"; mnemonic = "bltu"; }
    { op = "GEU4"; rule = "stmt_geu4"; mnemonic = "bgeu"; }

    # --- task-054 ---------------------------------------------------------
    # The pointer rows. The two width-4 conversions are `mv' for the reason
    # CVUI4 and CVIU4 at width 4 are: a pointer and an unsigned int are the
    # same 32 bits here, so the whole instruction is the move. CNSTP4's row
    # names `li' and not the zero register: `reg_zerop' takes the null pointer
    # constant at cost 0 and its template is a fragment with no mnemonic to
    # name, so what this pins is the OTHER rule -- the one lcc's hexadecimal
    # spelling of every non-null pointer constant forces.
    #
    # SUBP4 and RETP4 both have executed witnesses in ir/ptr.c, so these two
    # rows are not the only thing standing behind them; they are here so that
    # the block reads as the family it is.
    { op = "SUBP4"; rule = "reg_subp"; mnemonic = "sub"; }
    { op = "CVPU4"; rule = "reg_cvpu4_4"; mnemonic = "mv"; }
    { op = "CVUP4"; rule = "reg_cvup4_4"; mnemonic = "mv"; }
    { op = "CNSTP4"; rule = "reg_cnstp_wide"; mnemonic = "li"; }
    { op = "RETP4"; rule = "stmt_retp"; mnemonic = "mv"; }
  ];

  # WHICH I-TYPED AND U-TYPED RULES MUST AGREE, AND WHICH MUST NOT (task-051).
  #
  # The U-typed block in rules.nix is mostly the I-typed block with a letter
  # changed, and that duplication is the right shape for a table of data --
  # `grep RSHU4 rules.nix' finds the row, and lburg's own machine descriptions
  # list ADDI4 and ADDU4 separately for the same reason. What the duplication
  # costs is that nothing stops the two drifting, in EITHER direction: an edit
  # that makes RSHU4 arithmetic and an edit that makes ADDU4 a subtract are
  # both one character, and both leave a table that still looks symmetrical.
  #
  # So the pairing is written down as data and checked against the templates.
  # `same' means the two rules must emit byte-identical text -- which is how
  # "MULU4 shares __mulsi3 with MULI4" stops being prose and becomes a checked
  # property. `different' means they must NOT, which is the whole of the
  # signed/unsigned distinction on this target: those five pairs are the ones
  # that compile, assemble, run and give the wrong answer on operands with bit
  # 31 set.
  #
  # NEGI4 has no partner because lcc has no NEGU4 (its ops.h gives NEG only
  # the I and F kinds), and that absence is stated here rather than left to be
  # noticed as a gap in the list.
  pairs = [
    { i = "reg_addi_imm"; u = "reg_addu_imm"; relation = "same"; }
    { i = "reg_addi_reg"; u = "reg_addu_reg"; relation = "same"; }
    { i = "reg_subi"; u = "reg_subu"; relation = "same"; }
    { i = "reg_lshi_imm"; u = "reg_lshu_imm"; relation = "same"; }
    { i = "reg_lshi_reg"; u = "reg_lshu_reg"; relation = "same"; }
    { i = "reg_bandi_imm"; u = "reg_bandu_imm"; relation = "same"; }
    { i = "reg_bandi_reg"; u = "reg_bandu_reg"; relation = "same"; }
    { i = "reg_bori_imm"; u = "reg_boru_imm"; relation = "same"; }
    { i = "reg_bori_reg"; u = "reg_boru_reg"; relation = "same"; }
    { i = "reg_bxori_imm"; u = "reg_bxoru_imm"; relation = "same"; }
    { i = "reg_bxori_reg"; u = "reg_bxoru_reg"; relation = "same"; }
    { i = "reg_bcomi"; u = "reg_bcomu"; relation = "same"; }
    { i = "reg_muli_libcall"; u = "reg_mulu_libcall"; relation = "same"; }
    { i = "stmt_reti"; u = "stmt_retu"; relation = "same"; }
    { i = "stmt_argi"; u = "stmt_argu"; relation = "same"; }
    { i = "reg_calli_direct"; u = "reg_callu_direct"; relation = "same"; }
    { i = "reg_calli_indirect"; u = "reg_callu_indirect"; relation = "same"; }
    { i = "stmt_calli_direct"; u = "stmt_callu_direct"; relation = "same"; }
    { i = "stmt_calli_indirect"; u = "stmt_callu_indirect"; relation = "same"; }
    { i = "stmt_eqi4"; u = "stmt_equ4"; relation = "same"; }
    { i = "stmt_nei4"; u = "stmt_neu4"; relation = "same"; }
    # And the five that must differ. Every one of them is a pair of RV32I
    # instructions that agree on every operand below 2^31.
    { i = "reg_rshi_imm"; u = "reg_rshu_imm"; relation = "different"; }
    { i = "reg_rshi_reg"; u = "reg_rshu_reg"; relation = "different"; }
    { i = "reg_divi_libcall"; u = "reg_divu_libcall"; relation = "different"; }
    { i = "reg_modi_libcall"; u = "reg_modu_libcall"; relation = "different"; }
    { i = "stmt_lei4"; u = "stmt_leu4"; relation = "different"; }
    { i = "stmt_lti4"; u = "stmt_ltu4"; relation = "different"; }
    { i = "stmt_gei4"; u = "stmt_geu4"; relation = "different"; }
    { i = "stmt_gti4"; u = "stmt_gtu4"; relation = "different"; }
  ];

  # RV32I has no M extension (decision-003). The oracle prints MUL/DIV inline
  # because it runs with mulops_calls=0 (decision-004), so the rule table is
  # where that difference has to be absorbed.
  libcalls = [
    { op = "MULI4"; rule = "reg_muli_libcall"; symbol = "__mulsi3"; }
    { op = "DIVI4"; rule = "reg_divi_libcall"; symbol = "__divsi3"; }
    { op = "MODI4"; rule = "reg_modi_libcall"; symbol = "__modsi3"; }
    # task-051. MULU4 shares __mulsi3 with MULI4 deliberately -- the low 32
    # bits of a product do not depend on how the operands are read -- and
    # DIVU4/MODU4 do NOT share the signed routines, because a quotient does.
    # That asymmetry is the whole content of these three rows.
    { op = "MULU4"; rule = "reg_mulu_libcall"; symbol = "__mulsi3"; }
    { op = "DIVU4"; rule = "reg_divu_libcall"; symbol = "__udivsi3"; }
    { op = "MODU4"; rule = "reg_modu_libcall"; symbol = "__umodsi3"; }
  ];


  # Mnemonics no rule may emit, because this target does not have them.
  forbiddenMnemonics = [ "mul " "mulh" "div " "divu" "rem " "remu" ];

  # --- the rules the corpus does NOT exercise (task-053) ------------------
  # `lowerings', `libcalls' and `pairs' above all name a rule and assert
  # something about ITS TEMPLATE. None of them asserts that the matcher ever
  # CHOOSES that rule, so a row nothing selects is pinned by a table that
  # describes it and by nothing else. task-051 shipped five U-typed rows in
  # exactly that state -- `reg_rshu_reg' among them, where `sra' for `srl' is
  # the defect that whole slice existed to prevent -- and two reviewers found
  # it after the fact.
  #
  # check.nix's census is the answer: it walks the corpus and works out, for
  # every rule in the table, the strongest thing that happens to it. A rule
  # that is not REDUCED has to appear here, with the status it does reach and
  # why that is acceptable; anything else is a named failure.
  #
  #   reduced    some of its template's text reached the emitted assembly --
  #              or, for a template with no text of its own, taking the row
  #              out of the table changes what the corpus compiles to. The
  #              only status that needs no entry here, and one a row here may
  #              NOT claim.
  #   labelled   it won a nonterminal at some node -- it was the cheapest way
  #              to produce that nonterminal there -- and the reduction never
  #              asked for it, so no text of its ever came out.
  #   unreached  it won a nonterminal nowhere. That is NOT the same as "no
  #              node it could match": most of the rows below are candidates
  #              at plenty of nodes and lose on cost at every one of them.
  #
  # WHAT STOPS THIS TABLE BECOMING A SILENCER, said carefully because the
  # first version of this comment claimed more than the code did and review
  # demonstrated the hole. Three things, and none of them is a length floor:
  #
  #   * a row whose rule is in a DIFFERENT state from the one declared fails,
  #     so a row cannot be added for a rule the corpus reduces;
  #   * `reduced' is not a status a row may declare, which was the one-line
  #     way round the previous point;
  #   * the census checks the arithmetic -- rules reduced plus rows declared
  #     must equal rules in the table -- which also catches a rule declared
  #     twice, where Nix's `listToAttrs' would otherwise keep the first row
  #     and ignore the second in silence.
  #
  # What none of that catches is the CORPUS shrinking and the rules it used to
  # reach being declared here instead. check.nix's `minReduced' floor is for
  # that, and it is the reason the floor exists rather than being derived.
  unexercisedRules = [
    # TWO OF THE THREE task-053 IS NAMED FOR. The third was `stmt_argp', a
    # pointer argument, and task-054's ir/ptr.c reaches it -- which is what
    # taking a row OUT of this table looks like.
    {
      rule = "reg_cnst_wide";
      status = "unreached";
      why = ''
        A signed constant too wide for the 12-bit immediate field. Every CNSTI4
        in the corpus is small enough for `con_cnst', which with the `reg: con'
        chain is cheaper, so this row never wins the `reg' nonterminal
        anywhere. Its unsigned twin `reg_cnstu_wide' IS reduced -- ir/unsig.c's
        data has bit 31 set -- so the template is the one thing about this row
        that has a witness. Reachable C; filed as task-055.
      '';
    }
    {
      rule = "stmt_callv_indirect";
      status = "unreached";
      why = ''
        A void call through a function pointer -- a candidate wherever CALLV
        appears, since `reg_from_acon' can produce its kid, and dearer than
        `stmt_callv_direct' at the one CALLV the corpus has. DELIBERATE, and
        the one entry
        here that must stay: run.sh's mutation "a call rule's emitted text
        stops looking like a call" is aimed at this row PRECISELY BECAUSE
        nothing else covers it, so that it demonstrates the derived
        callMarkers check rather than the emitted-assembly check. Put a void
        indirect call in the corpus and that mutation silently starts proving
        something else.
      '';
    }

    # THE FIVE THE CENSUS FOUND ON TOP OF THEM. All five WIN a nonterminal at
    # some node -- they are the cheapest way to produce it there -- and none of
    # them is ever expanded, because nothing ever asks for that nonterminal at
    # that node. That is the distinction a labelling-only census would have
    # missed, and it is why the two rows above are `unreached' and these are
    # not. Filed as task-056.
    {
      rule = "reg_addrfp";
      status = "labelled";
      why = ''
        Taking the ADDRESS of an incoming parameter. Every ADDRFP4 in the
        corpus is under a load or a store, where `addr_addrfp' folds it into
        the displacement for nothing, so the `reg' form is labelled at those
        same nodes and never asked for. Its local twin `reg_addrlp' IS
        reduced -- ir/lbuf.c takes the address of a local array.
      '';
    }
    {
      rule = "stmt_from_reg";
      status = "labelled";
      why = ''
        `stmt: reg', lcc's "evaluate it and drop it". THE ONE ROW HERE THE
        MARKER CANNOT SPEAK FOR: its template is empty, so expanding it emits
        nothing and no marker of its can reach the body. The census settles it
        by ablation instead, and the answer is not the charitable one -- with
        this row taken out of the table all fourteen corpus functions emit
        BYTE-IDENTICAL assembly, so nothing here needs it at all. Every
        discarded value in the corpus is a call, and task-025's
        `stmt_calli_direct'/`stmt_callu_direct' rows take those.
      '';
    }
    {
      rule = "addr_addi";
      status = "labelled";
      why = ''
        reg+const as an addressing mode, on the INTEGER add. lcc types address
        arithmetic as ADDP4, so every folded displacement in the corpus goes
        through `addr_addp'; the ADDI4 nodes that exist are arithmetic, this
        row wins `addr' at the ones whose kids fit it, and no load or store in
        the corpus ever asks for an `addr' there. cases.nix's duel on
        `addr_addp' is what proves the folding happens at all.
      '';
    }
    {
      rule = "reg_addp_imm";
      status = "labelled";
      why = ''
        Pointer + constant materialised into a register. Every one in the
        corpus is under a load or a store and folds into the displacement
        instead, at cost 0 against this row's 1. The register form
        `reg_addp_reg' IS reduced.
      '';
    }
    {
      rule = "reg_calli_indirect";
      status = "labelled";
      why = ''
        An int-returning call through a function pointer. `reg_calli_direct'
        is cheaper at every CALLI4 in the corpus, which is not an accident:
        cases.nix's duel on that pair RAISES the direct row's cost, watches
        this one take the node, and checks `jalr' appears in the body it then
        emits. So this row's template has a witness -- under a perturbed cost
        table, which is weaker than the corpus selecting it, and is why it is
        declared here rather than counted as reduced.
      '';
    }
  ];

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
      file = "expr"; forest = 2; node = "7"; nt = "reg"; rule = "reg_calli_direct"; cost = 5;
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
      # The same node, two nonterminals, two rules and two costs. This is the
      # whole of task-025: what lcc listed and nothing referenced reduces to
      # `stmt', and the `reg' rule is still there for a caller that wants the
      # value, one instruction dearer because it also moves a0.
      what = "a call whose result is discarded reduces to a statement, not a value";
      file = "voidcall"; forest = 1; node = "4"; nt = "stmt"; rule = "stmt_calli_direct"; cost = 4;
    }
    {
      # The margin the statement row wins by, and it is exactly the
      # instruction it does not emit -- `stmt: reg' over this same rule would
      # cost 5 and produce a value with nowhere to put it.
      what = "and the same node still produces a value, for one more instruction";
      file = "voidcall"; forest = 1; node = "4"; nt = "reg"; rule = "reg_calli_direct"; cost = 5;
    }
    {
      # Through a function pointer, which is the only way C reaches the
      # indirect row: the callee's address is loaded rather than named.
      what = "a discarded call through a function pointer is the indirect statement rule";
      file = "voidcall"; forest = 3; node = "6"; nt = "stmt"; rule = "stmt_calli_indirect"; cost = 8;
    }
    {
      what = "a void call was always a statement, and is priced as the call it is";
      file = "voidcall"; forest = 4; node = "1"; nt = "stmt"; rule = "stmt_callv_direct"; cost = 4;
    }
    {
      what = "pointer + constant field offset IS an addressing mode, and free";
      file = "field"; forest = 1; node = "5"; nt = "addr"; rule = "addr_addp"; cost = 1;
    }
    {
      what = "so p->y is one lw with the displacement folded in";
      file = "field"; forest = 1; node = "4"; nt = "reg"; rule = "reg_indiri"; cost = 2;
    }

    # --- the bitwise, shift and unary operators (task-051) -----------------
    # BOTH FORMS OF EVERY BINARY OPERATOR. The register row and the immediate
    # row are two rules, and the immediate one wins by exactly the `li' it
    # does not need -- which is why their costs differ by one and why both are
    # pinned here rather than one standing for the pair.
    {
      what = "a & b over two loaded values is the register form";
      file = "bits"; forest = 2; node = "3"; nt = "reg"; rule = "reg_bandi_reg"; cost = 3;
    }
    {
      what = "x & 255 is the immediate form, cheaper by the constant it does not materialise";
      file = "bits"; forest = 2; node = "16"; nt = "reg"; rule = "reg_bandi_imm"; cost = 2;
    }
    {
      what = "x | b is `or'";
      file = "bits"; forest = 2; node = "20"; nt = "reg"; rule = "reg_bori_reg"; cost = 3;
    }
    {
      what = "and x | 16 is `ori'";
      file = "bits"; forest = 2; node = "9"; nt = "reg"; rule = "reg_bori_imm"; cost = 2;
    }
    {
      what = "x ^ b is `xor'";
      file = "bits"; forest = 2; node = "13"; nt = "reg"; rule = "reg_bxori_reg"; cost = 3;
    }
    {
      what = "and x ^ 3 is `xori'";
      file = "bits"; forest = 2; node = "23"; nt = "reg"; rule = "reg_bxori_imm"; cost = 2;
    }
    {
      # The signed half of the pair ir/unsig.c pins the unsigned half of. Both
      # halves have to be SELECTED somewhere, or the claim that RSHI4 and
      # RSHU4 are different instructions rests on a table describing itself.
      what = "a signed right shift by a constant is srai";
      file = "bits"; forest = 2; node = "29"; nt = "reg"; rule = "reg_rshi_imm"; cost = 2;
    }
    {
      what = "and by a register, sra";
      file = "bits"; forest = 2; node = "38"; nt = "reg"; rule = "reg_rshi_reg"; cost = 4;
    }
    {
      what = "a left shift by a constant is slli, whatever the sign";
      file = "bits"; forest = 2; node = "34"; nt = "reg"; rule = "reg_lshi_imm"; cost = 2;
    }
    {
      what = "and by a register, sll";
      file = "bits"; forest = 2; node = "44"; nt = "reg"; rule = "reg_lshi_reg"; cost = 4;
    }
    {
      what = "~x has no RV32I instruction and is `xori' with all ones";
      file = "bits"; forest = 2; node = "47"; nt = "reg"; rule = "reg_bcomi"; cost = 2;
    }
    {
      what = "-x has none either, and is a subtract from the zero register";
      file = "bits"; forest = 2; node = "50"; nt = "reg"; rule = "reg_negi"; cost = 2;
    }
    {
      # The two signed comparisons no other corpus file reaches, and the two
      # whose unsigned twins ir/unsig.c pins below.
      what = "`x <= b' inverts into branch-if-greater, which is blt with its operands swapped";
      file = "bits"; forest = 2; node = "52"; nt = "stmt"; rule = "stmt_gti4"; cost = 3;
    }
    {
      what = "and `x == b' into bne";
      file = "bits"; forest = 5; node = "1"; nt = "stmt"; rule = "stmt_nei4"; cost = 3;
    }

    # --- the U-typed opcodes (task-051) ------------------------------------
    {
      what = "an unsigned divide is a call on __udivsi3, and is priced like the signed one";
      file = "unsig"; forest = 2; node = "3"; nt = "reg"; rule = "reg_divu_libcall"; cost = 12;
    }
    {
      what = "and an unsigned remainder a call on __umodsi3";
      file = "unsig"; forest = 2; node = "11"; nt = "reg"; rule = "reg_modu_libcall"; cost = 12;
    }
    {
      what = "an unsigned multiply shares __mulsi3 with the signed one";
      file = "unsig"; forest = 2; node = "32"; nt = "reg"; rule = "reg_mulu_libcall"; cost = 12;
    }
    {
      # The rows that distinguish this whole block from the I-typed one. A
      # shift is a shift; a LOGICAL shift is a different instruction, in both
      # the immediate and the register form.
      what = "an unsigned right shift by a constant is srli, where the signed one is srai";
      file = "unsig"; forest = 2; node = "15"; nt = "reg"; rule = "reg_rshu_imm"; cost = 2;
    }
    {
      what = "and by a register, srl, where the signed one is sra";
      file = "unsig"; forest = 2; node = "25"; nt = "reg"; rule = "reg_rshu_reg"; cost = 4;
    }
    {
      what = "a left shift has no signedness to get wrong, and is slli either way";
      file = "unsig"; forest = 2; node = "20"; nt = "reg"; rule = "reg_lshu_imm"; cost = 2;
    }
    {
      what = "nor in its register form";
      file = "unsig"; forest = 2; node = "30"; nt = "reg"; rule = "reg_lshu_reg"; cost = 4;
    }
    {
      what = "unsigned subtraction is the same `sub', because two's complement makes it so";
      file = "unsig"; forest = 2; node = "35"; nt = "reg"; rule = "reg_subu"; cost = 3;
    }
    {
      what = "unsigned & against a register";
      file = "unsig"; forest = 2; node = "38"; nt = "reg"; rule = "reg_bandu_reg"; cost = 3;
    }
    {
      what = "and against a constant that fits the immediate field";
      file = "unsig"; forest = 2; node = "52"; nt = "reg"; rule = "reg_bandu_imm"; cost = 2;
    }
    {
      what = "unsigned | against a register";
      file = "unsig"; forest = 2; node = "41"; nt = "reg"; rule = "reg_boru_reg"; cost = 3;
    }
    {
      what = "and against a constant";
      file = "unsig"; forest = 2; node = "56"; nt = "reg"; rule = "reg_boru_imm"; cost = 2;
    }
    {
      what = "unsigned ^ against a register";
      file = "unsig"; forest = 2; node = "44"; nt = "reg"; rule = "reg_bxoru_reg"; cost = 3;
    }
    {
      what = "and against a constant";
      file = "unsig"; forest = 2; node = "59"; nt = "reg"; rule = "reg_bxoru_imm"; cost = 2;
    }
    {
      what = "unsigned ~ is the same `xori' with all ones";
      file = "unsig"; forest = 2; node = "47"; nt = "reg"; rule = "reg_bcomu"; cost = 2;
    }
    {
      # lcc spells an unsigned constant as its UNSIGNED value, so this rule's
      # range starts at zero where the signed one starts at -2048.
      what = "a small unsigned constant is an immediate, at no cost of its own";
      file = "unsig"; forest = 2; node = "54"; nt = "con"; rule = "con_cnstu"; cost = 0;
    }
    {
      # lcc prints an unsigned constant in HEX once bit 15 is set, so `%a'
      # hands poc/04-assembler `0xdeadbeef' and its `parseInt' has to read it.
      # This is the only node in the corpus that takes that path.
      what = "an unsigned constant too wide for the immediate field is materialised with li";
      file = "unsig"; forest = 2; node = "66"; nt = "reg"; rule = "reg_cnstu_wide"; cost = 2;
    }
    {
      # Costs nothing because it emits nothing: x0 already reads as zero.
      what = "an unsigned zero is the zero register, not an instruction";
      file = "unsig"; forest = 2; node = "73"; nt = "reg"; rule = "reg_zerou"; cost = 0;
    }
    {
      what = "adding a small unsigned constant folds it into `addi'";
      file = "unsig"; forest = 3; node = "3"; nt = "reg"; rule = "reg_addu_imm"; cost = 2;
    }
    {
      what = "and adding two registers is `add', at the price of the libcalls under it";
      file = "unsig"; forest = 2; node = "9"; nt = "reg"; rule = "reg_addu_reg"; cost = 14;
    }
    {
      what = "`u > v' inverts into branch-if-less-or-equal-UNSIGNED, which is bleu and not ble";
      file = "unsig"; forest = 2; node = "74"; nt = "stmt"; rule = "stmt_leu4"; cost = 3;
    }
    {
      what = "and `u <= v' into the swapped bltu the greater-than rule is written as";
      file = "unsig"; forest = 5; node = "1"; nt = "stmt"; rule = "stmt_gtu4"; cost = 3;
    }
    {
      what = "`u < v' inverts into bgeu";
      file = "unsig"; forest = 8; node = "1"; nt = "stmt"; rule = "stmt_geu4"; cost = 3;
    }
    {
      what = "`u >= v' into bltu";
      file = "unsig"; forest = 11; node = "1"; nt = "stmt"; rule = "stmt_ltu4"; cost = 3;
    }
    {
      what = "`u == v' into bne, which equality gives no unsigned form to choose between";
      file = "unsig"; forest = 14; node = "1"; nt = "stmt"; rule = "stmt_neu4"; cost = 3;
    }
    {
      what = "and `u != v' into beq";
      file = "unsig"; forest = 17; node = "1"; nt = "stmt"; rule = "stmt_equ4"; cost = 3;
    }
    {
      what = "an unsigned argument is deposited in its argument register like any other word";
      file = "unsig"; forest = 23; node = "1"; nt = "stmt"; rule = "stmt_argu"; cost = 2;
    }
    {
      # ALL FOUR CALLU4 ROWS, in the four forests that reach them. task-025
      # built this split for CALLI4: a call whose result nothing wants reduces
      # to `stmt' and is one instruction cheaper for exactly the result move it
      # does not emit. The U-typed family needs all four rows for the same
      # reason, and a rule nothing selects is a rule nothing tests.
      what = "a discarded direct call reduces to a statement";
      file = "unsig"; forest = 23; node = "7"; nt = "stmt"; rule = "stmt_callu_direct"; cost = 4;
    }
    {
      what = "a discarded call through a function pointer is the indirect statement rule";
      file = "unsig"; forest = 24; node = "7"; nt = "stmt"; rule = "stmt_callu_indirect"; cost = 8;
    }
    {
      what = "and the same shape with its value used is the indirect value rule, one dearer";
      file = "unsig"; forest = 25; node = "7"; nt = "reg"; rule = "reg_callu_indirect"; cost = 9;
    }
    {
      what = "a direct call whose value is used moves a0, and costs one more than the statement form";
      file = "unsig"; forest = 26; node = "7"; nt = "reg"; rule = "reg_callu_direct"; cost = 5;
    }
    {
      what = "returning an unsigned moves to a0 and jumps to the epilogue, exactly as an int does";
      file = "unsig"; forest = 26; node = "9"; nt = "stmt"; rule = "stmt_retu"; cost = 6;
    }
    {
      # The two libcalls priced together: a quotient combined with a remainder
      # costs two of them plus the combining instruction, and this is the one
      # place in the corpus where that whole shape sits in a single node.
      what = "the quotient combined with the remainder is two libcalls and an xor, priced as such";
      file = "udiv"; forest = 0; node = "2"; nt = "reg"; rule = "reg_bxoru_reg"; cost = 25;
    }

    # --- the pointer rows (task-054) --------------------------------------
    # Each of the six rows task-054 added, named at the node the matcher picks
    # it for. `lowerings' above says what each one EMITS; these say the
    # matcher chooses it, which is the half a table describing a rule cannot
    # state -- and task-053's census is what makes a row nobody selects a
    # failure rather than a silence.
    {
      what = "the null pointer constant is the zero register, at no cost";
      file = "ptr"; forest = 1; node = "12"; nt = "reg"; rule = "reg_zerop"; cost = 0;
    }
    {
      what = "a non-null pointer constant, which lcc spells in hex, is materialised";
      file = "ptr"; forest = 10; node = "51"; nt = "reg"; rule = "reg_cnstp_wide"; cost = 2;
    }
    {
      what = "pointer minus INTEGER, which is a subtract and not a pointer difference";
      file = "ptr"; forest = 1; node = "6"; nt = "reg"; rule = "reg_subp"; cost = 3;
    }
    {
      what = "`p == 0' converts the pointer to an unsigned before comparing it";
      file = "ptr"; forest = 4; node = "2"; nt = "reg"; rule = "reg_cvpu4_4"; cost = 2;
    }
    {
      what = "an unsigned cast back to a pointer";
      file = "ptr"; forest = 10; node = "13"; nt = "reg"; rule = "reg_cvup4_4"; cost = 3;
    }
    {
      what = "a POINTER argument, which had a row since task-025 and no case that selected it";
      file = "ptr"; forest = 10; node = "40"; nt = "stmt"; rule = "stmt_argp"; cost = 2;
    }
    {
      what = "returning a pointer moves to a0 and jumps to the epilogue, exactly as returning an int does";
      file = "ptr"; forest = 10; node = "62"; nt = "stmt"; rule = "stmt_retp"; cost = 5;
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
    {
      # The immediate/register split the whole bitwise block is built on. Both
      # rules match `x & 255'; the immediate one wins by the `li' it does not
      # need, and raising it by two hands the node to the register form with
      # the constant materialised beside it.
      what = "a mask that fits the immediate field folds in, or the constant is materialised first";
      file = "bits"; forest = 2; node = "16"; nt = "reg";
      winner = "reg_bandi_imm"; loser = "reg_bandi_reg"; penalty = 2;
      winnerAsm = "andi s2,s2,255"; loserAsm = "and s2,s2,s3";
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
    {
      file = "voidcall";
      present = [ "call put" "call done" "jalr s1" "mv a0,s1" "addi s1,s1,2" ];
      absent = [ "%" ];
      # 19, and the count is what guards the SHAPE here: `present' is
      # membership, so it cannot see that put() is called twice, and a rule
      # that grew a result move would emit it with no %c to refuse over.
      instructions = 19;
      follows = [ ];
    }
    {
      file = "bits";
      # One line per rule this file exists to select: the register form and
      # the immediate form of each of the three bitwise operators, both forms
      # of both shifts, the two RV32I has no instruction for, and the two
      # comparisons no other corpus file reaches.
      present = [
        "and s2,s11,s10"
        "ori s2,s2,16"
        "xor s2,s2,s10"
        "andi s2,s2,255"
        "or s2,s2,s10"
        "xori s2,s2,3"
        "srai s3,s11,2"
        "slli s3,s10,3"
        "sra s3,s11,s4"
        "sll s3,s10,s4"
        "xori s2,s2,-1"
        "sub s2,zero,s2"
        "blt s10,s1,.Lmask_2"
        "bne s1,s2,.Lmask_4"
      ];
      # `srl' as a substring catches BOTH logical-for-arithmetic substitutions
      # at once -- `srai'->`srli' and `sra'->`srl' -- and nothing in this file
      # may shift logically, because every right shift here is signed.
      #
      # `not' and `neg' ARE implemented by poc/04-assembler, so a rule reaching
      # for them would assemble, run and give the right answer. `lowerings'
      # above catches that for reg_bcomi and reg_negi and fires first; these
      # two entries are the cheaper second line, and they also cover a rule
      # with no `lowerings' row of its own reaching for the same shortcut.
      #
      # `li s3,255' is the other half of the duel below: the mask folded into
      # the immediate field, so nothing materialised it.
      absent = [ "%" "srl" "not " "neg " "li s3,255" ];
      instructions = 61;
      follows = [ ];
    }
    {
      file = "unsig";
      present = [
        "call __udivsi3"
        "call __umodsi3"
        "call __mulsi3"
        # Both forms of both shifts. `srli'/`srl' are the rows that make this
        # file a different program from ir/bits.c rather than the same one on
        # differently-declared variables.
        "srli s3,s11,3"
        "slli s3,s11,1"
        "srl s3,s11,s8"
        "sll s3,s11,s8"
        "sub s2,s2,s10"
        # Both forms of all three bitwise operators.
        "and s2,s2,s11"
        "andi s2,s2,3"
        "or s2,s2,s10"
        "ori s2,s2,3"
        "xor s2,s2,s10"
        "xori s2,s2,5"
        "xori s2,s2,-1"
        # An unsigned constant too wide for the immediate field, in lcc's own
        # hexadecimal spelling, which poc/04-assembler's parseInt has to read.
        "li s4,0xdeadbeef"
        # And an unsigned zero, which is the zero register and no instruction.
        "sw zero,-64(s0)"
        "bne s1,zero,.Lwide_14"
        # The four ordering branches, each with its operands in the order its
        # rule puts them. `bltu s2,s1' and `bltu s1,s2' are the same mnemonic
        # and different comparisons -- GTU4 swaps and LTU4 does not -- so the
        # operand order is the assertion, and `lowerings' above cannot make it.
        "bleu s11,s10,.Lwide_2"
        "bltu s2,s1,.Lwide_4"
        "bgeu s1,s2,.Lwide_6"
        "bltu s1,s2,.Lwide_8"
        "bne s1,s2,.Lwide_10"
        "beq s1,s2,.Lwide_12"
        # A direct call and an indirect one, and the result move the value
        # forms make and the statement forms do not.
        "call uh"
        "jalr s1"
        "mv s11,a0"
      ];
      # Every signed instruction that would compile, assemble and run here, and
      # answer differently only because the data has bit 31 set. This is the
      # list a table with the U-typed rules missing -- or pointed at the
      # I-typed lowerings -- would trip. `sra' as a substring covers `srai'
      # too, which is why there is no separate entry for it.
      absent = [
        "%"
        "sra"
        "call __divsi3"
        "call __modsi3"
        "blt "
        "bge "
        "ble "
      ];
      instructions = 144;
      follows = [ ];
    }
    {
      file = "udiv";
      # `present' is MEMBERSHIP over whole lines, so these four lines say the
      # two libcalls are reached with the argument registers set up, and NOT
      # that each call sets up its own -- both rules emit the same two `mv'
      # lines, so one occurrence satisfies both entries. What catches a second
      # call left reading the first call's registers is the instruction count
      # below and the executed answer. Said plainly because the first version
      # of this comment claimed the stronger property.
      present = [
        "mv a0,s11"
        "mv a1,s10"
        "call __udivsi3"
        "call __umodsi3"
        "xor s1,s1,s2"
      ];
      absent = [ "%" "call __divsi3" "call __modsi3" ];
      instructions = 13;
      follows = [ ];
    }
    {
      file = "ptr";
      # One line per pointer rule that HAS a mnemonic, plus the two halves of
      # the return. `sw zero,' is reg_zerop: the null pointer constant reaches
      # the store as the zero register rather than as an instruction, which is
      # the one thing `lowerings' cannot say about it.
      #
      # `li s2,0x186a0' is lcc's HEXADECIMAL spelling of a non-null pointer
      # constant surviving all the way to poc/04-assembler, which reads it and
      # expands it to lui+addi. Nothing else in this corpus takes that path
      # for a pointer.
      present = [
        "sw zero,-72(s0)"
        "sub s2,s2,s11"
        "li s2,0x186a0"
        "mv a0,s9"
        "mv a0,s1"
        "j .Lwalk_epilogue"
      ];
      absent = [ "%" ];
      # The count is the shape guard `present' cannot be: membership cannot
      # see a rule that started emitting an extra move, and this file is full
      # of width-4 conversions whose whole content is one.
      instructions = 86;
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
      file = "lbuf";
      expect = 293;
      # The weights are what make the displacement observable. With every
      # constant index collapsed onto the base -- which is what dropping the
      # `+N' does -- both stores land on buf[0] and the return is 7 * 15 = 105
      # rather than 293. Measured, not reasoned: the mutation in run.sh that
      # drops the displacement exits 105.
      why = "pack(1): buf[i] = i+1, then buf[3]=100 and buf[5]=7, so 1 + 100*2 + 7*4 + 8*8 = 293";
    }
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
    {
      file = "voidcall";
      expect = 70;
      # The exit status is what put() ACCUMULATED, not what emit() returned:
      # emit() throws every result away, so the side effects are the only
      # evidence the calls happened.
      #
      # acc starts at 7, which is what makes the case discriminate. With 0,
      # put(n) would return exactly n and a compiler that used the discarded
      # result where the argument belongs would get the right answer by luck;
      # with 7 it computes 7+20=27, then 27+28=55, then 55+57=112. Dropping
      # either put() gives 48 or 49, and dropping the indirect call gives 48.
      why = "emit(20): acc 7 + 20 = 27, + 21 = 48, then hook(22) through the pointer = 70";
    }
    {
      file = "bits";
      expect = 73501;
      # `a' is negative, so the right shifts run over a value with bit 31 set
      # and `sra' and `srl' give different answers here.
      #
      # THE CHAIN BELOW WAS COMPUTED, NOT WRITTEN OUT. The first version of
      # this string was a step-by-step derivation for an earlier choice of
      # arguments; every intermediate in it was wrong and its final value
      # contradicted the `expect' three lines above, which nothing checks and
      # two reviews caught. Only the steps that DISCRIMINATE a rule are named
      # now -- the rest is what the host compiler and the emulator agree on.
      why = "mask(-1234,5678): the bitwise chain reaches 5693, then + (a>>2) = -309 arithmetic (srl would give 1073741515), + (b<<3) = 45424, + (a>>6) = -20, + (b<<2) = 22712, giving 73500; ~ then - leaves 73501, and neither trailing comparison fires";
    }
    {
      file = "unsig";
      expect = 3123634320;
      # Not a number anybody chose: the arguments were chosen (see
      # ir/unsig.c's header) so that each of the seven signed-for-unsigned
      # substitutions moves this answer, and then the host compiler and the
      # emulator were asked what it is. Both say 3123634320.
      #
      # They did not always: this note read 3758096711 until task-054, which
      # contradicted the `expect' three lines above it and was checked by
      # nothing -- a prose number beside a measured one, which is the kind
      # this file keeps having to correct.
      why = "wide(0xfffffff0,9): unsigned division, remainder, both logical shifts and four unsigned branches over a dividend whose top bit is set -- every one of which the signed rule answers differently -- plus a wide hexadecimal constant, an unsigned zero and all four CALLU4 rows";
    }
    {
      file = "udiv";
      expect = 2147483644;
      # The one number in this table that is about runtime.s rather than about
      # rules.nix. Every rule here is already covered by ir/unsig.c; what is
      # not covered there is the comparison INSIDE __udivsi3 and __umodsi3,
      # which only a divisor above 2^31 can reach.
      why = "wrap(0xfffffffe,0x80000001) = 1 ^ 0x7ffffffd = 0x7ffffffc; a signed compare inside the routines subtracts at every iteration instead of none, giving 0xffffffff ^ 0x7fffffff = 0x80000000 -- see ir/udiv.c for why the operator is `^' and not `+'";
    }
    {
      file = "ptr";
      expect = 103398;
      # TWO INDEPENDENT ANSWERS ADDED, which is what stops one defect
      # cancelling another: `hold' is the whole integer computation and the
      # returned pointer carries only `n + 4', so the arithmetic cannot move
      # the byte and the return cannot move `hold'.
      #
      # The three null tests DISAGREE -- z == 0 is true, p == 0 is false,
      # q != 0 is true -- and they add 1000, 2000 and 300. A null comparison
      # that is always false discriminates nothing, which is the pointer
      # version of the mistake ir/unsig.c's divisor of 7 was; so is a pointer
      # difference of zero, and `p - q' here is 2.
      why = "walk(2): 2 + 1000 (z == 0) + 300 (q != 0) + 2 (p - q) + 2 (*q, i.e. tag[1]) + 22 (take(q,2) = tag[1]*10 + 2) + 2006 (the CVUP4 pointer, 1003, read back as an int TWICE) + 100000 (a non-null pointer constant), so hold = 103334; the returned tag+2+4 points at 64";
    }
  ];
}
