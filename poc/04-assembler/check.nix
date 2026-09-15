# The assembler's verification, in one place so that run.sh and the flake's
# `checks.assembler' cannot drift apart. Forcing this either throws with a
# precise message or returns a summary of what was actually measured.
#
# The harness is as much on trial as the assembler. This project has shipped
# four tests that reported PASS while verifying nothing, so every count below
# is counted from work done, and a table that has shrunk or been emptied is a
# HARNESS FAULT rather than a pass. The floors live here rather than beside
# the tables in cases.nix, because a floor in the same file as its data is
# defeated by the same one-file edit it exists to catch.
#
# Guard ordering, which took three goes to get right and is asserted by the
# mutation test rather than argued for:
#
#   1. The floors, because an emptied table cannot produce a meaningful
#      verdict and a verdict derived from one would be a lie.
#   2. Whether the CORPUS still exercises what it claims to -- every mnemonic
#      reached, a forward reference and a backward one still present. Same
#      reason as the floors, and it has to come before the verdicts: deleting
#      one instruction from progs/ moves every address after it, so with this
#      checked last the report is a wrong branch encoding rather than "you
#      deleted a case".
#   3. hiLo and liParts, the smallest units here. A broken lui/addi split
#      makes `call' and `la' wrong in every program, and reporting THAT sends
#      the reader to the wrong file.
#   4. The program-level encodings, then the addresses and the layout.
#   5. Last, the "did we actually compare anything" arithmetic.
{
  progs ? ./progs,
  asm ? import ./asm.nix { },
}:
let
  b = builtins;
  cases = import ./cases.nix;
  parse = import ./parse.nix { inherit asm; };

  # Floors, not targets. Raise them if the tables legitimately grow.
  minPrograms = 5;
  minPcrelWords = 15;
  minRangeWords = 5;
  minLiCases = 12;
  minHiLoCases = 9;
  minSymbols = 9;
  minSwapWords = 4;
  minMnemonics = 55;
  minHandItems = 16;

  fault = msg: throw "HARNESS FAULT: ${msg}";

  # Every verdict below reports its FIRST failure and a count of the rest.
  # Reporting all of them reads well until two different bugs both make four
  # things wrong, at which point their reports overlap and the mutation test
  # can no longer tell the checks apart -- which is the check failing at its
  # actual job. The first failure is also the one that explains the others.
  firstError = errs:
    if errs == [ ] then null
    else b.head errs + (if b.length errs == 1 then "" else " (and ${toString (b.length errs - 1)} more)");

  built = b.listToAttrs (map
    (p: {
      inherit (p) name;
      value = asm.assemble { items = parse.parseFile (progs + "/${p.name}.s"); };
    })
    cases.programs);

  hand = asm.assemble { items = cases.handBuilt.items; };

  # --- encodings ----------------------------------------------------------
  # Compared elementwise by INDEX rather than by zipping two lists, because a
  # zip that truncates is precisely how this project's first differential test
  # reported a clean pass over half its cases.
  # Reports the FIRST mismatch and a count of the rest, not all of them. Two
  # different bugs -- a wrong PC base and a wrong auipc delta -- both make the
  # `la' words wrong, and a report listing every mismatch made the two
  # indistinguishable in the mutation test. The first one is also the one that
  # explains the others.
  wordCheck = file: want:
    let
      got = built.${file}.words;
      n = b.length want;
      mismatched = b.filter
        (i:
          let
            w = b.elemAt want i;
            g = b.elemAt got i;
          in
          g.hex != w.hex || g.addr != w.addr || g.mnemonic != w.mnemonic)
        (b.genList (i: i) (if b.length got < n then b.length got else n));
      report = i:
        let
          w = b.elemAt want i;
          g = b.elemAt got i;
          rest = b.length mismatched - 1;
        in
        "${file} word ${toString i}${if w.note == "" then "" else " (${w.note})"}: "
        + "expected ${w.mnemonic}@0x${asm.toHex w.addr}=${w.hex}, "
        + "got ${g.mnemonic}@0x${asm.toHex g.addr}=${g.hex}"
        + (if rest == 0 then "" else " (and ${toString rest} later word(s) too)");
    in
    if b.length got != n then
      "${file} assembled to ${toString (b.length got)} instruction words, ${toString n} expected"
    else if mismatched != [ ] then report (b.head mismatched)
    else null;

  # Kept as two separate bindings rather than one filtered list, and reported
  # in this order, because a list has to be forced whole: with both in one
  # `filter', a change that makes pcrel.s's words wrong AND pushes range.s's
  # -4096 branch out of range reports the range THROW and hides the precise
  # word mismatch that explains it. Measured, from the pc+4 mutation.
  pcrelError = wordCheck "pcrel" cases.pcrelWords;
  rangeError = wordCheck "range" cases.rangeWords;

  # The swap table names four instructions inside a much longer program, so
  # these are looked up by address rather than by index.
  swapErrors = b.filter (e: e != null) (map
    (w:
      let hits = b.filter (g: g.addr == w.addr) built.pseudo.words; in
      if hits == [ ] then "pseudo has no instruction at 0x${asm.toHex w.addr} for ${w.mnemonic}"
      else if (b.head hits).hex != w.hex then
        "pseudo ${w.mnemonic}@0x${asm.toHex w.addr} (${w.note}): expected ${w.hex}, got ${(b.head hits).hex}"
      else null)
    cases.swapWords);

  # --- lui/addi materialisation -------------------------------------------
  liErrors = b.filter (e: e != null) (map
    (c:
      let
        got = map asm.toHex (asm.liWords c.rd c.value);
      in
      if got != c.want then
        "li ${c.rd},${toString c.value}${if c.note == "" then "" else " (${c.note})"}: "
        + "expected [${b.concatStringsSep " " c.want}], got [${b.concatStringsSep " " got}]"
      else null)
    cases.liCases);

  liValues = map (c: c.value) cases.liCases;
  missingRequired = b.filter (v: !(b.elem v liValues)) cases.requiredLiValues;

  hiLoErrors = b.filter (e: e != null) (map
    (c:
      let got = asm.hiLo c.value; in
      if got.hi != c.hi || got.lo != c.lo then
        "hiLo ${toString c.value}${if c ? note then " (${c.note})" else ""}: "
        + "expected hi=${toString c.hi} lo=${toString c.lo}, got hi=${toString got.hi} lo=${toString got.lo}"
      else null)
    cases.hiLoCases);

  # `.globl' is the one directive that is recorded rather than acted on, and
  # a recorded-but-never-read field is a field that can quietly stop being
  # recorded. Every program in progs/ declares _start, so this keeps it live.
  globalErrors = map
    (p: "${p.name}: `.globl _start' was parsed but does not appear in the assembled globals")
    (b.filter (p: !(b.elem "_start" built.${p.name}.globals)) cases.programs);

  # --- pass one and pass two agree on every instruction's length -----------
  # `li' is the only variable-length instruction here, and its length comes
  # from the same `liParts' that encodes it -- but "comes from the same
  # helper" is a claim about the source, and this is the claim about the
  # result: the bytes each item was GIVEN by address assignment against the
  # words it actually produced. The `wide' floor keeps it from being vacuous
  # on a corpus that happened to contain no two-word instruction.
  sizeReports = b.concatLists (map
    (p:
      let r = built.${p.name}; in
      map
        (pl: {
          file = p.name;
          inherit (pl) addr size;
          mnemonic = pl.item.mnemonic;
          produced = 4 * b.length (b.filter (w: w.addr == pl.addr) r.words);
        })
        (b.filter (pl: pl.item.kind == "insn") r.placements))
    cases.programs);
  sizeErrors = map
    (r: "${r.file}: `${r.mnemonic}' at 0x${asm.toHex r.addr} was placed as ${toString r.size} bytes but encoded to ${toString r.produced}")
    (b.filter (r: r.size != r.produced) sizeReports);
  wide = b.filter (r: r.size > 4) sizeReports;

  # --- addresses ----------------------------------------------------------
  # The field nothing else looks at. Every encoding above could be right with
  # every label address wrong, provided the relative distances happened to
  # work out -- which is exactly what a wrong section base does.
  symbolErrors = b.filter (e: e != null) (map
    (s:
      let got = built.${s.file}.symbols.${s.name} or null; in
      if got == null then "${s.file} defines no symbol `${s.name}'"
      else if got != s.addr then
        "${s.file}: `${s.name}' is at 0x${asm.toHex got}, expected 0x${asm.toHex s.addr}"
      else null)
    cases.symbols);

  layoutErrors = b.filter (e: e != null) (map
    (p:
      let r = built.${p.name}; in
      if r.textSize != p.textSize then
        "${p.name}: .text is ${toString r.textSize} bytes, expected ${toString p.textSize}"
      else if r.textAlign != p.textAlign then
        "${p.name}: .text alignment is ${toString r.textAlign}, expected ${toString p.textAlign}"
      else if r.dataSize != p.dataSize then
        "${p.name}: .data is ${toString r.dataSize} bytes, expected ${toString p.dataSize}"
      else if b.length r.bytes != p.textSize + p.dataSize then
        "${p.name}: the image is ${toString (b.length r.bytes)} bytes but the sections total ${toString (p.textSize + p.dataSize)}"
      else null)
    cases.programs);

  # --- forward and backward references, from ONE symbol table --------------
  # pcrel.s references `over' before it is defined and `back' after, and both
  # are answered by the same attrset. Asserted as a property rather than
  # trusted from the word table, so that a two-pass assembler that grew a
  # separate fixup path for forward references would have to say so.
  pcrelItems = parse.parseFile (progs + "/pcrel.s");
  indexOfLabel = nm:
    let hits = b.filter (i: let it = b.elemAt pcrelItems i; in it.kind == "label" && it.name == nm)
      (b.genList (i: i) (b.length pcrelItems));
    in if hits == [ ] then -1 else b.head hits;
  indexOfRef = nm:
    let hits = b.filter
      (i: let it = b.elemAt pcrelItems i; in it.kind == "insn" && b.elem nm it.args)
      (b.genList (i: i) (b.length pcrelItems));
    in if hits == [ ] then -1 else b.head hits;
  forwardOK = indexOfRef "over" >= 0 && indexOfRef "over" < indexOfLabel "over";
  backwardOK = indexOfRef "back" >= 0 && indexOfRef "back" > indexOfLabel "back";

  # --- the hand-built item list -------------------------------------------
  # No text anywhere: this is what a code generator emits.
  handErrors = b.filter (e: e != null) [
    (if hand.symbols != cases.handBuilt.symbols then
      "hand-built items: symbols are ${b.toJSON hand.symbols}, expected ${b.toJSON cases.handBuilt.symbols}" else null)
    (if hand.textSize != cases.handBuilt.textSize then
      "hand-built items: .text is ${toString hand.textSize} bytes, expected ${toString cases.handBuilt.textSize}" else null)
    (if hand.dataBase != cases.handBuilt.dataBase then
      "hand-built items: .data is based at 0x${asm.toHex hand.dataBase}, expected 0x${asm.toHex cases.handBuilt.dataBase}" else null)
    (if hand.dataSize != cases.handBuilt.dataSize then
      "hand-built items: .data is ${toString hand.dataSize} bytes, expected ${toString cases.handBuilt.dataSize}" else null)
    (
      let
        n = b.length cases.handBuilt.tailBytes;
        got = b.genList (i: b.elemAt hand.text (b.length hand.text - n + i)) n;
      in
      if got != cases.handBuilt.tailBytes then
        "hand-built items: the symbol-valued .words came out as ${toString got}, expected ${toString cases.handBuilt.tailBytes}"
      else null
    )
  ];

  # --- coverage ------------------------------------------------------------
  # A mnemonic the table implements but progs/ never uses is a mnemonic the
  # differential against GNU as has never checked.
  usedMnemonics = b.listToAttrs (b.concatLists (map
    (f: map (w: { name = w.mnemonic; value = true; }) built.${f}.words)
    cases.mnemonicCorpus));
  uncovered = b.filter (m: !(usedMnemonics ? ${m})) asm.mnemonics;

  comparedWords = b.foldl' (a: f: a + b.length built.${f}.words) 0 cases.mnemonicCorpus;
  comparedBytes = b.foldl' (a: f: a + b.length built.${f}.bytes) 0 cases.mnemonicCorpus;
in
# --- floors, first -------------------------------------------------------
if b.length cases.programs < minPrograms then fault "cases.nix lists ${toString (b.length cases.programs)} programs, fewer than the ${toString minPrograms} this check needs"
else if b.length cases.pcrelWords < minPcrelWords then fault "the PC-relative word table has ${toString (b.length cases.pcrelWords)} entries, fewer than ${toString minPcrelWords}"
else if b.length cases.rangeWords < minRangeWords then fault "the branch-range word table has ${toString (b.length cases.rangeWords)} entries, fewer than ${toString minRangeWords}"
else if b.length cases.liCases < minLiCases then fault "the li table has ${toString (b.length cases.liCases)} cases, fewer than ${toString minLiCases}"
else if b.length cases.hiLoCases < minHiLoCases then fault "the hiLo table has ${toString (b.length cases.hiLoCases)} cases, fewer than ${toString minHiLoCases}"
else if b.length cases.symbols < minSymbols then fault "the symbol-address table has ${toString (b.length cases.symbols)} entries, fewer than ${toString minSymbols}"
else if b.length cases.swapWords < minSwapWords then fault "the operand-swap table has ${toString (b.length cases.swapWords)} entries, fewer than ${toString minSwapWords}"
else if b.length cases.handBuilt.items < minHandItems then fault "the hand-built item list has ${toString (b.length cases.handBuilt.items)} items, fewer than ${toString minHandItems}"
else if b.length asm.mnemonics < minMnemonics then fault "the assembler implements ${toString (b.length asm.mnemonics)} mnemonics, fewer than the ${toString minMnemonics} this corpus was written for"
else if missingRequired != [ ] then fault "the li table no longer covers ${toString missingRequired}, which the task names explicitly"

# --- does the corpus still exercise what it claims to --------------------
# These sit with the floors rather than with the verdicts below, and for the
# same reason: they say the CHECK has a hole, not that the assembler is wrong,
# and a verdict from a corpus with a hole is worth less than it reads. They
# also cannot be pre-empted by the verdicts below, which is the ordering rule
# task-002 arrived at -- but the reverse: deleting one instruction from
# progs/pseudo.s moves every address after it, so with these checked last the
# report was a wrong branch encoding rather than "you deleted a case".
else if !forwardOK then throw "assembler: pcrel.s no longer references `over' BEFORE defining it, so nothing here tests a forward reference"
else if !backwardOK then throw "assembler: pcrel.s no longer references `back' AFTER defining it, so nothing here tests a backward reference"
else if uncovered != [ ] then throw "assembler: ${toString (b.length uncovered)} mnemonic(s) are implemented but never assembled by progs/, so the differential has never seen them: ${b.concatStringsSep " " uncovered}"

# --- the assembler's own verdicts ---------------------------------------
# hiLo and liParts come first because they are the smallest units here, and a
# failure in either explains every program-level failure downstream: with the
# +0x800 correction removed, `call' and `la' in pcrel.s come out wrong too,
# and reporting THAT sends the reader to the wrong file.
else if firstError hiLoErrors != null then throw "assembler: ${firstError hiLoErrors}"
else if firstError liErrors != null then throw "assembler: ${firstError liErrors}"
else if pcrelError != null then throw "assembler: ${pcrelError}"
else if rangeError != null then throw "assembler: ${rangeError}"
else if firstError globalErrors != null then throw "assembler: ${firstError globalErrors}"
else if firstError sizeErrors != null then throw "assembler: ${firstError sizeErrors}"
else if firstError swapErrors != null then throw "assembler: ${firstError swapErrors}"
else if firstError handErrors != null then throw "assembler: ${firstError handErrors}"
else if firstError symbolErrors != null then throw "assembler: ${firstError symbolErrors}"
else if firstError layoutErrors != null then throw "assembler: ${firstError layoutErrors}"

# --- did we actually compare anything ------------------------------------
else if b.length wide < 8 then fault "only ${toString (b.length wide)} instructions in progs/ take more than one word, so the length check is nearly vacuous"
else if comparedWords < 100 then fault "only ${toString comparedWords} instruction words were assembled in total"
else if comparedBytes < 8000 then fault "only ${toString comparedBytes} bytes were assembled in total"
else ''
  assembler: ${toString (b.length cases.programs)} programs, ${toString comparedWords} instruction words and ${toString comparedBytes} bytes assembled
  assembler: ${toString (b.length cases.pcrelWords + b.length cases.rangeWords + b.length cases.swapWords)} encodings pinned, ${toString (b.length cases.symbols)} label addresses, ${toString (b.length cases.programs)} section layouts
  assembler: ${toString (b.length cases.liCases)} li expansions and ${toString (b.length cases.hiLoCases)} hiLo splits, covering every value the task names
  assembler: ${toString (b.length asm.mnemonics)} mnemonics implemented, all of them reached by progs/
  assembler: ${toString (b.length sizeReports)} instruction placements agree with what they encoded to, ${toString (b.length wide)} of them longer than one word
  assembler: ${toString (b.length cases.handBuilt.items)} hand-built items assembled with no assembly text involved
''
