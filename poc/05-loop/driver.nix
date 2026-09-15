# The demo's driver and its data, as assembler ITEMS.
#
# Not as assembly text, and deliberately: asm.nix consumes items, and a
# single-eval compiler has no reason to round-trip through a .s file. Every
# byte the demo runs that was not compiled from C is built here, in Nix, as
# data -- the entry point, the write() stub, the exit() call, the vector and
# the message buffer.
#
# What is NOT here is the multiply/divide runtime. poc/03-matcher/runtime.s is
# the only copy of __divsi3 and __modsi3 in the tree, and demo.nix reads it
# through the assembler's text front end rather than keeping a hand-translated
# second one that could drift from the copy poc/03-matcher and poc/04-assembler
# differential-test against. That file's own header is clear that it is a stub
# and that the real runtime library is task-007; this demo inherits that.
#
# `n' is an argument only so that must-fail.nix can drive the layout guard at
# the bottom of this file off its ends. The demo uses the default.
{ n ? 10 }:
let
  b = builtins;
  it = import ./items.nix;

  # --- what the demo computes ----------------------------------------------
  # THE VECTOR IS THE ONE FACT HERE. The prefix names it and the digits are
  # its sum, both DERIVED: a hand-written "1..10 = 55" sitting beside a vector
  # that had changed would make the program's own correct output read as a
  # compiler bug, and the failure message would still say 1..10.
  #
  # `vector' is 1..n by construction, which is what lets the prefix name it.
  vector = b.genList (i: i + 1) n;
  total = b.foldl' (a: x: a + x) 0 vector;
  prefix = "1..${toString n} = ";
  digits = toString total;
  expectedStdout = prefix + digits + "\n";

  # What hello() is told to write: the prefix, the two digits it computed and
  # the newline -- three of the four bytes it packed into the buffer's third
  # word. The fourth is a NUL, and a Nix string cannot hold one
  # (decision-001), which is why this pin is a byte LIST and the printable
  # rendering beside it is only a convenience.
  expectedBytes = it.asciiBytes "expected stdout" expectedStdout;

  # hello() packs two digits, a newline and a NUL into ONE word and stores it
  # at out[2], so the prefix must be exactly two words and the total exactly
  # two digits. Both follow from there being no byte store in the matcher's
  # rule table yet (task-024), so neither is a matter of taste and neither is
  # left to a reader noticing: change `n' and this says what broke.
  layoutError =
    if b.stringLength prefix != 8 then
      "driver: the message prefix `${prefix}' is ${toString (b.stringLength prefix)} bytes, but hello() writes its digits into the buffer's THIRD WORD, so the prefix must be exactly 8"
    else if b.stringLength digits != 2 then
      "driver: the vector sums to ${digits}, which is ${toString (b.stringLength digits)} digits; hello() converts exactly two"
    else null;

  result = {
    inherit vector prefix digits expectedStdout expectedBytes;
    writeCount = b.length expectedBytes;

    items = it.program [
      (it.insn "la" [ "a0" "vec" ])
      (it.insn "li" [ "a1" n ])
      (it.insn "la" [ "a2" "msg" ])
      (it.insn "call" [ "hello" ])
      # hello()'s return value is already in a0, which is exit()'s status: the
      # demo exits 0 exactly when the write syscall reported every byte
      # written.
      (it.insn "li" [ "a7" it.sysExit ])
      (it.insn "ecall" [ ])

      # write(fd, buf, count). The C prototype is `int wr(int, int *, int)',
      # so a0, a1 and a2 already hold the arguments and a0 already takes the
      # result; the whole function is the syscall number and the trap.
      (it.global "wr")
      (it.label "wr")
      (it.insn "li" [ "a7" it.sysWrite ])
      (it.insn "ecall" [ ])
      (it.insn "ret" [ ])

      (it.section ".data")
      (it.align 2)
      (it.label "vec")
      (it.words vector)
      # `msg' must be word-aligned: hello() stores its digits with `sw', and a
      # misaligned store is a fault in rv32.nix, not a slow path.
      (it.align 2)
      (it.label "msg")
      (it.chars "message prefix" prefix)
      # The word hello() fills in: two digits, a newline, and a NUL that is
      # never written out.
      (it.words [ 0 ])
    ];
  };
in
if layoutError != null then throw layoutError else result
