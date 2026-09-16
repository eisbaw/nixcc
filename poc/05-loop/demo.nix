# The loop, closed: C in, program output out, inside one evaluation.
#
#   hello.c  --poc/02-lexer------>  tokens
#            --poc/07-parser----->  the DAG, as lcc's symbolic listing
#            --poc/03-matcher---->  assembly for one function
#            --poc/04-assembler->   items -> bytes
#            --nix-riscv-------->   a running RV32I machine, stdout and an exit code
#
# NO ARROW LEAVES THE EVALUATOR any more. task-005 costed the first one -- lcc
# was the front end and a .sym listing was this compiler's real entry point --
# and slices 1 and 2 closed it: hello.c needs a global `char' array, a pointer
# parameter and a subscript, and task-028 is where those arrived.
#
# hello.sym IS STILL HERE and is still regenerated from lcc. It is no longer
# the input; it is the ORACLE, and check.nix diffs our own listing against it
# byte for byte. Deleting it would leave nothing saying that the frontend this
# demo now runs on agrees with the one it replaced.
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
, frontend ? ../07-parser
, source ? ./hello.c
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
  cc = import (frontend + "/compile.nix");

  # OUR listing, and lcc's, side by side. check.nix compares them; nothing
  # downstream of here reads `oracleListing', so a demo that quietly stopped
  # consulting lcc would still run -- which is exactly why the comparison is a
  # guard in check.nix and not an `assert' hidden in this let.
  listing = cc.listingOf (b.readFile source);
  oracleListing = b.readFile ir;

  compiled = emit.compile (irParse.parse listing);

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
  # `asm' and `compiled' are exported rather than left to the caller to import
  # again: check.nix reads operand KINDS out of `asm' to decide which operands
  # are branch targets, and the instructions and IR out of `compiled' to check
  # that hello.c still uses what it demonstrates. Reading either from an
  # instance other than the one that built THIS image would be reading a
  # different table -- and a second `emit.compile' of the same listing is also
  # a second DAG live at once, which decision-007 says is the budget to watch.
  inherit asm items image loaded driver compiled listing oracleListing;
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
