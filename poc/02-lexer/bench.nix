# Throughput driver. Takes a path, lexes it, and prints one line of counts.
#
#   nix eval --impure --raw --expr 'import ./bench.nix { path = "/abs/file.c"; }'
#
# `path` is a string rather than a path because it comes from the shell, and
# `/. + path` then turns it back into one. (`nix eval --file` with `--argstr`
# does not apply the argument, so the --expr form above is the one that works.)
#
# The deepSeq is belt and braces, not the load-bearing force: `lex`'s own
# genericClosure operator already deepSeqs each item it returns, so forcing the
# list spine forces every lexeme too. Measured at the 120 kB ladder point,
# `seq` and `deepSeq` here are within noise of each other. It stays because the
# numbers below are only honest if EVERYTHING the lexer produces is evaluated,
# and this file should not have to know which other file guarantees that.
{ path }:
let
  b = builtins;
  l = import ./lex.nix;
  src = b.readFile (/. + path);
  toks = l.lex src;
in
b.deepSeq toks "${toString (b.stringLength src)}\t${toString (b.length toks)}\n"
