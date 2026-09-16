# Compile one C file with nixcc and run it on the Nix RV32I emulator.
#
# Everything below happens inside `nix eval': the lexer, the parser, the DAG,
# instruction selection, the assembler and the machine are all Nix. Nothing is
# shelled out to, and no compiler, assembler or emulator binary is involved.
#
#   just run hello.c 10
#
# Inputs come from the environment so this stays a plain expression rather than
# a function -- `nix eval --file' does not auto-call one.
#
# The program must define `int run(int)'. `extern int wc(int)' writes one
# character to stdout; the driver supplies it as three instructions of
# assembly, because the syscall ABI is target knowledge and never was C.
let
  b = builtins;
  file = b.getEnv "NIXCC_FILE";
  arg = let s = b.getEnv "NIXCC_ARG"; in if s == "" then 10 else b.fromJSON s;
  riscv = b.getEnv "NIX_RISCV";          # set by the dev shell

  demo = import ./poc/07-parser/demo.nix {
    inherit arg;
    cpu = import (/. + (riscv + "/rv32.nix"));
    source = /. + file;
  };
  inherit (demo) report;

  printable = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
  char = n:
    if n == 10 then "\n"
    else if n >= 32 && n < 127 then b.substring (n - 32) 1 printable
    else "\\x" + toString n;
in
if file == "" then throw "run.nix: set NIXCC_FILE, or use `just run FILE ARG'"
else b.concatStringsSep "" (map char report.stdoutBytes)
