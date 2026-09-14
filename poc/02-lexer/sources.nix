# The round-trip corpus: every .c and .h in an lcc checkout's src directory.
#
# One definition, imported by both run.sh (pointed at $LCC_SRC) and the flake's
# `checks.lexer` (pointed at the pinned lcc-src input), so the two cannot end up
# round-tripping different files.
#
# Takes a PATH, not a string: `/. + "${lcc-src}/src"` is rejected in a flake,
# because a string carrying a store-path context cannot be turned back into a
# path. Callers pass `lcc-src + "/src"` or a bare path literal.
#
# lcc's sources are raw C89, not preprocessed output: `gcc -E` on them fails
# without lcc's own include paths, and lexing needs no preprocessing anyway.
dir:
let
  b = builtins;
  # readDir gives the type as well as the name; a directory called `foo.h`
  # would otherwise be handed to readFile.
  entries = b.readDir dir;
  names = b.filter (f: b.match ".*\\.[ch]" f != null && entries.${f} == "regular")
    (b.attrNames entries);
in
if names == [ ] then throw "sources: no .c or .h files under ${toString dir}"
else map (f: dir + "/${f}") names
