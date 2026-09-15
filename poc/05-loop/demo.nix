# The loop, closed: C in, program output out, inside one evaluation.
#
#   hello.c  --(lcc, outside)-->  hello.sym
#            --poc/03-matcher-->  assembly for one function
#            --poc/04-assembler->  items -> bytes
#            --nix-riscv-------->  a running RV32I machine, stdout and an exit code
#
# Only the first arrow leaves the evaluator, and it is the one task-005 has to
# cost: lcc is still the front end, so a .sym listing is this compiler's real
# entry point today, not a .c file. Everything downstream of it is Nix.
#
# The third arrow is the remaining seam INSIDE Nix: poc/03-matcher emits
# assembly TEXT, which poc/04-assembler's text front end immediately turns
# back into items. The driver below shows the path that has no text in it at
# all -- its items are built in Nix and handed straight to the assembler -- so
# what is left is for emit.nix to do the same (task-026).
#
# `cpu' is passed in rather than imported: nix-riscv is a flake input, which
# the flake's checks can reach purely and run.sh reaches through $NIX_RISCV.
# `base', `ramSize' and the two step budgets are cases.nix's to choose -- the
# fault programs aim at literal addresses derived from them -- so they arrive
# as arguments rather than being decided here. The defaults exist only so the
# demo can be evaluated by hand.
{ cpu
, matcher ? ../03-matcher
, assembler ? ../04-assembler
, ir ? ./hello.sym
, base ? 65536
, ramSize ? 1048576
, stepLimit ? 200000
}:
let
  b = builtins;

  asm = import (assembler + "/asm.nix") { };
  parse = import (assembler + "/parse.nix") { inherit asm; };
  emit = import (matcher + "/emit.nix") { };
  irParse = import (matcher + "/parse.nix");
  driver = import ./driver.nix { };

  compiled = emit.compile (irParse.parse (b.readFile ir));

  # Order is a choice, not an inheritance: the symbol table spans the whole
  # item list, so any order resolves -- but `_start' has to be the first thing
  # in .text for the entry point to be the load address.
  items = driver.items
    ++ parse.parse "hello.s" compiled.asm
    ++ parse.parseFile (matcher + "/runtime.s");

  image = asm.assemble { inherit items; textBase = base; };

  loaded = cpu.load {
    inherit (image) bytes;
    inherit base ramSize;
    entry = base;
  };
  final = cpu.run stepLimit loaded;
in
{
  # `asm' is exported rather than left to the caller to import again: check.nix
  # reads operand KINDS out of it to decide which operands are branch targets,
  # and reading them from an assembler instance other than the one that built
  # this image would be reading a different table.
  inherit asm items image loaded driver;
  report = cpu.report final;

  # Assemble and run an arbitrary item list on the same machine, which is what
  # the fault cases need: they are programs too, and they must go through the
  # same assembler and the same emulator as the demo or they prove nothing
  # about either.
  runItems = { faultItems, limit }:
    let
      img = asm.assemble { items = faultItems; textBase = base; };
      end = cpu.run limit (cpu.load {
        inherit (img) bytes;
        inherit base ramSize;
        entry = base;
      });
    in
    { image = img; final = end; report = cpu.report end; };
}
