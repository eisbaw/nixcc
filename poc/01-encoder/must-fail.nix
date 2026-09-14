# Must-fail suite. A differential test against GNU as can only compare things
# that encode successfully, so the reject paths need their own checks: if the
# range predicate were inverted, every case in cases.nix would still pass.
let
  b = builtins;
  e = import ./encode.nix;

  # A case passes when forcing it throws.
  rejects = [
    { what = "I-imm above range";    expr = e.addi "a0" "a1" 2048; }
    { what = "I-imm below range";    expr = e.addi "a0" "a1" (-2049); }
    { what = "S-imm above range";    expr = e.sw "a0" "sp" 2048; }
    { what = "S-imm below range";    expr = e.sw "a0" "sp" (-2049); }
    { what = "shamt above range";    expr = e.slli "a0" "a1" 32; }
    { what = "shamt negative";       expr = e.srli "a0" "a1" (-1); }
    { what = "odd branch offset";    expr = e.beq "a0" "a1" 3; }
    { what = "B-imm above range";    expr = e.beq "a0" "a1" 4096; }
    { what = "B-imm below range";    expr = e.beq "a0" "a1" (-4098); }
    { what = "odd jump offset";      expr = e.jal "ra" 3; }
    { what = "J-imm above range";    expr = e.jal "ra" 1048576; }
    { what = "J-imm below range";    expr = e.jal "ra" (-1048578); }
    { what = "U-imm negative";       expr = e.lui "a0" (-1); }
    { what = "U-imm above range";    expr = e.lui "a0" 1048576; }
    { what = "unknown register name"; expr = e.addi "a0" "nosuchreg" 0; }
    { what = "register number 32";   expr = e.add 32 0 0; }
    { what = "negative register";    expr = e.add 0 (-1) 0; }
  ];

  # Control cases: these MUST still succeed, otherwise a blanket-throw encoder
  # would pass the whole must-fail suite.
  accepts = [
    { what = "I-imm at upper bound"; expr = e.addi "a0" "a1" 2047; }
    { what = "I-imm at lower bound"; expr = e.addi "a0" "a1" (-2048); }
    { what = "shamt at upper bound"; expr = e.slli "a0" "a1" 31; }
    { what = "B-imm at bounds";      expr = e.beq "a0" "a1" (-4096); }
    { what = "J-imm at bounds";      expr = e.jal "ra" 1048574; }
    { what = "U-imm at upper bound"; expr = e.lui "a0" 1048575; }
  ];

  # toBytes is on the emulator path, not the GNU-as diff path, so nothing above
  # would notice if it were wrong. Check it against toHex, which is diffed.
  byteProps = b.filter (w:
    let bs = e.toBytes w;
        recomposed = b.foldl' (acc: i: acc + b.elemAt bs i * e.pow2 (8 * i)) 0 [ 0 1 2 3 ];
        inRange = b.all (x: x >= 0 && x <= 255) bs;
    in !(b.length bs == 4 && inRange && recomposed == w)
  ) [ 0 1 255 256 4294967295 2147483648 19 (e.addi "a0" "a1" (-5)) (e.jal "ra" (-1048576)) ];

  wronglyAccepted = b.filter (c: (b.tryEval (b.deepSeq c.expr c.expr)).success) rejects;
  wronglyRejected = b.filter (c: !(b.tryEval (b.deepSeq c.expr c.expr)).success) accepts;
  names = cs: b.concatStringsSep ", " (map (c: c.what) cs);
in
  if byteProps != [ ] then
    throw "must-fail: toBytes round-trip failed for words: ${toString byteProps}"
  else if wronglyAccepted != [ ] then
    throw "must-fail: these should have been rejected but encoded fine: ${names wronglyAccepted}"
  else if wronglyRejected != [ ] then
    throw "must-fail: these should have encoded but threw: ${names wronglyRejected}"
  else
    "must-fail: ${toString (b.length rejects)} reject cases, ${toString (b.length accepts)} control cases, toBytes round-trip OK\n"
