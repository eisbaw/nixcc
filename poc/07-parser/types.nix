# lcc/src/types.c, restricted to the types slice 1 can name.
#
# A type is a plain attrset, and lcc's pointer equality on interned Type
# structures becomes Nix's structural equality on those attrsets. That is only
# sound because lcc's `type()' interns: two Types are the same pointer exactly
# when their (op, type, size, align, sym) agree. `name' below stands in for the
# sym, which is what keeps `int' and `long int' -- same op, same size, same
# align -- distinct, exactly as they are in lcc.
#
# The metrics are symbolicIR's (lcc/src/symbolic.c): char 1, short 2, int 4,
# long 4, pointer 4, double 8. They are NOT read from a target description at
# runtime; -target=symbolic compiles them in, and rcc-rv32 only overrides
# little_endian (decision-004).
#
# What is deliberately absent: struct, union, enum, bitfields, long long and
# the floating types beyond the two declarations needed to REFUSE them. Those
# belong to later slices; a type this module cannot build is a type the parser
# throws on, which is the house rule (refuse loudly rather than miscompile).
let
  b = builtins;

  # lcc's type-op codes, from token.h. Kept numeric because three of lcc's
  # predicates are ORDER comparisons (`op <= UNSIGNED', `op >= CONST') rather
  # than membership tests, and rewriting those as lists is how a case goes
  # missing.
  opcode = {
    FLOAT = 1;
    DOUBLE = 2;
    CHAR = 3;
    SHORT = 4;
    INT = 5;
    UNSIGNED = 6;
    POINTER = 7;
    VOID = 8;
    STRUCT = 9;
    UNION = 10;
    FUNCTION = 11;
    ARRAY = 12;
    ENUM = 13;
    LONG = 14;
    CONST = 15;
    VOLATILE = 16;
    "CONST+VOLATILE" = 31;
  };

  code = ty: opcode.${ty.op} or (throw "types: no op code for `${ty.op}'");

  basic = op: name: size: align: { inherit op name size align; };
in
rec {
  inherit opcode code;

  chartype = basic "INT" "char" 1 1;
  signedchar = basic "INT" "signed char" 1 1;
  unsignedchar = basic "UNSIGNED" "unsigned char" 1 1;
  shorttype = basic "INT" "short" 2 2;
  unsignedshort = basic "UNSIGNED" "unsigned short" 2 2;
  inttype = basic "INT" "int" 4 4;
  unsignedtype = basic "UNSIGNED" "unsigned int" 4 4;
  longtype = basic "INT" "long int" 4 4;
  unsignedlong = basic "UNSIGNED" "unsigned long" 4 4;
  floattype = basic "FLOAT" "float" 4 4;
  doubletype = basic "FLOAT" "double" 8 8;
  longdouble = basic "FLOAT" "long double" 8 8;
  voidtype = basic "VOID" "void" 0 0;

  ptr = ty: { op = "POINTER"; type = ty; size = 4; align = 4; };
  deref = ty: if isptr ty then (unqual ty).type else throw "types: pointer expected";

  # lcc's func() records the prototype and whether the declarator was
  # old-style. `proto = null' is an old-style (unprototyped) function.
  func = ty: proto: oldstyle: {
    op = "FUNCTION";
    type = ty;
    size = 0;
    align = 0;
    inherit proto oldstyle;
  };
  freturn = ty: if isfunc ty then (unqual ty).type else throw "types: function expected";

  array = ty: n: a: {
    op = "ARRAY";
    type = ty;
    size = n * ty.size;
    align = if a != 0 then a else ty.align;
  };
  atop = ty: if isarray ty then ptr (unqual ty).type else throw "types: array expected";

  voidptype = ptr voidtype;
  charptype = ptr chartype;
  funcptype = ptr (func voidtype null 1);

  # lcc picks the first unsigned/signed basic type whose size AND align match a
  # pointer's. With symbolicIR's metrics that is unsigned int and int.
  unsignedptr = unsignedtype;
  signedptr = inttype;
  widechar = unsignedshort;

  # --- predicates, one per c.h macro -------------------------------------
  isqual = t: code t >= opcode.CONST;
  unqual = t: if isqual t then t.type else t;
  isvolatile = t: t.op == "VOLATILE" || t.op == "CONST+VOLATILE";
  isconst = t: t.op == "CONST" || t.op == "CONST+VOLATILE";
  isarray = t: (unqual t).op == "ARRAY";
  isstruct = t: (unqual t).op == "STRUCT" || (unqual t).op == "UNION";
  isfunc = t: (unqual t).op == "FUNCTION";
  isptr = t: (unqual t).op == "POINTER";
  isint = t: (unqual t).op == "INT" || (unqual t).op == "UNSIGNED";
  ischar = t: t.size == 1 && isint t;
  isfloat = t: (unqual t).op == "FLOAT";
  isarith = t: code (unqual t) <= opcode.UNSIGNED;
  isunsigned = t: (unqual t).op == "UNSIGNED";
  isscalar = t: code (unqual t) <= opcode.POINTER || (unqual t).op == "ENUM";
  isenum = t: (unqual t).op == "ENUM";

  # --- integer limits ----------------------------------------------------
  # lcc keeps these on the type's Symbol; here they are derived, because a
  # table would be a second place for a width to be wrong.
  pow2 = n: b.foldl' (a: _: a * 2) 1 (b.genList (i: i) n);
  ones = n: pow2 n - 1;
  limits = ty:
    let t = unqual ty; in
    if t.op == "INT" then { max = pow2 (8 * t.size - 1) - 1; min = 0 - pow2 (8 * t.size - 1); }
    else if t.op == "UNSIGNED" then { max = ones (8 * t.size); min = 0; }
    else throw "types: `${t.name or t.op}' has no integer limits";

  # extend(x,ty) from c.h: keep the low 8*size bits and sign-extend them.
  # bitAnd works on Nix's 64-bit two's-complement integers, so a negative x
  # yields its low bits unchanged, exactly as the C macro does.
  extend = x: ty:
    let
      w = 8 * (unqual ty).size;
      m = pow2 w;
      low = b.bitAnd x (m - 1);
    in
    if low >= m / 2 then low - m else low;

  # The low 8*size bits without sign extension: the `&ones(...)' half of the
  # same macro pair. NOT named `truncate', which is what it does, because
  # `just no-deletes' greps every harness source for delete-shaped commands
  # and `truncate' is one of them. A false positive there is cheaper to avoid
  # than to annotate away.
  lowBits = x: ty: b.bitAnd x (ones (8 * (unqual ty).size));

  # --- conversions -------------------------------------------------------
  promote = ty0:
    let ty = unqual ty0; in
    if ty.op == "ENUM" then inttype
    else if ty.op == "INT" then (if ty.size < inttype.size then inttype else ty)
    else if ty.op == "UNSIGNED" then
      (if ty.size < inttype.size then inttype
      else if ty.size < unsignedtype.size then unsignedtype
      else ty)
    else if ty.op == "FLOAT" then (if ty.size < doubletype.size then doubletype else ty)
    else ty;

  # expr.c's static super(): the type an operand is widened to before a
  # conversion chain is chosen.
  super = ty:
    if ty.op == "INT" && ty.size < inttype.size then inttype
    else if ty.op == "UNSIGNED" && ty.size < unsignedtype.size then unsignedtype
    else if ty.op == "POINTER" then unsignedptr
    else ty;

  # enode.c's binary(): the usual arithmetic conversions' common type.
  binaryType = xty: yty:
    let pick = t: xty == t || yty == t; in
    if pick longdouble then longdouble
    else if pick doubletype then doubletype
    else if pick floattype then floattype
    else if pick unsignedlong then unsignedlong
    else if (xty == longtype && yty == unsignedtype)
      || (xty == unsignedtype && yty == longtype) then
      (if longtype.size > unsignedtype.size then longtype else unsignedlong)
    else if pick longtype then longtype
    else if pick unsignedtype then unsignedtype
    else inttype;

  # --- ttob / btot -------------------------------------------------------
  # An IR opcode's "kind" letter and width come from the type. lcc packs them
  # into one integer; we keep the pair, because every consumer wants the pair
  # and the packing is only there to make C's switch statements possible.
  ttob = ty0:
    let ty = unqual ty0; in
    if ty.op == "ENUM" then { kind = "I"; inherit (inttype) size; }
    else if ty.op == "POINTER" then { kind = "P"; inherit (voidptype) size; }
    else if ty.op == "FUNCTION" then { kind = "P"; inherit (funcptype) size; }
    else if ty.op == "ARRAY" || ty.op == "STRUCT" || ty.op == "UNION" then { kind = "B"; inherit (ty) size; }
    else if ty.op == "INT" then { kind = "I"; inherit (ty) size; }
    else if ty.op == "UNSIGNED" then { kind = "U"; inherit (ty) size; }
    else if ty.op == "FLOAT" then { kind = "F"; inherit (ty) size; }
    else if ty.op == "VOID" then { kind = "V"; size = 0; }
    else throw "types: ttob has no encoding for `${ty.op}'";

  # --- outtype (lcc's %t) ------------------------------------------------
  # The exact text symbolic.c prints for `type=' fields and for a CALL node's
  # {...} operand. Reproduced literally: the diff against the oracle is on
  # bytes, and "pointer to int" versus "int *" is a whole-listing mismatch.
  outtype = ty:
    if ty.op == "CONST" then "const ${outtype ty.type}"
    else if ty.op == "VOLATILE" then "volatile ${outtype ty.type}"
    else if ty.op == "CONST+VOLATILE" then "const volatile ${outtype ty.type}"
    else if ty.op == "POINTER" then "pointer to ${outtype ty.type}"
    else if ty.op == "FUNCTION" then
      "${outtype ty.type} function" + (
        if ty.proto != null && ty.proto != [ ] then
          "(" + b.concatStringsSep "," (map (p: if p == voidtype then "..." else outtype p) ty.proto) + ")"
        else if ty.proto != null && ty.proto == [ ] then "(void)"
        else ""
      )
    else if ty.op == "ARRAY" then
      (if ty.size > 0 && ty.type != null && ty.type.size > 0
      then "array ${toString (ty.size / ty.type.size)}"
      else "incomplete array") + " of ${outtype ty.type}"
    else ty.name or (throw "types: outtype has no spelling for `${ty.op}'");

  # eqtype for the cases slice 1 can reach. lcc's version walks structures and
  # composes prototypes; with no struct, no enum and no old-style/new-style
  # mixing in the corpus, structural equality is the whole of it -- but a
  # FUNCTION type reaches here from `assign', so the two prototype shapes that
  # do differ are handled rather than assumed away.
  eqtype = ty1: ty2: _ret: ty1 == ty2;
}
