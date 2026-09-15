# Must-fail suite: the paths check.nix cannot reach, because check.nix can
# only look at input the assembler handles.
#
# Every reject is paired with a CONTROL that must still succeed, and the
# controls sit next to their rejects -- a branch at exactly -4096 beside one at
# -4100, a `.align 4' beside a `.align 5' -- so that a control passing is
# evidence the specific rule fired rather than evidence that the assembler
# merely does not throw at everything. An assembler that threw unconditionally
# could not pass this file.
#
# `expect' is a fragment that must appear in the thrown message. It cannot be
# checked here -- builtins.tryEval returns success and value, never the message
# -- so messages.sh re-evaluates each reject outside Nix and greps. Without
# that step, an assembler whose every diagnostic read "error" would pass a file
# whose whole subject is refusing to emit wrong code.
let
  b = builtins;
  asm = import ./asm.nix { };
  parse = import ./parse.nix { inherit asm; };

  minRejects = 20;
  minControls = 12;

  # Forcing `words' rather than the whole result keeps the 1 MiB `.zero' in the
  # jump-range cases from ever being expanded into a byte list: placement needs
  # its SIZE, and only the image needs its contents.
  words = items: (asm.assemble { inherit items; }).words;
  image = items: (asm.assemble { inherit items; }).bytes;
  text = s: parse.parse "must-fail" s;

  insn = mnemonic: args: { kind = "insn"; inherit mnemonic args; };
  label = name: { kind = "label"; inherit name; };
  gap = count: { kind = "zero"; inherit count; };

  # A branch `d' bytes from its own address, built so that d is exactly what
  # it says: the branch is item 0 at offset 0, so the target label must sit at
  # offset d. Negative distances put the label first.
  branchAt = d:
    if d >= 0 then [ (insn "beq" [ "a0" "a1" "far" ]) (gap (d - 4)) (label "far") ]
    else [ (label "far") (gap (0 - d)) (insn "beq" [ "a0" "a1" "far" ]) ];
  jumpAt = d:
    if d >= 0 then [ (insn "j" [ "far" ]) (gap (d - 4)) (label "far") ]
    else [ (label "far") (gap (0 - d)) (insn "j" [ "far" ]) ];

  rejects = [
    # --- the range decision, which is to REFUSE rather than relax ----------
    {
      what = "a branch four bytes past the forward limit";
      expect = "a B-type offset must be in [-4096, 4094]";
      run = words (branchAt 4096);
    }
    {
      what = "a branch four bytes past the backward limit";
      expect = "Invert the branch and jump over a `j' instead";
      run = words (branchAt (-4100));
    }
    {
      what = "a jump past the forward limit of a J-type offset";
      expect = "a J-type offset must be in [-1048576, 1048574]";
      run = words (jumpAt 1048576);
    }
    {
      what = "a jump past the backward limit of a J-type offset";
      expect = "Use `call', which is an auipc/jalr pair";
      run = words (jumpAt (-1048580));
    }

    # --- symbols ----------------------------------------------------------
    {
      what = "a call to a symbol nothing in the unit defines";
      expect = "which nothing in this unit defines";
      run = words [ (insn "call" [ "nosuchfunction" ]) ];
    }
    {
      what = "a branch to a symbol nothing in the unit defines";
      expect = "branches to `nowhere'";
      run = words [ (insn "beq" [ "a0" "a1" "nowhere" ]) ];
    }
    {
      what = "the same label defined twice";
      expect = "is defined more than once";
      run = words [ (label "twice") (insn "nop" [ ]) (label "twice") (insn "ret" [ ]) ];
    }
    {
      what = "`1f' with no `1:' after it";
      expect = "there is no `1:' after it";
      run = words [ (label "1") (insn "j" [ "1f" ]) ];
    }
    {
      what = "`2b' with no `2:' before it";
      expect = "there is no `2:' before it";
      run = words [ (insn "j" [ "2b" ]) (label "2") ];
    }

    # --- item and operand shapes -----------------------------------------
    {
      what = "a mnemonic the table does not implement";
      expect = "unknown mnemonic `mul'";
      run = words [ (insn "mul" [ "a0" "a1" "a2" ]) ];
    }
    {
      what = "too few operands";
      expect = "`beq' takes 3 operand(s), given 2";
      run = words [ (insn "beq" [ "a0" "a1" ]) ];
    }
    {
      what = "a symbol where an immediate belongs";
      expect = "must be an integer immediate";
      run = words [ (label "x") (insn "addi" [ "a0" "a0" "x" ]) ];
    }
    {
      what = "an immediate where a memory operand belongs";
      expect = "must be a memory operand { base, disp }";
      run = words [ (insn "lw" [ "a0" 4 ]) ];
    }
    {
      what = "an item whose kind is not one of the five";
      expect = "unknown item kind `directive'";
      run = words [ { kind = "directive"; name = ".text"; } ];
    }
    {
      what = "a section this assembler does not lay out";
      expect = "lays out .text and .data only";
      run = words [ { kind = "section"; name = ".rodata"; } (insn "nop" [ ]) ];
    }

    # --- alignment --------------------------------------------------------
    {
      what = ".align beyond what a 16-byte section base can honour";
      expect = "can only honour up to .align 4";
      run = words [ (insn "nop" [ ]) { kind = "align"; pow = 5; } (insn "ret" [ ]) ];
    }
    {
      what = "an instruction that would land on an odd address";
      expect = "which is not a multiple of four";
      run = image [ { kind = "bytes"; width = 1; values = [ 1 ]; } (insn "nop" [ ]) ];
    }
    {
      what = "a text base that is not 16-byte aligned";
      expect = "is not 16-byte aligned";
      run = (asm.assemble { items = [ (insn "nop" [ ]) ]; textBase = 65540; }).bytes;
    }
    {
      what = "a symbol's address squeezed into a .byte";
      expect = "a symbol's address needs four bytes";
      run = image [ (label "x") { kind = "bytes"; width = 1; values = [ "x" ]; } ];
    }

    # --- the encoder still gets to refuse its own fields -------------------
    {
      what = "a shift amount RV32 has no field for";
      expect = "shamt: immediate 32 out of range";
      run = words [ (insn "slli" [ "a0" "a1" 32 ]) ];
    }

    # --- the text front end ----------------------------------------------
    {
      what = "a directive parse.nix does not implement";
      expect = "refuses directives rather than dropping them";
      run = text "\t.comm buf,16\n";
    }
    {
      what = "a block comment that is never closed";
      expect = "unterminated /* comment";
      run = text "\t.text\n/* and then nothing\n\tnop\n";
    }
    {
      what = "a memory operand that is not disp(base)";
      expect = "is not a memory operand of the form disp(base)";
      run = text "\tlw\ta0,sp\n";
    }
    {
      what = "a line that is neither a label, a directive nor an instruction";
      expect = "cannot make sense of";
      run = text "\t%%%\n";
    }
  ];

  controls = [
    # Each of these sits beside a reject above and must still succeed, or the
    # reject beside it proves nothing.
    { what = "a branch at exactly the forward limit"; run = words (branchAt 4094); }
    { what = "a branch at exactly the backward limit"; run = words (branchAt (-4096)); }
    { what = "a jump at exactly the forward limit"; run = words (jumpAt 1048574); }
    { what = "a jump at exactly the backward limit"; run = words (jumpAt (-1048576)); }
    {
      what = "a call to a symbol this unit does define";
      run = words [ (label "here") (insn "call" [ "here" ]) ];
    }
    {
      # A numeric label MAY be defined many times -- that is the whole point
      # of numeric labels -- so the duplicate-label refusal must not catch it.
      what = "the same NUMERIC label defined twice, with 1f and 1b resolving either way";
      run = words [ (label "1") (insn "j" [ "1f" ]) (label "1") (insn "j" [ "1b" ]) ];
    }
    { what = ".align 4, the widest a 16-byte section base honours"; run = words [ (insn "nop" [ ]) { kind = "align"; pow = 4; } (insn "ret" [ ]) ]; }
    {
      what = "a byte of data followed by an .align that puts the next instruction back on a word";
      run = image [ { kind = "bytes"; width = 1; values = [ 1 ]; } { kind = "align"; pow = 2; } (insn "nop" [ ]) ];
    }
    { what = "a text base that is 16-byte aligned"; run = (asm.assemble { items = [ (insn "nop" [ ]) ]; textBase = 65552; }).bytes; }
    { what = "a symbol's address in a .word, which is wide enough"; run = image [ (label "x") { kind = "bytes"; width = 4; values = [ "x" ]; } ]; }
    { what = "the largest shift amount RV32 does have a field for"; run = words [ (insn "slli" [ "a0" "a1" 31 ]) ]; }
    { what = "a directive parse.nix does implement"; run = text "\t.globl buf\n"; }
    { what = "a block comment that is closed"; run = text "\t.text\n/* and then this */\n\tnop\n"; }
    { what = "a memory operand that is disp(base)"; run = text "\tlw\ta0,-4(sp)\n"; }
    { what = "li at both sides of the 12-bit boundary"; run = [ (asm.liWords "a0" 2047) (asm.liWords "a0" 2048) ]; }
    {
      what = "a forward reference defined later in the same unit";
      run = words [ (insn "beq" [ "a0" "a1" "later" ]) (insn "nop" [ ]) (label "later") (insn "ret" [ ]) ];
    }
    { what = "`jal target', the one-operand spelling"; run = words [ (label "t") (insn "jal" [ "t" ]) ]; }
  ];

  # deepSeq, because everything here is lazy: `tryEval (assemble ...)` alone
  # reports success for an input whose error is still an unforced thunk.
  survives = c: (b.tryEval (b.deepSeq c.run true)).success;

  rejectResults = map (c: { inherit (c) what; accepted = survives c; }) rejects;
  controlResults = map (c: { inherit (c) what; ok = survives c; }) controls;

  wronglyAccepted = b.filter (r: r.accepted) rejectResults;
  wronglyRejected = b.filter (r: !r.ok) controlResults;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  # messages.sh reads this to check the thrown text, which Nix cannot see.
  inherit rejects;

  summary =
    if b.length rejectResults < minRejects || b.length controlResults < minControls then
      throw "HARNESS FAULT: must-fail tables shrank to ${toString (b.length rejectResults)} rejects and ${
        toString (b.length controlResults)} controls"
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been refused but assembled fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these should have assembled but threw: ${names wronglyRejected}"
    else
      "must-fail: ${toString (b.length rejectResults)} reject cases, ${
        toString (b.length controlResults)} control cases\n";
}
