# Criterion #5: a C program using macros and conditional compilation compiles
# from .c and RUNS.
#
# The whole chain is inside one `nix eval': poc/08-cpp preprocesses, the lexer
# and poc/07-parser make the DAG, poc/03-matcher selects instructions,
# poc/04-assembler lays out the image and nix-riscv executes it. Nothing is
# shelled out to. This is the same route poc/07-parser/check.nix takes for its
# own programs, with the preprocessor now at the front of it -- and `just run
# poc/08-cpp/run/macros.c 10' is that route with the answer printed instead of
# compared.
#
# THE ANSWERS ARE COMPUTED HERE, not read off a run. Each program's output is
# derived in this file from the constants the source defines, so a
# preprocessor that took the wrong arm of a conditional produces a different
# number rather than a differently-spelled version of the same one. The
# alternative-arm values are written out beside them: they are what makes the
# case discriminate, and they are the reason the constants are 7-against-1000
# rather than, say, 1-against-2.
{ cpu }:
let
  b = builtins;

  # sum of i for i in 1..n, without a loop: the programs compute it the slow
  # way and this is the independent check.
  triangle = n: n * (n + 1) / 2;
  digits = n: toString n + "\n";

  programs = [
    {
      name = "macros";
      arg = 7;
      # BIAS + SCALE*sum(1..n) + EXTRA*n, with BIAS 7 because BASE > 8 and
      # EXTRA 2 because NDEBUG is not defined.
      want = digits (7 + 3 * triangle 7 + 2 * 7);
      # The other arms give 1098 (BIAS 1000) and 3605 (EXTRA 500).
      instead = [ (1000 + 3 * triangle 7 + 2 * 7) (7 + 3 * triangle 7 + 500 * 7) ];
    }
    {
      name = "macros";
      arg = 10;
      want = digits (7 + 3 * triangle 10 + 2 * 10);
      instead = [ (1000 + 3 * triangle 10 + 2 * 10) (7 + 3 * triangle 10 + 500 * 10) ];
    }
    {
      name = "table";
      arg = 7;
      # MULT*sum(1..n) + OFFSET, with MULT 11 from the third #elif arm and
      # OFFSET 100 from the definition that follows the #undef.
      want = digits (11 * triangle 7 + 100);
      # The #else arm gives MULT 1000, and an #undef that did nothing would
      # have left OFFSET at 4.
      instead = [ (1000 * triangle 7 + 100) (11 * triangle 7 + 4) ];
    }
    {
      name = "table";
      arg = 10;
      want = digits (11 * triangle 10 + 100);
      instead = [ (1000 * triangle 10 + 100) (11 * triangle 10 + 4) ];
    }
  ];

  declaredPrograms = 4;

  ran = map
    (p:
      let
        d = import ../07-parser/demo.nix {
          inherit cpu;
          source = ./run + "/${p.name}.c";
          inherit (p) arg;
        };
      in
      p // { inherit (d) report; })
    programs;

  # `steps' as well as the output: a report that printed the right answer in
  # no instructions at all would be a stub, and the answer is the only other
  # thing checked here.
  wrong = b.filter (r: r.report.stdout != r.want || r.report.exitCode != 0 || r.report.steps < 100) ran;

  # A case whose wrong answer equals its right one discriminates nothing. This
  # is arithmetic over the table rather than a claim in a comment, because
  # ir/unsig.c's divisor of 7 was a claim in a comment.
  blind = b.filter (r: b.any (v: digits v == r.want) r.instead) programs;

  show = s: b.replaceStrings [ "\n" ] [ "\\n" ] s;
in
if b.length programs != declaredPrograms then
  throw "check: ${toString (b.length programs)} program runs, against the ${
    toString declaredPrograms} this file declares"
else if blind != [ ] then
  throw "check: ${(b.head blind).name}.c with ${toString (b.head blind).arg} prints the same answer whether the preprocessor chose the right arm or not, so running it proves nothing"
else if wrong != [ ] then
  throw "check: ${(b.head wrong).name}.c with ${
    toString (b.head wrong).arg} printed `${show (b.head wrong).report.stdout}' and exited ${
    toString (b.head wrong).report.exitCode} in ${
    toString (b.head wrong).report.steps} instructions, wanted `${
    show (b.head wrong).want}' and 0 in more than a hundred"
else
  b.concatStringsSep "\n" (map
    (r: "run/${r.name}.c preprocessed, compiled and run with ${toString r.arg}: ${
      show r.report.stdout} in ${toString r.report.steps} instructions")
    ran) + "\n"
