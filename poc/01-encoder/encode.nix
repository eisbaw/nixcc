# RV32I instruction encoder in pure Nix.
#
# Nix has bitAnd/bitOr/bitXor but NO shift operators, so every shift is a
# multiply or divide by a power of two taken from a precomputed table.
# Integers are 64-bit signed and OVERFLOW THROWS rather than wrapping, so
# negative immediates are folded into unsigned 32-bit form before any field
# extraction (builtins.div truncates toward zero, which is wrong for bits).
let
  b = builtins;

  powers = b.genList (n: if n == 0 then 1 else 2 * b.elemAt powers (n - 1)) 33;
  pow2 = n: b.elemAt powers n;
  u32 = x:
    if x >= -2147483648 && x <= 4294967295 then b.bitAnd x 4294967295
    else throw "u32: ${toString x} is outside [-2^31, 2^32-1]";

  # bits x lo width  ==  (x >> lo) & ((1 << width) - 1), on the unsigned value
  bits = x: lo: width: b.bitAnd (b.div (u32 x) (pow2 lo)) (pow2 width - 1);
  # place a field at bit position pos
  at = v: pos: v * pow2 pos;

  regNames =
    let
      x = b.listToAttrs (b.genList (i: { name = "x${toString i}"; value = i; }) 32);
      abi = {
        zero = 0; ra = 1; sp = 2; gp = 3; tp = 4;
        t0 = 5; t1 = 6; t2 = 7; s0 = 8; fp = 8; s1 = 9;
        a0 = 10; a1 = 11; a2 = 12; a3 = 13; a4 = 14; a5 = 15; a6 = 16; a7 = 17;
        s2 = 18; s3 = 19; s4 = 20; s5 = 21; s6 = 22; s7 = 23; s8 = 24; s9 = 25;
        s10 = 26; s11 = 27; t3 = 28; t4 = 29; t5 = 30; t6 = 31;
      };
    in x // abi;

  reg = r:
    if b.isInt r then (if r >= 0 && r < 32 then r else throw "bad register number ${toString r}")
    else regNames.${r} or (throw "unknown register '${r}'");

  # Reject immediates that do not fit the field, rather than silently truncating.
  fits = name: v: lo: hi:
    if v >= lo && v <= hi then v
    else throw "${name}: immediate ${toString v} out of range [${toString lo}, ${toString hi}]";

  # --- instruction formats -------------------------------------------------
  rType = op: f3: f7: rd: rs1: rs2:
    at f7 25 + at (reg rs2) 20 + at (reg rs1) 15 + at f3 12 + at (reg rd) 7 + op;

  iType = op: f3: rd: rs1: imm:
    at (bits (fits "I-imm" imm (-2048) 2047) 0 12) 20
    + at (reg rs1) 15 + at f3 12 + at (reg rd) 7 + op;

  # shift-immediate: shamt in [0,31] with funct7 in the top bits
  shType = op: f3: f7: rd: rs1: shamt:
    at f7 25 + at (fits "shamt" shamt 0 31) 20 + at (reg rs1) 15 + at f3 12 + at (reg rd) 7 + op;

  # Argument order deliberately matches the assembly it encodes -- `sw a0, 0(sp)`
  # is (src, base, imm). Taking base first reads naturally from the instruction
  # format and is the reverse of every other mnemonic here, and a swapped pair
  # still encodes to a valid instruction, so a differential test would not catch
  # the mistake.
  sType = op: f3: rs2: rs1: imm:
    let i = bits (fits "S-imm" imm (-2048) 2047) 0 12; in
    at (bits i 5 7) 25 + at (reg rs2) 20 + at (reg rs1) 15 + at f3 12 + at (bits i 0 5) 7 + op;

  # branch offsets are even and encoded scaled by 2, bits shuffled
  bType = op: f3: rs1: rs2: imm:
    let i = bits (fits "B-imm" imm (-4096) 4094) 0 13; in
    if b.bitAnd i 1 != 0 then throw "B-imm must be even, got ${toString imm}" else
    at (bits i 12 1) 31 + at (bits i 5 6) 25 + at (reg rs2) 20 + at (reg rs1) 15
    + at f3 12 + at (bits i 1 4) 8 + at (bits i 11 1) 7 + op;

  uType = op: rd: imm:
    at (bits (fits "U-imm" imm 0 1048575) 0 20) 12 + at (reg rd) 7 + op;

  jType = op: rd: imm:
    let i = bits (fits "J-imm" imm (-1048576) 1048574) 0 21; in
    if b.bitAnd i 1 != 0 then throw "J-imm must be even, got ${toString imm}" else
    at (bits i 20 1) 31 + at (bits i 1 10) 21 + at (bits i 11 1) 20
    + at (bits i 12 8) 12 + at (reg rd) 7 + op;

  OP = 51; OP_IMM = 19; LOAD = 3; STORE = 35; BRANCH = 99;
  JALR = 103; JAL = 111; LUI = 55; AUIPC = 23; SYSTEM = 115; MISC_MEM = 15;

  i = {
    # register-register
    add  = rType OP 0 0;    sub = rType OP 0 32;
    sll  = rType OP 1 0;    slt = rType OP 2 0;   sltu = rType OP 3 0;
    xor  = rType OP 4 0;    srl = rType OP 5 0;   sra  = rType OP 5 32;
    or   = rType OP 6 0;    and = rType OP 7 0;
    # register-immediate
    addi = iType OP_IMM 0;  slti = iType OP_IMM 2; sltiu = iType OP_IMM 3;
    xori = iType OP_IMM 4;  ori  = iType OP_IMM 6; andi  = iType OP_IMM 7;
    slli = shType OP_IMM 1 0; srli = shType OP_IMM 5 0; srai = shType OP_IMM 5 32;
    # loads / stores
    lb = iType LOAD 0; lh = iType LOAD 1; lw = iType LOAD 2;
    lbu = iType LOAD 4; lhu = iType LOAD 5;
    sb = sType STORE 0; sh = sType STORE 1; sw = sType STORE 2;
    # branches
    beq = bType BRANCH 0; bne = bType BRANCH 1;
    blt = bType BRANCH 4; bge = bType BRANCH 5;
    bltu = bType BRANCH 6; bgeu = bType BRANCH 7;
    # jumps and upper immediates
    jal = jType JAL; jalr = iType JALR 0;
    lui = uType LUI; auipc = uType AUIPC;
    # memory ordering. Operand bits are i=8, o=4, r=2, w=1; plain `fence` in
    # GNU as means `fence iorw, iorw`, i.e. pred = succ = 15.
    fence = pred: succ:
      at 0 28 + at (fits "fence pred" pred 0 15) 24 + at (fits "fence succ" succ 0 15) 20
      + MISC_MEM;
    # system
    ecall = iType SYSTEM 0 "zero" "zero" 0;
    ebreak = iType SYSTEM 0 "zero" "zero" 1;
  };

  # word -> 4 little-endian bytes, the form a Nix RISC-V emulator consumes
  toBytes = w: b.genList (n: bits w (8 * n) 8) 4;
  toHex = w:
    let d = "0123456789abcdef";
        nib = n: b.substring (bits w (4 * n) 4) 1 d;
    in b.concatStringsSep "" (map nib [ 7 6 5 4 3 2 1 0 ]);
in
  i // { inherit toBytes toHex u32 bits pow2 reg; }
