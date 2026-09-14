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
# burg.nix interprets it.
#
# MULI4/DIVI4/MODI4 are NOT instructions here. RV32I has no M extension
# (decision-003), so they are libcalls into __mulsi3/__divsi3/__modsi3. The
# oracle prints them inline because it runs with mulops_calls=0 (decision-004);
# a rule table is exactly the right place to absorb that difference, and doing
# it here rather than by rewriting the DAG is itself evidence for the approach.
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
    { id = "stmt_asgni"; nt = "stmt"; op = "ASGNI4"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sw %1,%0\n"; }
    { id = "stmt_asgnp"; nt = "stmt"; op = "ASGNP4"; kids = [ "addr" "reg" ]; cost = 1; tmpl = "sw %1,%0\n"; }

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

    # --- calls ------------------------------------------------------------
    # A call to a known symbol beats materialising its address and jalr-ing
    # through it: 4 against 2 + 5. Cost, not rule order, decides that.
    { id = "reg_calli_direct"; nt = "reg"; op = "CALLI4"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\nmv %c,a0\n"; }
    { id = "reg_calli_indirect"; nt = "reg"; op = "CALLI4"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\nmv %c,a0\n"; }
    { id = "stmt_callv_direct"; nt = "stmt"; op = "CALLV"; kids = [ "acon" ]; cost = callCost; tmpl = "call %0\n"; }
    { id = "stmt_callv_indirect"; nt = "stmt"; op = "CALLV"; kids = [ "reg" ]; cost = callCost + 1; tmpl = "jalr %0\n"; }
    { id = "stmt_argi"; nt = "stmt"; op = "ARGI4"; kids = [ "reg" ]; cost = 1; tmpl = "mv %A,%0\n"; }
    { id = "stmt_argp"; nt = "stmt"; op = "ARGP4"; kids = [ "reg" ]; cost = 1; tmpl = "mv %A,%0\n"; }

    # --- control flow -----------------------------------------------------
    { id = "stmt_reti"; nt = "stmt"; op = "RETI4"; kids = [ "reg" ]; cost = 1; tmpl = "mv a0,%0\nj %E\n"; }
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
  ];
}
