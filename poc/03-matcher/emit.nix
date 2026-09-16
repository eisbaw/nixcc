# The RV32 half of the PoC: frame layout, the naming conventions the rule
# templates refer to through %a/%A/%E, and the prologue/epilogue that wrap the
# body burg.nix selects.
#
# Everything here is target knowledge; everything in burg.nix is not. The split
# is the same one lcc draws between gen.c and a .md file, and it is what the
# "rules are data" claim rests on: no instruction is chosen in this file.
#
# What this file is NOT: a register allocator or an ABI. Registers are assigned
# by expression depth (see burg.nix) and every s-register the body touches is
# saved, which is correct but wasteful. lcc allocates registers in a separate
# pass and so will we -- filed as task-016.
# Callee-saved registers, so that a libcall or a CALL inside a statement
# cannot destroy a partially-evaluated expression. Evaluation depth grows from
# the bottom of `depthRegs`, common subexpressions from the bottom of
# `cseRegs`, and the two lists are disjoint. Both are arguments so that
# must-fail.nix can shrink them and prove exhaustion is refused rather than
# silently wrapped around.
{
  table ? import ./rules.nix,
  depthRegs ? [ "s1" "s2" "s3" "s4" "s5" "s6" ],
  cseRegs ? [ "s11" "s10" "s9" "s8" "s7" ],
}:
let
  b = builtins;

  savedRegs = depthRegs ++ cseRegs;
  overlap = b.filter (r: b.elem r cseRegs) depthRegs;

  wordSize = 4;
  # `addi sp,sp,-frame` has a 12-bit signed immediate. A larger frame needs a
  # scratch register and a different prologue (task-019).
  maxFrame = 2032;

  isLabelName = s: b.match "[0-9]+" s != null;

  # A symbol operand may carry a DISPLACEMENT. lcc folds `msg[8]' into ONE node
  # over a generated symbol whose NAME is the addressing expression -- `msg+8',
  # `buf-4' -- and nothing in the rule table splits it, so it is split here:
  # the base may have to be renamed and the displacement has to survive that.
  #
  # Reading the whole thing as a name was the defect task-032 filed. It is
  # loud rather than silent -- poc/04-assembler refuses an undefined symbol --
  # but it is the spelling EVERY constant subscript produces.
  splitDisp = s:
    let m = b.match "([A-Za-z_.$0-9]+)([+-])([0-9]+)" s; in
    if m == null then { base = s; disp = 0; }
    else {
      base = b.head m;
      disp = (if b.elemAt m 1 == "-" then 0 - 1 else 1) * b.fromJSON (b.elemAt m 2);
    };

  withDisp = name: disp:
    if disp == 0 then name
    else name + (if disp > 0 then "+" else "") + toString disp;

  # lcc's generated symbols are numbered from ONE file-wide counter, so a
  # number names either a branch label inside a function or a file-scope
  # static -- a string literal's home in the lit segment -- and never both.
  # They need different names in assembly: a branch label is local to the
  # function it is in and is already mangled with the function's name, while a
  # literal is laid down once and may be referenced from any function in the
  # translation unit. Neither may keep the bare number: poc/04-assembler reads
  # `2:' as a GAS POSITIONAL label, the kind `1f'/`1b' refer to, and renames it
  # out from under any `la' that names it.
  litLabel = n: ".Llit_${n}";

  indexOf = x: xs:
    let hit = b.filter (i: b.elemAt xs i == x) (b.genList (i: i) (b.length xs)); in
    if hit == [ ] then throw "emit: ${x} is not one of this target's saved registers" else b.head hit;

  labelOf = fn: n: ".L${fn}_${n}";
  epilogueOf = fn: ".L${fn}_epilogue";

  # The branch labels this function DEFINES, which is what tells one kind of
  # numeric symbol from the other above. Taken from the listing rather than
  # guessed: parse.nix already tags every label in the emit order.
  labelsIn = fn: b.listToAttrs (map (e: { inherit (e) name; value = true; })
    (b.filter (e: e.kind == "label")
      (b.concatLists (map (f: f.emitOrder) fn.forests))));

  argReg = i:
    if i < 8 then "a${toString i}"
    else throw "emit: argument ${toString i} does not fit the 8 argument registers, and this PoC has no outgoing argument area (task-018)";

  constValue = node:
    if b.match "CNST[A-Z][0-9]" node.op == null then null
    else if node.syms == [ ] then throw "emit: ${node.op} with no value"
    else
      let m = b.match "(-?[0-9]+)" (b.head node.syms); in
      if m == null then null else b.fromJSON (b.head m);

  # --- frame ---------------------------------------------------------------
  # From s0 (the frame pointer, pointing one past the top of the frame) down:
  #
  #     s0-4    return address
  #     s0-8    caller's s0
  #     s0-12.. one slot per callee-saved register this target has
  #     ...     incoming parameters, at lcc's own offsets
  #     ...     locals, at lcc's own offsets
  #
  # lcc hands out parameter and local offsets counting up from zero in two
  # separate spaces, so each area is placed as a block and lcc's offset is
  # added inside it.
  #
  # The saved-register area is a FIXED slot per register rather than one slot
  # per register the body happens to use. That costs up to eleven words of
  # stack and buys something worth more than they are: the layout no longer
  # depends on the reduction, so the reduction no longer has to be run once to
  # size the frame and again to emit against it. The earlier two-pass version
  # also had an unasserted fixpoint in it -- a rule predicate that looked at a
  # frame displacement would have made the two passes disagree, and nothing
  # would have noticed. The prologue still saves only what the body used; only
  # the ADDRESSES are fixed.
  frameOf = fn:
    let
      savedBytes = wordSize * (2 + b.length savedRegs);
      paramEnd = b.foldl' (a: p: let e = p.offset + wordSize; in if e > a then e else a) 0 fn.params;
      localEnd = fn.maxoff;
      paramBase = -(savedBytes + paramEnd);
      localBase = paramBase - localEnd;
      raw = savedBytes + paramEnd + localEnd;
      size = ((raw + 15) / 16) * 16;
      # Compared against the WHOLE type, not its first word: lcc prints
      # `type=long long int', and matching on `long' alone let an eight-byte
      # parameter through this guard into a four-byte slot.
      fourByte = t:
        b.match "pointer to .*" t != null
        || b.elem t [ "int" "unsigned int" "unsigned" "long int" "unsigned long int" "long" ];
      # Parameters only. A local of any size is laid out correctly whatever its
      # type, because lcc has already sized the whole local area and handed it
      # over as `maxoff'; the parameter area is the one this file sizes itself,
      # four bytes per lcc offset, and that is the assumption that can be wrong.
      wide = b.filter (p: p.type != null && !(fourByte p.type)) fn.params;
      slots = b.listToAttrs (
        map (p: { inherit (p) name; value = paramBase + p.offset; }) fn.params
        ++ map (l: { inherit (l) name; value = localBase + l.offset; }) fn.locals
      );
      names = map (p: p.name) fn.params ++ map (l: l.name) fn.locals;
    in
    if b.length (b.attrNames slots) != b.length names then
      throw "emit: function ${fn.name} has two frame symbols with the same name, so an ADDRLP4/ADDRFP4 would be ambiguous"
    else if wide != [ ] then
      throw "emit: parameter `${(b.head wide).name}' has type ${(b.head wide).type}, and this PoC lays out 4-byte scalars only (task-019)"
    else if size > maxFrame then
      throw "emit: frame of ${toString size} bytes for ${fn.name} exceeds the ${toString maxFrame}-byte immediate a one-instruction prologue can reach"
    else { inherit size savedBytes paramBase localBase slots; };

  # --- the target interface burg.nix calls back into ------------------------
  targetFor = fn: frame:
    let
      # Computed ONCE per function and not once per operand: `operand' is
      # called for every node with a symbol, and rebuilding this from the
      # forest list each time is quadratic in the size of the function.
      defined = labelsIn fn;
    in
    {
      inherit depthRegs cseRegs argReg constValue;
      label = fnName: n: labelOf fnName n;
      epilogue = epilogueOf;

      # %a: "what this node's own symbol means in assembly". A constant is its
      # value, a global is its name, a frame symbol is its displacement, and a
      # branch target is a local label. lcc makes the same distinction, in the
      # md's own local()/address()/defsymbol().
      operand = node:
        let
          sym = if node.syms == [ ] then throw "emit: ${node.op} has no symbol for %a" else b.head node.syms;
          d = splitDisp sym;
        in
        if b.match "CNST[A-Z][0-9]" node.op != null then sym
        else if node.op == "ADDRGP4" then
          withDisp
            (if !(isLabelName d.base) then d.base
            else if defined ? ${d.base} then labelOf fn.name d.base
            else litLabel d.base)
            d.disp
        else if node.op == "ADDRLP4" || node.op == "ADDRFP4" then
          toString (d.disp + (frame.slots.${d.base} or (throw
            "emit: ${node.op} names `${d.base}', which is neither a parameter nor a local of ${fn.name}")))
        else if isLabelName sym then labelOf fn.name sym
        else throw "emit: no %a meaning defined for ${node.op} (symbol `${sym}')";
    };

  # --- assembly ------------------------------------------------------------
  compile = fn:
    let
      frame = frameOf fn;
      burg = import ./burg.nix { inherit table; target = targetFor fn frame; };
      selected = burg.select fn;
      body = b.concatLists (map (s: s.code) selected);

      # Which registers the body actually touched, read back off the reduction
      # so the prologue saves those and no others. High-water marks, so a
      # register in the middle of a pool that happened to go unused is still
      # saved -- conservative in the safe direction.
      depthHigh = b.foldl' (a: s: if s.st.depthHigh > a then s.st.depthHigh else a) 0 selected;
      cseHigh = b.foldl' (a: s: if s.st.cseHigh > a then s.st.cseHigh else a) 0 selected;
      saved = b.genList (i: b.elemAt depthRegs i) (depthHigh + 1)
        ++ b.genList (i: b.elemAt cseRegs i) cseHigh;

      # A register's slot is its position in `savedRegs', not its position in
      # the list of the ones that were used -- that is what makes the layout
      # independent of the reduction.
      slotOf = r: frame.size - wordSize * (3 + indexOf r savedRegs);
      prologue =
        [
          "\t.text"
          "\t.align 2"
          "\t.globl ${fn.name}"
          "\t.type ${fn.name},@function"
          "${fn.name}:"
          "\taddi sp,sp,-${toString frame.size}"
          "\tsw ra,${toString (frame.size - wordSize)}(sp)"
          "\tsw s0,${toString (frame.size - 2 * wordSize)}(sp)"
        ]
        ++ map (r: "\tsw ${r},${toString (slotOf r)}(sp)") saved
        ++ [ "\taddi s0,sp,${toString frame.size}" ]
        # Spill the incoming argument registers into the parameter slots the
        # ADDRFP4 rules address. A real back end keeps them in registers where
        # it can; that is register allocation, and it is task-016.
        ++ b.genList
          (i:
            let p = b.elemAt fn.params i; in
            "\tsw ${argReg i},${toString (frame.paramBase + p.offset)}(s0)")
          (b.length fn.params);

      epilogue =
        [ "${epilogueOf fn.name}:" ]
        ++ map (r: "\tlw ${r},${toString (slotOf r)}(sp)") saved
        ++ [
          "\tlw s0,${toString (frame.size - 2 * wordSize)}(sp)"
          "\tlw ra,${toString (frame.size - wordSize)}(sp)"
          "\taddi sp,sp,${toString frame.size}"
          "\tret"
          "\t.size ${fn.name},.-${fn.name}"
        ];

      indent = line: if b.match "[^ \t].*:" line != null then line else "\t${line}";
      lines = prologue ++ map indent body ++ epilogue;
    in
    {
      inherit fn frame selected prologue epilogue lines saved;
      asm = b.concatStringsSep "\n" lines + "\n";
      bodyLines = body;
    };
in
if overlap != [ ] then
  throw "emit: ${b.head overlap} is in both the evaluation and the common-subexpression register pool, so one would silently destroy the other"
else {
  # `compile' is the whole interface; the rest are exported only because
  # must-fail.nix builds a target by hand to prove burg.nix checks for one.
  inherit compile frameOf targetFor constValue savedRegs;
  # `litLabel' is exported because whatever lays the lit segment DOWN has to
  # agree with what references it, and two copies of a naming convention are
  # two places for it to drift. poc/07-parser/data.nix is the other side.
  inherit litLabel;
}
