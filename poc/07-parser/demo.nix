# The loop closed from .c rather than from .sym.
#
#   run/*.c  --poc/02-lexer------>  tokens
#            --poc/07-parser----->  the DAG, as lcc's symbolic listing
#            --poc/03-matcher---->  RV32 assembly, one function at a time
#            --poc/04-assembler->   items -> bytes
#            --nix-riscv-------->   a running RV32I machine, stdout, exit code
#
# EVERY arrow is inside one `nix eval'. poc/05-loop's demo.nix had the same
# picture with the first two arrows replaced by "lcc, outside"; that was the
# gap decision-007 set out to close, and task-028 closed it there as well, so
# hello.c now takes this route too.
#
# The driver is assembly for the same reason it is in poc/05-loop: the RV32
# Linux syscall ABI is target knowledge that no C program can express. There
# are two stubs and the difference between them is the difference slice 2
# made. wc() writes ONE character, which was the smallest primitive that let a
# program in the int-only subset produce visible output at all: with no array
# and no pointer there was nothing to point a write(2) at except a one-byte
# buffer the driver owns. wr() writes a BUFFER, which a program with a char
# array has something to fill.
#
# THE FIRST ARROW IS NOW THE PREPROCESSOR. task-013.01 put poc/08-cpp in
# front of the lexer's output: `source' is raw C, directives and all, and what
# reaches the parser is the preprocessed TOKEN stream rather than a re-lexed
# string. On a file with no directives in it the preprocessor is the identity
# and nothing here changes, which is what poc/08-cpp/oracle.nix asserts over
# 26 of this directory's own translation units.
{ cpu
, source
, cpp ? ../08-cpp
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
  data = import ./data.nix { inherit (emit) litLabel; };

  pp = import (cpp + "/cpp.nix");
  listing = cc.listingOfToks (pp.tokensOf {
    src = b.readFile source;
    file = b.baseNameOf source;
  });
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

    # wr(fd, buf, n): write(2) with the arguments already where the syscall
    # wants them, which is the whole stub. It exists because a program that
    # has a char array has something worth writing more than one byte of, and
    # `wc' above cannot say how long it is.
    (it.global "wr")
    (it.label "wr")
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
    ++ parse.parseFile (matcher + "/runtime.s")
    # The lit segment last, because it is data and the entry point has to stay
    # at the first byte of .text. An empty list when the program has no string
    # literal, so nothing changes for the programs that had none.
    ++ data.items listing;

  image = asm.assemble { inherit items; textBase = base; };

  final = cpu.run stepLimit (cpu.load {
    inherit (image) bytes;
    inherit base ramSize;
    entry = base;
  });
in
{
  inherit listing functions compiled items image;
  # What the lit segment laid down, so check.nix can assert a program's string
  # literals reached .data as bytes rather than trusting that it ran.
  dataDefs = data.defsOf listing;
  report = cpu.report final;
}
