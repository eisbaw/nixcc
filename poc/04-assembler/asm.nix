# The layer between the encoder and any code generator: an assembler.
#
# poc/01-encoder encodes RESOLVED offsets -- `e.jal "ra" 4'. A code generator
# does not have those; poc/03-matcher emits `beq a0,a1,.Lf_3', where .Lf_3 may
# not exist yet. This file closes that gap: items in, bytes and a symbol table
# out, every symbol resolved at layout time.
#
# Shape, and why:
#
#   * ITEMS ARE DATA (see `measure' for the whole vocabulary). Nothing here
#     parses text; parse.nix is a separate front end for the .s files that
#     already exist, and a code generator should emit items directly.
#
#   * ADDRESS ASSIGNMENT IS ONE genericClosure. It is a sequential pass that
#     must emit one placement per item, which is exactly what `foldl'' cannot
#     do and what `acc ++ [x]' does quadratically (decision-001). The operator
#     deepSeqs the state it returns: genericClosure forces only `key', so a
#     lazy field would build a thunk chain as deep as the loop and die with
#     "stack overflow", not with a slow run.
#
#   * RESOLUTION IS A PLAIN map, because after the first pass every label's
#     address is known. Forward and backward references are therefore the same
#     code path -- there is no fixup list and no second symbol table. The
#     symbol table is one `listToAttrs' over the label items.
#
#   * PC-RELATIVE OFFSETS ARE RELATIVE TO THE REFERRING INSTRUCTION'S OWN
#     ADDRESS, never to the one after it. `ctx.pc' below is the address of the
#     instruction being encoded, and for the two-instruction auipc pairs it
#     stays the address of the AUIPC for both halves, which is what the
#     PCREL_HI20/PCREL_LO12 pair means.
#
#   * lui/addi CONSTANT MATERIALISATION IS ONE HELPER, `hiLo', used by li, la
#     and call. The (v + 0x800) >> 12 correction and the 20-bit fold are
#     written once; `liParts' is likewise the single definition of how a
#     32-bit constant becomes instructions, so the SIZE of an `li' and its
#     ENCODING cannot disagree -- both call it.
#
# What this assembler refuses rather than guesses:
#
#   * A branch further than a B-type offset reaches. GNU as does the same;
#     relaxing to an inverted branch over a `jal' is a layout fixpoint, and an
#     unasserted fixpoint is how emit.nix's frame sizing went wrong once
#     already. Filed as task-021.
#   * A symbol nothing in the unit defines. There are no relocations here: a
#     single-eval compiler has one translation unit (task-022 if that changes).
#   * An instruction landing on an address that is not a multiple of four.
#   * `.align' beyond 2^4, because section bases are 16-aligned and alignment
#     is computed on section offsets (see `assemble').
{
  encode ? import ../01-encoder/encode.nix,
}:
let
  b = builtins;

  # --- arithmetic Nix does not have ---------------------------------------
  # No `%' operator, and `/' truncates toward zero, so these are for x >= 0.
  mod = x: y: x - (x / y) * y;
  alignUp = x: a: let r = mod x a; in if r == 0 then x else x + (a - r);
  max = x: y: if x > y then x else y;

  signed32 = v: let u = encode.u32 v; in if u >= 2147483648 then u - 4294967296 else u;

  # THE lui/addi split, in one place.
  #
  # `lui' writes bits 31:12 and `addi' adds a SIGN-EXTENDED 12-bit field, so
  # when the low half is >= 0x800 it subtracts 0x1000 and the upper half must
  # be pre-incremented: that is the +0x800 below, and forgetting it is the
  # classic bug this helper exists to have exactly one copy of.
  #
  # The 20-bit mask is load-bearing, not hygiene: for v = 0xfffff800 the
  # correction carries into bit 32 and the unmasked result (0x100000) is
  # outside lui's [0, 0xfffff] field. Masking wraps it to 0, which is right --
  # auipc 0 followed by addi -2048 is pc - 2048.
  hiLo = v:
    let
      u = encode.u32 v;
      low = b.bitAnd u 4095;
    in
    {
      hi = b.bitAnd ((u + 2048) / 4096) 1048575;
      lo = if low >= 2048 then low - 4096 else low;
    };

  # How a 32-bit constant becomes instructions. Called BOTH to size an `li'
  # during placement and to encode it afterwards, so the two cannot disagree.
  # One instruction when the value fits addi's signed 12-bit field (which is
  # why 0xfffff800 is one instruction and 0x800 is two), and one when the low
  # half is zero (0x80000000 is `lui' alone).
  liParts = rd: v:
    let
      s = signed32 v;
      hl = hiLo v;
    in
    if s >= -2048 && s <= 2047 then [ { mn = "addi"; args = [ rd "zero" s ]; } ]
    else
      [ { mn = "lui"; args = [ rd hl.hi ]; } ]
      ++ (if hl.lo == 0 then [ ] else [ { mn = "addi"; args = [ rd rd hl.lo ]; } ]);

  encodeSimple = p:
    let a = n: b.elemAt p.args n; in
    if p.mn == "addi" then encode.addi (a 0) (a 1) (a 2)
    else if p.mn == "lui" then encode.lui (a 0) (a 1)
    else throw "asm: internal error -- no expansion encoder for `${p.mn}'";

  # --- the instruction table ----------------------------------------------
  # Each entry declares the KINDS of its operands, so nothing has to guess
  # whether `a0' in `beq a0,a1,.L3' is a register or a label -- the mnemonic
  # says. Kinds: r register, i immediate, m memory (base+displacement),
  # l branch/jump target, s symbol whose ADDRESS is wanted.
  #
  # `alts' is the list of operand shapes the mnemonic accepts, longest first
  # -- GNU as spells `jal' both as `jal rd,target' and as `jal target', and
  # refusing the short form would be a gratuitous divergence. `n' is the
  # instruction's length in words as a function of its arguments; only `li'
  # varies. `enc' gets the placement context and returns words.
  a0 = a: b.elemAt a 0;
  a1 = a: b.elemAt a 1;
  a2 = a: b.elemAt a 2;

  fixed = ops: enc: { alts = [ ops ]; inherit enc; n = _: 1; };

  rrr = f: fixed [ "r" "r" "r" ] (_: a: [ (f (a0 a) (a1 a) (a2 a)) ]);
  rri = f: fixed [ "r" "r" "i" ] (_: a: [ (f (a0 a) (a1 a) (a2 a)) ]);
  # `lw a0,-60(s0)' and `sw a0,-60(s0)' have the same operand shape; the
  # encoder's S-type takes (src, base, imm) so that it reads like the
  # assembly, which is why both spell out the same call.
  mem = f: fixed [ "r" "m" ] (_: a: [ (f (a0 a) (a1 a).base (a1 a).disp) ]);
  bcc = f: fixed [ "r" "r" "l" ] (ctx: a: [ (f (a0 a) (a1 a) (ctx.branchOff (a2 a))) ]);
  uimm = f: fixed [ "r" "i" ] (_: a: [ (f (a0 a) (a1 a)) ]);

  table = {
    # --- real RV32I ------------------------------------------------------
    add = rrr encode.add; sub = rrr encode.sub;
    sll = rrr encode.sll; slt = rrr encode.slt; sltu = rrr encode.sltu;
    xor = rrr encode.xor; srl = rrr encode.srl; sra = rrr encode.sra;
    or = rrr encode.or; and = rrr encode.and;

    addi = rri encode.addi; slti = rri encode.slti; sltiu = rri encode.sltiu;
    xori = rri encode.xori; ori = rri encode.ori; andi = rri encode.andi;
    slli = rri encode.slli; srli = rri encode.srli; srai = rri encode.srai;

    lb = mem encode.lb; lh = mem encode.lh; lw = mem encode.lw;
    lbu = mem encode.lbu; lhu = mem encode.lhu;
    sb = mem encode.sb; sh = mem encode.sh; sw = mem encode.sw;

    beq = bcc encode.beq; bne = bcc encode.bne;
    blt = bcc encode.blt; bge = bcc encode.bge;
    bltu = bcc encode.bltu; bgeu = bcc encode.bgeu;

    lui = uimm encode.lui; auipc = uimm encode.auipc;

    # `jal rd,target' and `jalr rd,rs1,imm' in their two-and-three-operand
    # spellings; the one-operand forms are pseudo-instructions further down.
    jal = {
      alts = [ [ "r" "l" ] [ "l" ] ];
      n = _: 1;
      enc = ctx: a:
        if b.length a == 2 then [ (encode.jal (a0 a) (ctx.jumpOff (a1 a))) ]
        else [ (encode.jal "ra" (ctx.jumpOff (a0 a))) ];
    };
    jalr = {
      alts = [ [ "r" "r" "i" ] [ "r" ] ];
      n = _: 1;
      enc = _: a:
        if b.length a == 3 then [ (encode.jalr (a0 a) (a1 a) (a2 a)) ]
        else [ (encode.jalr "ra" (a0 a) 0) ];
    };

    ecall = fixed [ ] (_: _: [ encode.ecall ]);
    ebreak = fixed [ ] (_: _: [ encode.ebreak ]);
    fence = fixed [ ] (_: _: [ (encode.fence 15 15) ]);

    # --- pseudo-instructions ---------------------------------------------
    # These are here rather than in a code generator's rule table because
    # their expansion depends on the VALUE and the DISTANCE, neither of which
    # a pattern knows (task-003 carried this forward).
    nop = fixed [ ] (_: _: [ (encode.addi "zero" "zero" 0) ]);
    mv = fixed [ "r" "r" ] (_: a: [ (encode.addi (a0 a) (a1 a) 0) ]);
    not = fixed [ "r" "r" ] (_: a: [ (encode.xori (a0 a) (a1 a) (-1)) ]);
    neg = fixed [ "r" "r" ] (_: a: [ (encode.sub (a0 a) "zero" (a1 a)) ]);
    seqz = fixed [ "r" "r" ] (_: a: [ (encode.sltiu (a0 a) (a1 a) 1) ]);
    snez = fixed [ "r" "r" ] (_: a: [ (encode.sltu (a0 a) "zero" (a1 a)) ]);
    sltz = fixed [ "r" "r" ] (_: a: [ (encode.slt (a0 a) (a1 a) "zero") ]);
    sgtz = fixed [ "r" "r" ] (_: a: [ (encode.slt (a0 a) "zero" (a1 a)) ]);

    beqz = fixed [ "r" "l" ] (ctx: a: [ (encode.beq (a0 a) "zero" (ctx.branchOff (a1 a))) ]);
    bnez = fixed [ "r" "l" ] (ctx: a: [ (encode.bne (a0 a) "zero" (ctx.branchOff (a1 a))) ]);
    bgez = fixed [ "r" "l" ] (ctx: a: [ (encode.bge (a0 a) "zero" (ctx.branchOff (a1 a))) ]);
    bltz = fixed [ "r" "l" ] (ctx: a: [ (encode.blt (a0 a) "zero" (ctx.branchOff (a1 a))) ]);
    blez = fixed [ "r" "l" ] (ctx: a: [ (encode.bge "zero" (a0 a) (ctx.branchOff (a1 a))) ]);
    bgtz = fixed [ "r" "l" ] (ctx: a: [ (encode.blt "zero" (a0 a) (ctx.branchOff (a1 a))) ]);
    # The operand SWAP is the whole content of these four; getting it backwards
    # compares the wrong way round and still assembles.
    bgt = fixed [ "r" "r" "l" ] (ctx: a: [ (encode.blt (a1 a) (a0 a) (ctx.branchOff (a2 a))) ]);
    ble = fixed [ "r" "r" "l" ] (ctx: a: [ (encode.bge (a1 a) (a0 a) (ctx.branchOff (a2 a))) ]);
    bgtu = fixed [ "r" "r" "l" ] (ctx: a: [ (encode.bltu (a1 a) (a0 a) (ctx.branchOff (a2 a))) ]);
    bleu = fixed [ "r" "r" "l" ] (ctx: a: [ (encode.bgeu (a1 a) (a0 a) (ctx.branchOff (a2 a))) ]);

    j = fixed [ "l" ] (ctx: a: [ (encode.jal "zero" (ctx.jumpOff (a0 a))) ]);
    jr = fixed [ "r" ] (_: a: [ (encode.jalr "zero" (a0 a) 0) ]);
    ret = fixed [ ] (_: _: [ (encode.jalr "zero" "ra" 0) ]);

    # `li' is the only variable-length instruction here, and its length comes
    # from the same `liParts' that encodes it.
    li = {
      alts = [ [ "r" "i" ] ];
      n = a: b.length (liParts (a0 a) (a1 a));
      enc = _: a: map encodeSimple (liParts (a0 a) (a1 a));
    };

    # auipc pairs. BOTH halves use the offset from the AUIPC's address; using
    # the second instruction's own address for the low half is a silent
    # four-byte error, which is why `ctx.pc' never advances inside an item.
    la = {
      alts = [ [ "r" "s" ] ];
      n = _: 2;
      enc = ctx: a:
        let hl = hiLo (ctx.pcrel (a1 a)); in
        [ (encode.auipc (a0 a) hl.hi) (encode.addi (a0 a) (a0 a) hl.lo) ];
    };
    call = {
      alts = [ [ "s" ] ];
      n = _: 2;
      enc = ctx: a:
        let hl = hiLo (ctx.pcrel (a0 a)); in
        [ (encode.auipc "ra" hl.hi) (encode.jalr "ra" "ra" hl.lo) ];
    };
    tail = {
      alts = [ [ "s" ] ];
      n = _: 2;
      enc = ctx: a:
        let hl = hiLo (ctx.pcrel (a0 a)); in
        [ (encode.auipc "t1" hl.hi) (encode.jalr "zero" "t1" hl.lo) ];
    };
  };

  # --- operand shapes ------------------------------------------------------
  kindOf = x:
    if b.isInt x then "i"
    else if b.isAttrs x then "m"
    else if b.isString x then "sym"
    else "?";

  # The operand shape matching this many operands. Arity is resolved first so
  # that a kind error can name the right expectation.
  shapeFor = where: mnemonic: spec: nargs:
    let hit = b.filter (o: b.length o == nargs) spec.alts; in
    if hit == [ ] then
      throw ("asm: ${where}: `${mnemonic}' takes "
        + b.concatStringsSep " or " (map (o: toString (b.length o)) spec.alts)
        + " operand(s), given ${toString nargs}")
    else b.head hit;

  checkOps = where: mnemonic: spec: args:
    let
      ops = shapeFor where mnemonic spec (b.length args);
      bad = b.filter
        (i:
          let
            k = b.elemAt ops i;
            v = b.elemAt args i;
            seen = kindOf v;
          in
          if k == "r" then !(b.isString v)
          else if k == "i" then seen != "i"
          else if k == "m" then seen != "m" || !(v ? base) || !(v ? disp)
          else seen != "sym")
        (b.genList (i: i) (b.length ops));
    in
    if bad != [ ] then
      let i = b.head bad; in
      throw ("asm: ${where}: operand ${toString (i + 1)} of `${mnemonic}' must be "
        + "${
          {
            r = "a register";
            i = "an integer immediate";
            m = "a memory operand { base, disp }";
            l = "a branch target";
            s = "a symbol";
          }.${b.elemAt ops i}
        }, got ${kindOf (b.elemAt args i)}")
    else args;

  specOf = where: mnemonic:
    table.${mnemonic}
      or (throw "asm: ${where}: unknown mnemonic `${mnemonic}'. This assembler "
      + "implements RV32I and the usual pseudo-instructions; extension "
      + "opcodes are not silently ignored.");

  # --- numeric local labels ------------------------------------------------
  # `1:' can be defined many times and `1f'/`1b' mean the nearest definition
  # forward/backward, so they are not symbol-table names at all: they are
  # positional. Rewritten here, before placement, into names carrying the
  # DEFINING ITEM'S INDEX, which is unique by construction.
  numName = k: j: ".Lnum_${k}_${toString j}";
  isNumLabel = s: b.match "[0-9]+" s != null;
  numRef = s: b.match "([0-9]+)([fb])" s;

  normalise = items:
    let
      n = b.length items;
      idx = b.genList (i: i) n;
      defIndices = b.filter (i: let it = b.elemAt items i; in it.kind == "label" && isNumLabel it.name) idx;
      keys = b.attrNames (b.listToAttrs (map (i: { inherit ((b.elemAt items i)) name; value = true; }) defIndices));
      defsOf = b.listToAttrs (map
        (k: { name = k; value = b.filter (i: (b.elemAt items i).name == k) defIndices; })
        keys);
      resolve = i: s:
        let
          m = numRef s;
          k = b.head m;
          dir = b.elemAt m 1;
          ds = defsOf.${k} or [ ];
          cands = b.filter (j: if dir == "f" then j > i else j < i) ds;
        in
        if cands == [ ] then
          throw "asm: item ${toString i} refers to `${s}', but there is no `${k}:' ${if dir == "f" then "after" else "before"} it"
        else numName k (if dir == "f" then b.head cands else b.elemAt cands (b.length cands - 1));
      fix = i:
        let it = b.elemAt items i; in
        if it.kind == "label" && isNumLabel it.name then it // { name = numName it.name i; }
        else if it.kind != "insn" then it
        else
          let
            where = "item ${toString i}";
            spec = specOf where it.mnemonic;
            ops = shapeFor where it.mnemonic spec (b.length it.args);
            args = b.genList
              (j:
                let
                  k = b.elemAt ops j;
                  v = b.elemAt it.args j;
                in
                if (k == "l" || k == "s") && b.isString v && numRef v != null then resolve i v else v)
              (b.length it.args);
          in
          it // { inherit args; };
    in
    b.genList fix n;

  # --- measurement ---------------------------------------------------------
  # The whole item vocabulary lives here. `off' is the offset within the
  # CURRENT section, which is all an `.align' needs (see `assemble' for why
  # that is the same answer as aligning the absolute address).
  measure = where: item: sec: off:
    if item.kind == "label" then { size = 0; sec2 = sec; pow = 0; }
    else if item.kind == "section" then
      (if item.name == ".text" || item.name == ".data" then { size = 0; sec2 = item.name; pow = 0; }
      else throw "asm: ${where}: section `${item.name}' -- this assembler lays out .text and .data only (task-022)")
    else if item.kind == "global" || item.kind == "ignored" then { size = 0; sec2 = sec; pow = 0; }
    else if item.kind == "align" then
      (if item.pow < 0 || item.pow > 4 then
        throw "asm: ${where}: .align ${toString item.pow} means 2^${toString item.pow} bytes, and this assembler aligns section bases to 16, so it can only honour up to .align 4"
      else { size = alignUp off (encode.pow2 item.pow) - off; sec2 = sec; inherit (item) pow; })
    else if item.kind == "bytes" then
      (if item.width != 1 && item.width != 2 && item.width != 4 then
        throw "asm: ${where}: data width ${toString item.width} -- .byte, .half and .word only"
      else { size = item.width * b.length item.values; sec2 = sec; pow = 0; })
    else if item.kind == "zero" then { size = item.count; sec2 = sec; pow = 0; }
    else if item.kind == "insn" then
      let spec = specOf where item.mnemonic; in
      # `seq', not just passing it in: `n' for a fixed-length instruction
      # ignores its argument, so an unforced operand check is no check at all
      # -- the must-fail suite caught exactly that, with `beq' given two
      # operands reaching the encoder and dying on elemAt instead.
      { size = b.seq (checkOps where item.mnemonic spec item.args) (4 * spec.n item.args); sec2 = sec; pow = 0; }
    else throw "asm: ${where}: unknown item kind `${toString (item.kind or "<missing>")}'";

  # --- padding fill --------------------------------------------------------
  # GNU as does not pad a CODE section with zeros: it pads with instructions
  # that do nothing, so that padding landed on is harmless. Measured, not
  # guessed (`.byte' xN followed by `.align 3', N = 1..7):
  #
  #   zeros until the offset is even, then a 2-byte c.nop if that lands the
  #   rest on a 4-byte boundary, then 4-byte nops.
  #
  # It emits the compressed c.nop even for -march=rv32i, which has no C
  # extension -- padding is never executed, so it does not matter, but an
  # assembler that filled with zeros differs from GNU as in exactly two bytes
  # out of a 48-byte program, which is the sort of thing a differential test
  # exists to find. Data sections are zero-filled.
  nopBytes = encode.toBytes (encode.addi "zero" "zero" 0);
  cNopBytes = [ 1 0 ];
  fill = sec: off: count:
    if sec != ".text" then b.genList (_: 0) count
    else
      let
        want = mod off 2;
        lead = if want > count then count else want;
        at = off + lead;
        r0 = count - lead;
        half = if mod at 4 != 0 && r0 >= 2 then 2 else 0;
        r = r0 - half;
      in
      b.genList (_: 0) lead
      ++ (if half == 2 then cNopBytes else [ ])
      ++ b.concatLists (b.genList (_: nopBytes) (r / 4))
      ++ (if mod r 4 == 2 then cNopBytes else b.genList (_: 0) (mod r 4));

  # --- the assembler -------------------------------------------------------
  assemble =
    { items
    , textBase ? 65536 # 0x10000: where poc/03-matcher links, and 16-aligned
    }:
    let
      src = normalise items;
      n = b.length src;
      whereOf = i:
        let it = b.elemAt src i; in
        "item ${toString i}" + (if it.kind == "insn" then " (`${it.mnemonic}')" else " (${it.kind})");

      # PASS ONE. One genericClosure, one placement per item, no list ever
      # appended to. The state IS the running address; `place' is what item
      # key-1 was given, so `steps' has n+1 entries and the last one holds the
      # section sizes.
      steps = b.genericClosure {
        startSet = [{
          key = 0;
          sec = ".text";
          textOff = 0;
          dataOff = 0;
          textAlign = 4; # GNU as gives .text alignment 4 and .data 1
          dataAlign = 1;
          place = null;
        }];
        operator = s:
          if s.key >= n then [ ]
          else
            let
              m = measure (whereOf s.key) (b.elemAt src s.key) s.sec
                (if s.sec == ".text" then s.textOff else s.dataOff);
              next = {
                key = s.key + 1;
                sec = m.sec2;
                textOff = if s.sec == ".text" then s.textOff + m.size else s.textOff;
                dataOff = if s.sec == ".data" then s.dataOff + m.size else s.dataOff;
                textAlign =
                  if s.sec == ".text" && m.pow > 0 then max s.textAlign (encode.pow2 m.pow)
                  else s.textAlign;
                dataAlign =
                  if s.sec == ".data" && m.pow > 0 then max s.dataAlign (encode.pow2 m.pow)
                  else s.dataAlign;
                place = {
                  inherit (s) sec;
                  off = if s.sec == ".text" then s.textOff else s.dataOff;
                  inherit (m) size;
                };
              };
            in
            [ (b.deepSeq next next) ];
      };

      final = b.elemAt steps n;
      # genericClosure returns items in discovery order, and this loop has one
      # successor per state, so the order is the item order. Asserted rather
      # than assumed: a harness that indexed a reordered list would read the
      # wrong address for every item and still produce plausible bytes.
      misordered = b.filter (i: (b.elemAt steps i).key != i) (b.genList (i: i) (n + 1));

      textSize = alignUp final.textOff final.textAlign;
      dataSize = alignUp final.dataOff final.dataAlign;
      dataBase = alignUp (textBase + textSize) 16;
      baseOf = sec: if sec == ".text" then textBase else dataBase;

      placeAt = i: (b.elemAt steps (i + 1)).place;
      addrAt = i: let p = placeAt i; in baseOf p.sec + p.off;

      # PASS TWO's prerequisite: one symbol table, built once, O(1) lookup,
      # and the same table answers forward and backward references because it
      # is complete before any of them is resolved.
      labelIdx = b.filter (i: (b.elemAt src i).kind == "label") (b.genList (i: i) n);
      labelNames = map (i: (b.elemAt src i).name) labelIdx;
      symbols = b.listToAttrs (map (i: { inherit ((b.elemAt src i)) name; value = addrAt i; }) labelIdx);
      # The fast path is one length comparison; the quadratic scan that names
      # the offender only runs once a duplicate is known to exist.
      duplicated =
        let seen = b.listToAttrs (map (nm: { name = nm; value = true; }) labelNames); in
        if b.length (b.attrNames seen) == b.length labelNames then [ ]
        else b.filter (nm: b.length (b.filter (o: o == nm) labelNames) > 1) (b.attrNames seen);

      globals = b.filter (i: (b.elemAt src i).kind == "global") (b.genList (i: i) n);
      globalNames = map (i: (b.elemAt src i).name) globals;

      lookup = where: what: sym:
        symbols.${sym}
          or (throw "asm: ${where}: ${what} `${sym}', which nothing in this unit defines. "
          + "This assembler resolves every symbol at layout time and emits no relocations (task-022).");

      ctxAt = i:
        let
          pc = addrAt i;
          where = whereOf i;
          rel = what: sym: lookup where what sym - pc;
        in
        {
          inherit pc;
          pcrel = rel "takes the address of";
          # The range tests below are about the DIAGNOSTIC, not about safety:
          # encode.beq's own `fits "B-imm"' would throw anyway, and does if
          # these are removed. What they add is the label's name, the
          # distance, and what to do instead -- which is the whole value of a
          # refusal, so messages.sh holds them to their text rather than
          # must-fail.nix holding them to "something threw".
          branchOff = sym:
            let d = rel "branches to" sym; in
            if d < -4096 || d > 4094 then
              throw ("asm: ${where} at 0x${encode.toHex pc} branches to `${sym}' at "
                + "0x${encode.toHex symbols.${sym}}, which is ${toString d} bytes away; a "
                + "B-type offset must be in [-4096, 4094]. Invert the branch and jump over a "
                + "`j' instead -- automatic relaxation is task-021.")
            else d;
          jumpOff = sym:
            let d = rel "jumps to" sym; in
            if d < -1048576 || d > 1048574 then
              throw ("asm: ${where} at 0x${encode.toHex pc} jumps to `${sym}' at "
                + "0x${encode.toHex symbols.${sym}}, which is ${toString d} bytes away; a "
                + "J-type offset must be in [-1048576, 1048574]. Use `call', which is an "
                + "auipc/jalr pair and reaches anywhere (task-021).")
            else d;
        };

      # PASS TWO. A plain map: every address is already known, so a forward
      # reference costs exactly what a backward one costs.
      bytesAt = i:
        let
          it = b.elemAt src i;
          p = placeAt i;
          where = whereOf i;
        in
        if it.kind == "insn" then
          let
            spec = specOf where it.mnemonic;
            words = spec.enc (ctxAt i) (checkOps where it.mnemonic spec it.args);
          in
          if mod (addrAt i) 4 != 0 then
            throw "asm: ${where} would land at 0x${encode.toHex (addrAt i)}, which is not a multiple of four; RV32 instructions must be word-aligned"
          else if 4 * b.length words != p.size then
            throw "asm: internal error -- ${where} was sized ${toString p.size} bytes but encoded ${toString (4 * b.length words)}"
          else b.concatLists (map encode.toBytes words)
        else if it.kind == "align" then fill p.sec p.off p.size
        else if it.kind == "zero" then b.genList (_: 0) p.size
        else if it.kind == "bytes" then
          b.concatLists (map
            (v:
              let
                w = if b.isInt v then v else lookup where "stores the address of" v;
              in
              if b.isString v && it.width != 4 then
                throw "asm: ${where}: a symbol's address needs four bytes, not ${toString it.width}"
              else b.genList (k: b.bitAnd (encode.u32 w / encode.pow2 (8 * k)) 255) it.width)
            it.values)
        else [ ];

      sectionBytes = sec: size:
        let
          idx = b.filter (i: (placeAt i).sec == sec) (b.genList (i: i) n);
          body = b.concatLists (map bytesAt idx);
          used = if sec == ".text" then final.textOff else final.dataOff;
        in
        body ++ fill sec used (size - used);

      textBytes = sectionBytes ".text" textSize;
      dataBytes = sectionBytes ".data" dataSize;
      gap = dataBase - (textBase + textSize);
    in
    if misordered != [ ] then
      throw "asm: HARNESS FAULT -- genericClosure returned placements out of order at index ${toString (b.head misordered)}"
    else if duplicated != [ ] then
      throw "asm: label `${b.head duplicated}' is defined more than once, so a reference to it is ambiguous"
    else if mod textBase 16 != 0 then
      throw "asm: text base 0x${encode.toHex textBase} is not 16-byte aligned; alignment is computed on section offsets and would be wrong"
    else {
      inherit symbols textBase dataBase textSize dataSize;
      inherit (final) textAlign dataAlign;
      globals = globalNames;
      text = textBytes;
      data = dataBytes;
      # One flat image: .text, the gap that puts .data on its 16-byte base,
      # then .data. This is what the emulator loads at `textBase'. An empty
      # .data contributes NOTHING, not even the gap -- a trailing run of zeros
      # after the last instruction would be four bytes of image that GNU ld
      # does not produce, and the differential caught exactly that.
      bytes = if dataSize == 0 then textBytes else textBytes ++ b.genList (_: 0) gap ++ dataBytes;
      # Per-item view, for tests that want to assert an ADDRESS rather than a
      # byte -- the field nothing else looks at, and so the one a broken
      # assembler would get away with.
      placements = b.genList
        (i: let p = placeAt i; in {
          index = i;
          item = b.elemAt src i;
          inherit (p) sec size;
          addr = baseOf p.sec + p.off;
        })
        n;
      words = b.concatLists (b.genList
        (i:
          let it = b.elemAt src i; in
          if it.kind != "insn" then [ ]
          else
            let spec = specOf (whereOf i) it.mnemonic; in
            map (w: { addr = addrAt i; hex = encode.toHex w; inherit (it) mnemonic; })
              (spec.enc (ctxAt i) (checkOps (whereOf i) it.mnemonic spec it.args)))
        n);
    };
in
{
  inherit assemble hiLo liParts;
  # The same expansion the assembler uses, encoded -- so a test asserts what
  # `li' really produces rather than a second copy of the rule.
  liWords = rd: v: map encodeSimple (liParts rd v);
  inherit (encode) toHex;
  mnemonics = b.attrNames table;
  # The operand shapes, exported so parse.nix decides what a token means from
  # the SAME table the assembler encodes from, rather than from a second guess.
  operandShapes = b.mapAttrs (_: v: v.alts) table;
}
