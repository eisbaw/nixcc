# IR opcodes: lcc/src/ops.h, lcc/src/c.h's op macros and tree.c's opname().
#
# lcc packs an opcode into one integer -- `opindex<<4 | optype', with the
# operand size shifted up by ten -- so that its switch statements can test
# `op == ADD+I' and its masks can strip a field. Here the fields stay a record,
# because every reader wants the fields and nothing here needs a C switch.
#
# THE ONE TRAP WORTH THE COMMENT: `mkop(op,ty)' is `specific(op + ttob(ty))',
# and `specific' MASKS THE SIZE OFF. So a TREE's op carries a kind letter and
# no width, and the width is added later, in dag.c's listnodes, from the tree's
# own type. Give a tree op a size here and every conversion node comes out with
# the wrong one.
let
  b = builtins;
in
self:
let
  ty = self.types;
in
rec {
  # A tree op: generic name plus lcc's type letter ("" for the tree-only ops
  # AND/NOT/OR/COND/RIGHT/FIELD, which have optype 0).
  mk = gen: kind: { inherit gen kind; };
  bare = gen: { inherit gen; kind = ""; };

  # mkop(op, ty)
  mkop = gen: t: mk gen (ty.ttob t).kind;

  # A dag node op: a tree op plus the width from the tree's type, which is
  # listnodes' `tp->op + sizeop(tp->type->size)'.
  sized = op: size: { inherit (op) gen kind; inherit size; };

  isaddrop = op:
    (op.gen == "ADDRG" || op.gen == "ADDRL" || op.gen == "ADDRF") && op.kind == "P";

  # tree.c's opname(). The suffix letters are lcc's, indexed by optype; the
  # width is printed only when non-zero, which is why a tree op renders without
  # one and a node op with.
  opname = op:
    if op.kind == "" then op.gen
    else op.gen + op.kind + (if (op.size or 0) > 0 then toString op.size else "");

  # The opcodes this slice knows how to emit. Anything else is a hole in the
  # port rather than a valid opcode we happen not to use, so name it.
  known = [
    "CNST" "ARG" "ASGN" "INDIR" "CVF" "CVI" "CVP" "CVU" "NEG" "CALL" "RET"
    "ADDRG" "ADDRF" "ADDRL" "ADD" "SUB" "LSH" "MOD" "RSH" "BAND" "BCOM" "BOR"
    "BXOR" "DIV" "MUL" "EQ" "GE" "GT" "LE" "LT" "NE" "JUMP" "LABEL"
    "AND" "NOT" "OR" "COND" "RIGHT" "FIELD"
  ];

  check = op:
    if b.elem op.gen known then op
    else throw "ops: `${op.gen}' is not an opcode this frontend knows";
}
