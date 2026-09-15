# What the assembler is expected to produce, as tables.
#
# Every hex word here was read off riscv32-none-elf-as for the same program
# (run.sh diffs the whole image against it on every run), so these are pinned
# copies of an independent oracle rather than of our own output. They exist as
# well as the differential because the differential needs binutils and a
# subprocess; check.nix is pure, runs inside `nix flake check', and fails at
# evaluation time.
#
# The floors that stop a table from being emptied are NOT here. They are in
# check.nix, because a floor kept beside the data it guards is defeated by the
# same one-file edit it exists to catch -- poc/03-matcher learned that the hard
# way.
rec {
  # The programs in progs/, and what the layout comes out as. `textAlign' is
  # the section alignment GNU as derives from the widest .align in the file.
  programs = [
    { name = "pcrel"; textSize = 60; textAlign = 4; dataSize = 0; }
    { name = "consts"; textSize = 88; textAlign = 4; dataSize = 0; }
    { name = "data"; textSize = 48; textAlign = 16; dataSize = 0; }
    { name = "range"; textSize = 8200; textAlign = 4; dataSize = 0; }
    { name = "pseudo"; textSize = 268; textAlign = 4; dataSize = 0; }
    { name = "symexpr"; textSize = 84; textAlign = 4; dataSize = 0; }
  ];

  # Label addresses. This is this task's equivalent of the lexer's line
  # numbers: the field the byte comparison does not look at, and therefore the
  # one an assembler could get wrong while every encoding still matched.
  # progs/ is linked at 0x10000 = 65536.
  symbols = [
    { file = "pcrel"; name = "self"; addr = 65536; }
    { file = "pcrel"; name = "over"; addr = 65548; }
    { file = "pcrel"; name = "back"; addr = 65548; }
    { file = "pcrel"; name = "fwd"; addr = 65568; }
    { file = "pcrel"; name = "here"; addr = 65576; }
    { file = "data"; name = "here"; addr = 65560; }
    { file = "range"; name = "fardown"; addr = 69628; }
    { file = "pseudo"; name = "target"; addr = 65704; }
    { file = "pseudo"; name = "far"; addr = 65800; }
    { file = "symexpr"; name = "after"; addr = 65576; }
    { file = "symexpr"; name = "tbl"; addr = 65592; }
  ];

  # SYMBOL EXPRESSIONS: `tbl+8', a base symbol with a constant displacement,
  # which is what lcc folds `msg[2]' into (task-023). What is pinned is the
  # ADDRESS the assembler resolves the expression to, through the same
  # `lookup' every instruction goes through -- the encodings below pin the
  # bytes, and these pin the number, because an auipc/addi pair carries a
  # relative distance and a wrong base with a compensating offset encodes
  # identically.
  #
  # `after+0' is here because zero is the displacement a naive split reports
  # for any expression, and `tbl-4' because the sign is the half a pattern can
  # get wrong while `+' still works. Every address was read off
  # riscv32-none-elf-nm for the same file.
  symbolExpressions = [
    { file = "symexpr"; expr = "tbl+8"; addr = 65600; note = "the third word of tbl"; }
    { file = "symexpr"; expr = "tbl-4"; addr = 65588; note = "backwards, which is `done'"; }
    { file = "symexpr"; expr = "after+0"; addr = 65576; note = "a zero displacement is still an expression"; }
    { file = "symexpr"; expr = "after+8"; addr = 65584; note = ""; }
    { file = "symexpr"; expr = "after+4"; addr = 65580; note = "a branch target, which goes through branchOff"; }
    { file = "symexpr"; expr = "done-4"; addr = 65584; note = "a jump target, which goes through jumpOff"; }
    { file = "symexpr"; expr = "tbl"; addr = 65592; note = "the base on its own, which must not go through the split"; }
  ];

  # Every word of symexpr.s, read off riscv32-none-elf-objdump for the same
  # file. Four callers of one `lookup' -- `la' and `call' through `pcrel', `j'
  # through `jumpOff', `beq' through `branchOff' -- so a displacement lost on
  # any one of those paths shows up here as a changed encoding.
  symexprWords = [
    { addr = 65536; hex = "00000517"; mnemonic = "la"; note = "la tbl+8, auipc half"; }
    { addr = 65536; hex = "04050513"; mnemonic = "la"; note = "addi 64: 8 past tbl, 56 past here"; }
    { addr = 65544; hex = "00000597"; mnemonic = "la"; note = ""; }
    { addr = 65544; hex = "03058593"; mnemonic = "la"; note = "addi 48: the base with no displacement"; }
    { addr = 65552; hex = "00000617"; mnemonic = "la"; note = ""; }
    { addr = 65552; hex = "02460613"; mnemonic = "la"; note = "addi 36: tbl-4, four LESS than the base"; }
    { addr = 65560; hex = "00052683"; mnemonic = "lw"; note = ""; }
    { addr = 65564; hex = "00b50863"; mnemonic = "beq"; note = "+16 to after+4, not +12 to after"; }
    { addr = 65568; hex = "00000097"; mnemonic = "call"; note = "call after+0, auipc half"; }
    { addr = 65568; hex = "008080e7"; mnemonic = "call"; note = "jalr 8, from the auipc's own pc"; }
    { addr = 65576; hex = "00000013"; mnemonic = "nop"; note = ""; }
    { addr = 65580; hex = "0040006f"; mnemonic = "j"; note = "+4 to done-4, not +8 to done"; }
    { addr = 65584; hex = "00000013"; mnemonic = "nop"; note = ""; }
    { addr = 65588; hex = "00008067"; mnemonic = "ret"; note = ""; }
  ];

  # THE PC-RELATIVE BASE, one case per way of getting it wrong.
  #
  # A branch offset is measured from the branch's OWN address. Computing it
  # from the next instruction instead shifts every one of these by four, and
  # every shifted value is still a perfectly valid branch -- which is why this
  # table pins the words and not just "it assembled".
  #
  #   self-branch   offset 0     would become -4
  #   forward       offset +8    would become +4
  #   backward      offset -4    would become -8
  #   la to itself  delta 0      would become -4, so `addi' stops being 0
  pcrelWords = [
    { addr = 65536; hex = "00b50063"; mnemonic = "beq"; note = "offset 0: branches to itself"; }
    { addr = 65540; hex = "00b51463"; mnemonic = "bne"; note = "offset +8: skips one instruction"; }
    { addr = 65544; hex = "00150513"; mnemonic = "addi"; note = ""; }
    { addr = 65548; hex = "00250513"; mnemonic = "addi"; note = ""; }
    { addr = 65552; hex = "feb54ee3"; mnemonic = "blt"; note = "offset -4: the instruction before"; }
    { addr = 65556; hex = "fedff0ef"; mnemonic = "jal"; note = "J-type, -20"; }
    { addr = 65560; hex = "0080006f"; mnemonic = "j"; note = "J-type, +8"; }
    { addr = 65564; hex = "00000013"; mnemonic = "nop"; note = ""; }
    { addr = 65568; hex = "00000097"; mnemonic = "call"; note = "auipc half of a -32 call"; }
    { addr = 65568; hex = "fe0080e7"; mnemonic = "call"; note = "jalr half, low 12 of the SAME delta"; }
    { addr = 65576; hex = "00000317"; mnemonic = "la"; note = "delta 0: auipc 0"; }
    { addr = 65576; hex = "00030313"; mnemonic = "la"; note = "delta 0: addi 0, from the auipc's pc"; }
    { addr = 65584; hex = "00000397"; mnemonic = "la"; note = "delta -16"; }
    { addr = 65584; hex = "ff038393"; mnemonic = "la"; note = "delta -16, low half"; }
    { addr = 65592; hex = "00008067"; mnemonic = "ret"; note = ""; }
  ];

  # The branch range, at the two values that still fit.
  rangeWords = [
    { addr = 65536; hex = "7eb50ee3"; mnemonic = "beq"; note = "+4092"; }
    { addr = 69628; hex = "00000013"; mnemonic = "nop"; note = ""; }
    { addr = 73724; hex = "80b55063"; mnemonic = "bge"; note = "-4096, the minimum a B-type reaches"; }
    { addr = 73728; hex = "800fe06f"; mnemonic = "j"; note = ""; }
    { addr = 73732; hex = "00008067"; mnemonic = "ret"; note = ""; }
  ];

  # lui/addi materialisation. `want' is the whole expansion, so a case that
  # should be ONE instruction fails loudly if a second appears -- which is
  # what an assembler that skips the 12-bit fast path does, and it is the only
  # thing that distinguishes 0xfffff800 from 0x800.
  #
  # The first five are the ones the task names.
  requiredLiValues = [ 2047 2048 4294965248 (-1) 2147483648 ];
  liCases = [
    { value = 2047; rd = "a0"; want = [ "7ff00513" ]; note = "0x7ff: the largest that addi alone holds"; }
    { value = 2048; rd = "a1"; want = [ "000015b7" "80058593" ]; note = "0x800: the +0x800 correction's reason for existing"; }
    { value = 4294965248; rd = "a2"; want = [ "80000613" ]; note = "0xfffff800 is -2048, and fits addi alone"; }
    { value = -1; rd = "a3"; want = [ "fff00693" ]; note = "-1"; }
    { value = 2147483648; rd = "a4"; want = [ "80000737" ]; note = "0x80000000: zero low half, lui alone"; }
    { value = 0; rd = "a5"; want = [ "00000793" ]; note = ""; }
    { value = -2048; rd = "a7"; want = [ "80000893" ]; note = "the negative boundary"; }
    { value = -2049; rd = "t0"; want = [ "fffff2b7" "7ff28293" ]; note = "one past it, so two instructions"; }
    { value = 4096; rd = "t5"; want = [ "00001f37" ]; note = ""; }
    { value = 4294963200; rd = "t6"; want = [ "ffffffb7" ]; note = "0xfffff000"; }
    { value = 305419896; rd = "t4"; want = [ "12345eb7" "678e8e93" ]; note = "0x12345678"; }
    { value = 2147483647; rd = "t2"; want = [ "800003b7" "fff38393" ]; note = "0x7fffffff"; }
  ];

  # hiLo on its own, because the two places it can go wrong are invisible in
  # most `li' expansions: the +0x800 pre-increment, and the 20-bit fold that
  # the pre-increment can carry out of.
  hiLoCases = [
    { value = 0; hi = 0; lo = 0; }
    { value = 2047; hi = 0; lo = 2047; }
    { value = 2048; hi = 1; lo = -2048; note = "without +0x800 this would be hi=0"; }
    { value = 4095; hi = 1; lo = -1; }
    { value = 4096; hi = 1; lo = 0; }
    { value = 4294965248; hi = 0; lo = -2048; note = "0xfffff800: the correction carries into bit 32 and the 20-bit fold brings it back to 0"; }
    { value = -1; hi = 0; lo = -1; }
    { value = 2147483648; hi = 524288; lo = 0; }
    { value = 2147483647; hi = 524288; lo = -1; }
  ];

  # Four of pseudo.s's expansions, chosen because the mistake in them is a
  # SWAP: `bgt a,b,L' is `blt b,a,L', and reversing it assembles, links and
  # runs while comparing the wrong way round.
  swapWords = [
    { addr = 65728; hex = "fea5c4e3"; mnemonic = "bgt"; note = "blt with the operands reversed"; }
    { addr = 65732; hex = "fea5d2e3"; mnemonic = "ble"; note = "bge with the operands reversed"; }
    { addr = 65736; hex = "fea5e0e3"; mnemonic = "bgtu"; note = "bltu with the operands reversed"; }
    { addr = 65740; hex = "fca5fee3"; mnemonic = "bleu"; note = "bgeu with the operands reversed"; }
  ];

  # ITEMS ARE DATA, proved without the text front end: this program is built
  # as an item list, never parsed, and is the shape a code generator should
  # emit -- no assembly text is involved anywhere in it.
  #
  # Its branch target is a label named `a1', which is also a register name.
  # That resolves as a label because operand kinds come from the MNEMONIC and
  # not from how a token looks, and it is here so that the day someone
  # shortcuts that with "strings that look like registers are registers", this
  # fails.
  handBuilt = {
    items = [
      { kind = "section"; name = ".text"; }
      { kind = "global"; name = "_start"; }
      { kind = "label"; name = "_start"; }
      { kind = "insn"; mnemonic = "li"; args = [ "a0" 2048 ]; }
      { kind = "insn"; mnemonic = "beq"; args = [ "a0" "zero" "a1" ]; } # forward, to a label called a1
      { kind = "insn"; mnemonic = "addi"; args = [ "a0" "a0" 1 ]; }
      { kind = "label"; name = "a1"; }
      { kind = "insn"; mnemonic = "sw"; args = [ "a0" { base = "sp"; disp = -4; } ]; }
      { kind = "insn"; mnemonic = "la"; args = [ "t0" "table" ]; }
      { kind = "insn"; mnemonic = "ret"; args = [ ]; }
      { kind = "align"; pow = 2; }
      { kind = "label"; name = "table"; }
      { kind = "bytes"; width = 4; values = [ "_start" "a1" 305419896 ]; }
      { kind = "section"; name = ".data"; }
      { kind = "label"; name = "counter"; }
      { kind = "bytes"; width = 4; values = [ 0 ]; }
    ];
    # li 0x800 is two words, so `a1' is at 0x10000 + 8 + 4 + 4 = 0x10010, and
    # the .word table starts right after `ret' -- the `.align 2' before it
    # pads nothing, because everything ahead of it is a whole instruction.
    symbols = { _start = 65536; a1 = 65552; table = 65568; counter = 65584; };
    textSize = 44;
    dataBase = 65584;
    dataSize = 4;
    # The two symbol-valued .words, little-endian, then 0x12345678.
    tailBytes = [ 0 0 1 0 16 0 1 0 120 86 52 18 ];
  };

  # A label whose own NAME ends in `-1', in a unit that defines no `f'. Built
  # as items and never as text, because GNU as has no spelling for it -- `-'
  # is not a symbol character there -- so this is a claim about OUR assembler
  # alone and the differential cannot make it.
  #
  # What it pins: a name that PARSES as a symbol expression but IS a label
  # resolves to the label, rather than being refused for a base symbol nobody
  # wrote down. The case where both readings answer and disagree is a refusal,
  # and lives in must-fail.nix.
  literalSignedName = {
    items = [
      { kind = "section"; name = ".text"; }
      { kind = "label"; name = "f-1"; }
      { kind = "insn"; mnemonic = "nop"; args = [ ]; }
      { kind = "label"; name = "g"; }
      { kind = "insn"; mnemonic = "ret"; args = [ ]; }
    ];
    signed = 65536;
    plain = 65540;
  };

  # Every mnemonic the table implements must occur somewhere in progs/, or the
  # differential is testing less than it looks like it is.
  mnemonicCorpus = [ "pcrel" "consts" "data" "range" "pseudo" "symexpr" ];
}
