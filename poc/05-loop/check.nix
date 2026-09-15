# The closed loop's verification, in one place so that run.sh and the flake's
# `checks.loop' cannot drift apart. Forcing this either throws with a precise
# message or returns a summary of what was actually measured.
#
# The harness is as much on trial as the loop. This project has shipped four
# tests that reported PASS while measuring nothing, so every table below has a
# floor and an emptied one is a HARNESS FAULT rather than a pass. A review of
# the first version of this file found eleven guards that could be deleted
# without run.sh's mutation stage noticing, and four tables that could be
# EMPTIED while it still returned success -- the same shape, one level up. The
# floors below and the mutations beside them are what that produced; a guard
# with no mutation aimed at it is a guard nobody has seen fail.
#
# Guard ordering, which matters here more than usual because the fault table
# and the demo can fail for the same underlying reason:
#
#   1. The floors on the TABLES, because a verdict from an emptied table is a
#      lie. Note where the floors on the demo's own size are NOT: they sit at
#      the bottom, because a floor on the item count fires before the image is
#      ever forced, and a demo missing a whole unit then reported "fewer items
#      than expected" instead of the assembler's own precise "nothing in this
#      unit defines `__divsi3'". A floor that pre-empts a better diagnostic is
#      in the wrong place.
#   2. The IMAGE: entry point, layout, the symbols that must exist, and a
#      byte-for-byte comparison of the loaded machine's RAM against what the
#      assembler produced. Everything below reads a number out of a machine
#      that ran this image, so if the image is wrong the numbers are about the
#      wrong program.
#   3. The CONTROLS, before the faults. A machine that faults at everything
#      passes the fault table outright, and reporting a fault case when the
#      truth is "nothing runs any more" sends the reader to the wrong file.
#   4. The faults, then the demo, then the branch resolution.
#   5. Last, the "did we actually run anything" arithmetic.
{ cpu
, matcher ? ../03-matcher
, assembler ? ../04-assembler
, ir ? ./hello.sym
}:
let
  b = builtins;
  cases = import ./cases.nix;
  demo = import ./demo.nix {
    inherit cpu matcher assembler ir;
    inherit (cases) base ramSize;
  };
  inherit (demo) asm image report driver;

  # Floors, not targets. Raise them if the tables legitimately grow.
  minFaults = 10;
  minControls = 12;
  minReasons = 10;
  minRequiredSymbols = 10;
  minDemoSymbols = 3;
  minItems = 120;
  minImageBytes = 500;
  minBranches = 10;

  fault = msg: throw "HARNESS FAULT: ${msg}";
  firstError = errs:
    if errs == [ ] then null
    else b.head errs + (if b.length errs == 1 then "" else " (and ${toString (b.length errs - 1)} more)");

  # The stdout rendering for a message or a summary line: rv32.report turns
  # byte 10 back into a real newline, which would break the line it is
  # reported on.
  visible = t: b.replaceStrings [ "\n" "\t" "\r" ] [ "\\n" "\\t" "\\r" ] t;

  # --- running the tables ---------------------------------------------------
  # Through demo.nix's own runner, so a fault program goes through the same
  # assembler and the same emulator as the demo. A fault case assembled by a
  # different route would say nothing about either. The budget is the case
  # table's, never the runner's: `runItems' has no default for it.
  ran = c: demo.runItems {
    faultItems = c.items;
    limit = c.limit or cases.faultLimit;
  };

  faultResults = map (c: c // { got = (ran c).report; }) cases.faults;
  controlResults = map (c: c // { got = (ran c).report; }) cases.controls;

  faultErrors = b.filter (e: e != null) (map
    (r:
      if r.got.reason == r.reason then null
      else if r.got.reason == "exit" then
        "`${r.what}' ran to a CLEAN EXIT with status ${toString r.got.exitCode}; rv32 should have reported ${r.reason}"
      else "`${r.what}' halted with reason ${r.got.reason}, expected ${r.reason}")
    faultResults);

  # Every control pins its stdout as well as its status -- the ones that write
  # and the ones that must not -- because a control that spuriously printed
  # something is exactly what a control table exists to notice. Unconditional,
  # not `r ? stdoutBytes': the conditional form went vacuous for eight of
  # eleven controls and a control that spuriously wrote four bytes passed.
  controlsMissingPin = b.filter (c: !(c ? stdoutBytes)) cases.controls;

  controlErrors = b.filter (e: e != null) (map
    (r:
      if r.got.reason != "exit" then
        "control `${r.what}' halted with reason ${r.got.reason}; it is the case that must still RUN, so the fault beside it proves nothing"
      else if r.got.exitCode != r.exitCode then
        "control `${r.what}' exited ${toString r.got.exitCode}, expected ${toString r.exitCode}"
      else if r.got.stdoutBytes != r.stdoutBytes then
        "control `${r.what}' wrote ${toString r.got.stdoutBytes}, expected ${toString r.stdoutBytes}"
      else null)
    controlResults);

  reasonsSeen = map (r: r.reason) cases.faults;
  missingReasons = b.filter (r: !(b.elem r reasonsSeen)) cases.requiredReasons;

  # --- the image ------------------------------------------------------------
  # THE WHOLE IMAGE, not a spot check. An earlier version compared the first
  # WORD of the loaded machine against the first word of `image.bytes', which
  # let a byte tampered with at offset 400 -- inside a real instruction --
  # through, and let a byte appended to the image through as well. So: every
  # byte of RAM against every byte of the image, and the SIZE of the machine's
  # memory against the length of the image, which is what catches an append
  # (RAM reads as zero where nothing was loaded, so a trailing zero is
  # invisible to a value comparison).
  loadedBytes = b.filter
    (i: cpu.readByte demo.loaded (cases.base + i) != b.elemAt image.bytes i)
    (b.genList (i: i) (b.length image.bytes));
  loadedCount = b.length (b.attrNames demo.loaded.memory);

  symbolErrors = b.filter (e: e != null) (map
    (nm:
      let
        want = cases.demo.symbols.${nm};
        got = image.symbols.${nm} or null;
      in
      if got == null then "the image defines no symbol `${nm}'"
      else if got != want then "`${nm}' is at 0x${asm.toHex got}, expected 0x${asm.toHex want}"
      else null)
    (b.attrNames cases.demo.symbols));

  # Separate from the address pins above, and about a different thing: that
  # every unit the demo is composed of is actually in it, WHOLE.
  #
  # Dropping poc/03-matcher/runtime.s outright does not get this far -- the
  # assembler refuses `call __divsi3' first, with a better message, and that
  # is why the item-count floor was moved out of the way of it. What this
  # catches is the subtler version: a runtime trimmed to the two functions the
  # demo happens to call. `__mulsi3', `h' and `g' are in runtime.s and nothing
  # in the demo references them, so they are exactly the symbols that would
  # vanish silently.
  missingSymbols = b.filter (nm: !(image.symbols ? ${nm})) cases.requiredSymbols;

  imageErrors = b.filter (e: e != null) [
    (if image.symbols._start or null != image.textBase then
      "`_start' is at 0x${asm.toHex (image.symbols._start or 0)} but the image is entered at 0x${asm.toHex image.textBase}; the entry point is not the entry point"
    else null)
    (if demo.loaded.pc != (image.symbols._start or 0) then
      "the machine was entered at 0x${asm.toHex demo.loaded.pc}, but `_start' is at 0x${asm.toHex (image.symbols._start or 0)}"
    else null)
    (if missingSymbols != [ ] then
      "the demo's image defines no `${b.head missingSymbols}', which it must: every unit the demo is composed of has to be in it"
    else null)
    (if loadedCount != b.length image.bytes then
      "the loaded machine holds ${toString loadedCount} bytes of RAM but the assembler produced an image of ${toString (b.length image.bytes)}; the emulator was not handed the image we assembled"
    else null)
    (if loadedBytes != [ ] then
      "the machine's memory differs from the assembled image at byte ${toString (b.head loadedBytes)} of ${toString (b.length image.bytes)}"
      + (if b.length loadedBytes == 1 then "" else " (and ${toString (b.length loadedBytes - 1)} more)")
    else null)
    (
      let a = image.symbols.msg or null; in
      if a == null then "the image defines no `msg' buffer"
      else if a - (a / 4) * 4 != 0 then
        "`msg' is at 0x${asm.toHex a}, which is not word-aligned, and hello() stores its digits there with `sw'"
      else null
    )
  ];

  # --- the demo -------------------------------------------------------------
  demoErrors = b.filter (e: e != null) [
    (if report.reason != cases.demo.reason then
      "the demo halted with reason ${report.reason}, expected ${cases.demo.reason}" else null)
    (if report.exitCode != cases.demo.exitCode then
      "the demo exited ${toString report.exitCode}, expected ${toString cases.demo.exitCode}; hello() returns 0 only when write() reported all ${toString driver.writeCount} bytes"
    else null)
    (if report.stdoutBytes != driver.expectedBytes then
      "the demo wrote `${visible report.stdout}', expected `${visible driver.expectedStdout}' -- as bytes, ${toString report.stdoutBytes} against ${toString driver.expectedBytes}"
    else null)
    # Nearly, but not quite, implied by the byte comparison above: the two
    # sides of THIS one are rendered through different tables -- rv32.nix's
    # `byteText' and items.nix's `codeOf' -- so the only thing it can catch is
    # those two drifting apart. Kept for that, and said so rather than left to
    # read as a second opinion on the bytes.
    (if report.stdout != driver.expectedStdout then
      "the demo printed `${visible report.stdout}', expected `${visible driver.expectedStdout}'; the byte lists agree, so items.nix's character table and rv32.nix's have drifted apart"
    else null)
    (if report.steps < cases.demo.minSteps then
      "the demo halted after ${toString report.steps} steps, fewer than the ${toString cases.demo.minSteps} this program takes; it cannot have run"
    else null)
  ];

  # --- branches resolved from the symbol table ------------------------------
  # Criterion: a branch's distance must come from the symbol table and not
  # from a human counting instructions. The check is stronger than "a label
  # was used": for every branch and jump in the demo, the distance the SYMBOL
  # TABLE implies is decoded back out of the assembled WORD. If the two agree
  # for a forward reference and for a backward one, the label layer resolved
  # them -- and the immediate in the instruction is the proof, because it is
  # the only number the machine actually branches on.
  pow2 = n: b.foldl' (a: _: a * 2) 1 (b.genList (i: i) n);
  # Nix has no shift and no mask beyond bitAnd, so a bit field is a divide and
  # a truncating remainder. Values here are non-negative 32-bit words.
  field = x: lo: width: let q = x / pow2 lo; in q - (q / pow2 width) * pow2 width;
  sext = width: x: if x >= pow2 (width - 1) then x - pow2 width else x;

  # The immediate a B-type or J-type word really carries, decoded the same way
  # rv32.nix decodes it.
  encodedOffset = w:
    let op = field w 0 7; in
    if op == 99 then
      sext 13 (field w 8 4 * 2 + field w 25 6 * 32 + field w 7 1 * 2048 + field w 31 1 * 4096)
    else if op == 111 then
      sext 21 (field w 21 10 * 2 + field w 20 1 * 2048 + field w 12 8 * 4096 + field w 31 1 * 1048576)
    else null;

  # Which operands of a mnemonic are branch targets comes from the assembler's
  # own operand-kind table, not from a list kept here that could drift. Both
  # lookups throw rather than answering "no branch targets": neither can fire
  # today, because asm.nix refuses an unknown mnemonic and a bad arity long
  # before this file sees a placement -- which is exactly the argument for not
  # writing the answer that would be a lie if one ever did.
  targetsOf = item:
    let
      alts = asm.operandShapes.${item.mnemonic}
        or (fault "the assembler has no operand shape for `${item.mnemonic}', so this cannot tell which of its operands are branch targets");
      hit = b.filter (o: b.length o == b.length item.args) alts;
    in
    if hit == [ ] then
      fault "no operand shape of `${item.mnemonic}' takes ${toString (b.length item.args)} operands, so this cannot tell which of them are branch targets"
    else
      let ops = b.head hit; in
      b.filter (x: x != null) (b.genList
        (i: if b.elemAt ops i == "l" then b.elemAt item.args i else null)
        (b.length ops));

  # asm.nix exports the instruction WORD beside its hex rendering, so nothing
  # here has to undo toHex to decode a field.
  wordAt = addr:
    let hits = b.filter (w: w.addr == addr) image.words; in
    if hits == [ ] then null else (b.head hits).word;

  branches = b.concatLists (map
    (pl:
      if pl.item.kind != "insn" then [ ]
      else map
        (t: {
          from = pl.addr;
          target = t;
          to = image.symbols.${t};
          delta = image.symbols.${t} - pl.addr;
          encoded = encodedOffset (wordAt pl.addr);
          inherit (pl.item) mnemonic;
        })
        (targetsOf pl.item))
    image.placements);

  inCompiled = br:
    b.substring 0 (b.stringLength cases.demo.labelPrefix) br.target == cases.demo.labelPrefix;
  compiledBranches = b.filter inCompiled branches;
  forward = b.filter (br: br.delta > 0) compiledBranches;
  backward = b.filter (br: br.delta < 0) compiledBranches;

  # If the symbol table and the encoded immediate disagree, one of them was
  # hand-computed. Checked over EVERY branch in the image, not only the
  # compiled ones, because the driver and the runtime go through the same
  # layer.
  offsetErrors = map
    (br: "`${br.mnemonic}' at 0x${asm.toHex br.from} branches to `${br.target}' at 0x${asm.toHex br.to}, "
      + "which the symbol table puts ${toString br.delta} bytes away, but the assembled word encodes ${toString br.encoded}")
    (b.filter (br: br.encoded != br.delta) branches);
in
# --- floors, first ---------------------------------------------------------
if b.length cases.faults < minFaults then fault "the fault table has ${toString (b.length cases.faults)} programs, fewer than ${toString minFaults}"
else if b.length cases.controls < minControls then fault "the control table has ${toString (b.length cases.controls)} programs, fewer than ${toString minControls}"
else if controlsMissingPin != [ ] then fault "control `${(b.head controlsMissingPin).what}' pins no stdout, so nothing would notice if it started writing"
else if b.length cases.requiredReasons < minReasons then fault "the required-fault-classification list has ${toString (b.length cases.requiredReasons)} entries, fewer than ${toString minReasons}"
else if missingReasons != [ ] then fault "the fault table no longer covers ${b.concatStringsSep ", " missingReasons}"
else if b.length cases.requiredSymbols < minRequiredSymbols then fault "the required-symbol list has ${toString (b.length cases.requiredSymbols)} entries, fewer than ${toString minRequiredSymbols}"
else if b.length (b.attrNames cases.demo.symbols) < minDemoSymbols then fault "the demo's address table has ${toString (b.length (b.attrNames cases.demo.symbols))} entries, fewer than ${toString minDemoSymbols}"
else if cases.demo.minCompiledBranches < 1 then fault "the compiled-branch floor is ${toString cases.demo.minCompiledBranches}, which no image can fall below"

# --- the image the numbers below are about ---------------------------------
else if firstError imageErrors != null then throw "loop: ${firstError imageErrors}"
else if firstError symbolErrors != null then throw "loop: ${firstError symbolErrors}"

# --- controls before faults ------------------------------------------------
else if firstError controlErrors != null then throw "loop: ${firstError controlErrors}"
else if firstError faultErrors != null then throw "loop: ${firstError faultErrors}"

# --- the demo --------------------------------------------------------------
else if firstError demoErrors != null then throw "loop: ${firstError demoErrors}"

# --- the label layer -------------------------------------------------------
else if firstError offsetErrors != null then throw "loop: ${firstError offsetErrors}"
else if b.length compiledBranches < cases.demo.minCompiledBranches then
  fault "the compiled function has ${toString (b.length compiledBranches)} branches to its own labels, fewer than ${toString cases.demo.minCompiledBranches}; nothing here tests the label layer any more"
else if forward == [ ] then throw "loop: no branch in the compiled function goes FORWARD to a label defined later, so nothing shows a forward reference was resolved from the symbol table"
else if backward == [ ] then throw "loop: no branch in the compiled function goes BACKWARD, so nothing shows a backward reference was resolved from the symbol table"

# --- did we actually compare anything --------------------------------------
else if b.length branches < minBranches then fault "only ${toString (b.length branches)} branches in the whole image were checked against the symbol table, fewer than ${toString minBranches}"
else if b.length demo.items < minItems then fault "the demo is ${toString (b.length demo.items)} items, fewer than the ${toString minItems} a compiled function plus a driver and a runtime comes to"
else if b.length image.bytes < minImageBytes then fault "the demo image is ${toString (b.length image.bytes)} bytes, fewer than ${toString minImageBytes}"
else ''
  loop: ${toString (b.length demo.items)} items, ${toString (b.length image.bytes)} bytes, assembled and executed in this evaluation
  loop: every byte of the machine's RAM is the byte the assembler put there
  loop: the demo ran ${toString report.steps} instructions, wrote ${toString (b.length report.stdoutBytes)} bytes and exited ${toString report.exitCode} through the exit syscall
  loop: its output was "${visible report.stdout}", computed by compiled C and carried out by the write syscall
  loop: ${toString (b.length branches)} branch offsets agree with the symbol table, ${toString (b.length forward)} forward and ${toString (b.length backward)} backward inside the compiled function
  loop: ${toString (b.length cases.faults)} malformed programs each halted with their own reported fault, covering ${toString (b.length cases.requiredReasons)} classifications
  loop: ${toString (b.length cases.controls)} control programs still ran to a clean exit with their output pinned
''
