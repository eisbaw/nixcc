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
  # the newline. The byte after them is a NUL, and a Nix string cannot hold
  # one (decision-001), which is why this pin is a byte LIST and the
  # printable rendering beside it is only a convenience.
  expectedBytes = it.asciiBytes "expected stdout" expectedStdout;
  writeBytes = b.length expectedBytes;

  # hello() writes its digits at msg[8], msg[9] and msg[10], which are
  # literal indices in the C, so the prefix must be exactly 8 bytes long and
  # the total exactly two digits. Those are the C's assumptions about this
  # data, not a matter of taste, and neither is left to a reader noticing:
  # change `n' and this says what broke.
  #
  # Note what this guard NO LONGER says. It used to be about word packing --
  # hello() could only store a whole word, so the prefix had to be exactly
  # two of them. The indices are byte indices now (task-024); 8 is still 8,
  # for a different and much duller reason.
  #
  # The buffer length is checked too. hello() writes msg[10] and asks write()
  # for 11 bytes, so a tail shortened by one would run off the end of the
  # buffer into whatever follows in .data -- today nothing, so RAM reads zero,
  # stdout gets an invisible NUL and the failure surfaces as a byte mismatch
  # pointing at the wrong layer.
  msgBytes = b.stringLength prefix + 4;
  #
  # ORDER MATTERS. The buffer check comes LAST because a sum that needs three
  # digits also overflows the buffer, and "the vector sums to 105" is the
  # diagnosis while "the buffer is one byte short" is its consequence.
  layoutError =
    if b.stringLength prefix != 8 then
      "driver: the message prefix `${prefix}' is ${toString (b.stringLength prefix)} bytes, but hello() writes its digits at msg[8] onwards, so the prefix must be exactly 8"
    else if b.stringLength digits != 2 then
      "driver: the vector sums to ${digits}, which is ${toString (b.stringLength digits)} digits; hello() converts exactly two"
    else if msgBytes < writeBytes + 1 then
      "driver: the message buffer is ${toString msgBytes} bytes, but hello() writes ${toString writeBytes} and needs one more for the NUL it never writes out"
    else null;

  result = {
    inherit vector prefix digits expectedStdout expectedBytes;
    writeCount = writeBytes;

    items = it.program [
      (it.insn "la" [ "a0" "vec" ])
      (it.insn "li" [ "a1" n ])
      (it.insn "call" [ "hello" ])
      # hello()'s return value is already in a0, which is exit()'s status.
      # It is a literal 0 now that hello() discards write()'s answer
      # (task-025), so the exit status says only that the function returned;
      # what it PRINTED is the thing check.nix leans on.
      (it.insn "li" [ "a7" it.sysExit ])
      (it.insn "ecall" [ ])

      # write(fd, buf, count). The C prototype is `int wr(int, char *, int)',
      # so a0, a1 and a2 already hold the arguments and a0 already takes the
      # result; the whole function is the syscall number and the trap. The
      # result is what hello() now discards (task-025), which is why the
      # demo's exit status no longer carries it -- see check.nix.
      (it.global "wr")
      (it.label "wr")
      (it.insn "li" [ "a7" it.sysWrite ])
      (it.insn "ecall" [ ])
      (it.insn "ret" [ ])

      (it.section ".data")
      # `vec' MUST be word-aligned: hello() reads it with `lw', and a
      # misaligned load is a fault in rv32.nix, not a slow path.
      (it.align 2)
      (it.label "vec")
      (it.words vector)
      # `msg' needs no alignment at all, and that is task-024 showing: hello()
      # fills it with `sb', one byte at a time, which has no alignment rule.
      # It lands word-aligned anyway, because `vec' is a whole number of
      # words -- but nothing requires it to and nothing checks it.
      (it.label "msg")
      (it.chars "message prefix" prefix)
      # Four spare bytes: two digits, a newline, and a NUL that is never
      # written out. Two of the three digits land at addresses 1 and 2 modulo
      # four, which is the interesting case for `sb' and free coverage that
      # nothing else arranges -- it would evaporate if the prefix length
      # changed.
      (it.bytes [ 0 0 0 0 ])
    ];
  };
in
if layoutError != null then throw layoutError else result
