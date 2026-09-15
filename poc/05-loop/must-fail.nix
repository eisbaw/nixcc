# Must-fail suite: the paths check.nix cannot reach, because check.nix can
# only look at a demo that assembles and runs.
#
# It is small, and deliberately so rather than by omission. Almost every guard
# in this PoC lives in check.nix, and run.sh's mutation stage already holds
# each of those to its own diagnostic TEXT -- which is the job messages.sh
# does for the other PoCs. What is left over, and what is here, are the throws
# that happen before check.nix has anything to look at: the character table
# that turns a string into .data bytes, and driver.nix's message-layout guard,
# which exists because hello() can only write a WORD at a time (task-024) and
# so the prefix has to be exactly two words and the sum exactly two digits.
#
# Every reject is paired with a CONTROL that must still succeed, and the
# controls sit next to their rejects -- n = 13 beside n = 14, a string of
# printable characters and newlines beside one with a bell in it -- so that a
# control passing is evidence the specific rule fired rather than evidence
# that nothing throws at anything. A driver that threw unconditionally could
# not pass this file.
#
# `expect' is a fragment that must appear in the thrown message. It cannot be
# checked here -- builtins.tryEval returns success and value, never the
# message -- so messages.sh re-evaluates each reject outside Nix and greps.
let
  b = builtins;
  it = import ./items.nix;
  asm = import ../04-assembler/asm.nix { };

  minRejects = 5;
  minControls = 5;

  driver = n: import ./driver.nix { inherit n; };

  # Characters a Nix string can hold but this PoC's .data table has no byte
  # value for. Written as JSON escapes because Nix string syntax has no way to
  # spell them.
  bell = b.fromJSON ''"\u0007"'';
  del = b.fromJSON ''"\u007f"'';

  rejects = [
    {
      what = "a control character the .data table has no byte value for";
      expect = "is not a character this .data table has a byte value for";
      run = it.asciiBytes "must-fail" "ok${bell}";
    }
    {
      what = "DEL, which is past the printable range";
      expect = "extend the table rather than letting it become a zero";
      run = it.chars "must-fail" "ok${del}";
    }
    {
      # n = 9 gives "1..9 = ", seven bytes, and hello() stores its digits at
      # msg[8] onwards.
      what = "a message prefix that is not exactly eight bytes";
      expect = "so the prefix must be exactly 8";
      run = (driver 9).expectedBytes;
    }
    {
      # 1 + ... + 14 = 105. The prefix is still eight bytes, so this reaches
      # the second guard and not the first.
      what = "a vector whose sum needs more than two digits";
      expect = "which is 3 digits; hello() converts exactly two";
      run = (driver 14).expectedBytes;
    }
    {
      # items.nix's constructors are not a second, laxer way into the
      # assembler: a program built out of them is held to the same rules as
      # one parsed from text.
      what = "a program built from items that branches to a symbol nothing defines";
      expect = "which nothing in this unit defines";
      run = (asm.assemble { items = it.program [ (it.insn "j" [ "nowhere" ]) ]; }).words;
    }
  ];

  controls = [
    {
      what = "the demo's own message, which the table does have every byte for";
      run = (driver 10).expectedBytes;
    }
    {
      what = "a string carrying the three control characters the table does hold";
      run = it.asciiBytes "must-fail" "a\tb\nc\r";
    }
    {
      # 1 + ... + 13 = 91: two digits, and "1..13 = " is eight bytes. The
      # layout guard is about the LAYOUT, not about n.
      what = "a different vector that still lays out as eight bytes and two digits";
      run = (driver 13).expectedBytes;
    }
    {
      what = "a program built from items that branches to a symbol it does define";
      run = (asm.assemble { items = it.program [ (it.insn "j" [ "here" ]) (it.label "here") ]; }).words;
    }
    {
      what = "the syscall helpers, which have to assemble like anything else";
      run = (asm.assemble {
        items = it.program ((it.writeCall 1 "buf" 4) ++ it.exitWithA0
          ++ [ (it.section ".data") (it.label "buf") (it.chars "control" "ok!\n") ]);
      }).bytes;
    }
  ];

  # deepSeq, because everything here is lazy: `tryEval (driver 9)` alone
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
      throw "must-fail: these should have been refused but went through fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these should have gone through but threw: ${names wronglyRejected}"
    else
      "loop: ${toString (b.length rejectResults)} reject cases, ${
        toString (b.length controlResults)} control cases\n";
}
