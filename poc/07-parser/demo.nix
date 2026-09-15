# The loop closed from .c rather than from .sym.
#
#   run/*.c  --poc/02-lexer------>  tokens
#            --poc/07-parser----->  the DAG, as lcc's symbolic listing
#            --poc/03-matcher---->  RV32 assembly, one function at a time
#            --poc/04-assembler->   items -> bytes
#            --nix-riscv-------->   a running RV32I machine, stdout, exit code
#
# EVERY arrow is inside one `nix eval'. poc/05-loop's demo.nix has the same
# picture with the first two arrows replaced by "lcc, outside", and that was
# the gap decision-007 set out to close for the integer subset. It is closed
# here for these three programs and NOT for poc/05-loop/hello.c, which uses a
# global char array and a pointer parameter -- slices 2 and 3.
#
# The driver is assembly for the same reason it is in poc/05-loop: the RV32
# Linux syscall ABI is target knowledge that no C program can express. What is
# different is how little of it there is. wc() writes ONE character, which is
# the smallest primitive that lets a program in the int-only subset produce
# visible output at all: with no array and no pointer there is nothing to point
# a write(2) at except a one-byte buffer the driver owns.
{ cpu
, source
, matcher ? ../03-matcher
, assembler ? ../04-assembler
, entry ? "run"
, arg ? 10
, base ? 65536
, ramSize ? 1048576
, stepLimit ? 2000000
}:
let
  b = builtins;

  asm = import (assembler + "/asm.nix") { };
  parse = import (assembler + "/parse.nix") { inherit asm; };
  emit = import (matcher + "/emit.nix") { };
  irParse = import (matcher + "/parse.nix");
  cc = import ./compile.nix;
  it = import ../05-loop/items.nix;

  listing = cc.listingOf (b.readFile source);
  functions = irParse.parseAll listing;
  compiled = map emit.compile functions;

  driver = it.program [
    (it.insn "li" [ "a0" arg ])
    (it.insn "call" [ entry ])
    (it.insn "li" [ "a7" it.sysExit ])
    (it.insn "ecall" [ ])

    # wc(ch): store the low byte of a0 into a one-byte buffer and write(1,...).
    # The C prototype is `int wc(int)', so a0 already holds the character and
    # a0 already takes the result.
    (it.global "wc")
    (it.label "wc")
    (it.insn "la" [ "a1" "ch" ])
    (it.insn "sb" [ "a0" { base = "a1"; disp = 0; } ])
    (it.insn "li" [ "a0" 1 ])
    (it.insn "li" [ "a2" 1 ])
    (it.insn "li" [ "a7" it.sysWrite ])
    (it.insn "ecall" [ ])
    (it.insn "ret" [ ])

    (it.section ".data")
    (it.label "ch")
    (it.bytes [ 0 ])
  ];

  items = driver
    ++ b.concatLists (b.genList
      (i: parse.parse "${b.baseNameOf source}#${toString i}" (b.elemAt compiled i).asm)
      (b.length compiled))
    ++ parse.parseFile (matcher + "/runtime.s");

  image = asm.assemble { inherit items; textBase = base; };

  final = cpu.run stepLimit (cpu.load {
    inherit (image) bytes;
    inherit base ramSize;
    entry = base;
  });
in
{
  inherit listing functions compiled items image;
  report = cpu.report final;
}
