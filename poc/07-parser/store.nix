# A chunked integer-keyed store, and the reason it is not just an attrset.
#
# Symbols, trees and dag nodes are interned to integer ids and kept on the
# state (see sym.nix). The obvious representation is one attrset per table,
# updated with `//'. MEASURED, it is quadratic: `set // { k = v; }' builds a
# new binding array holding every existing key, so interning n values copies
# n^2/2 bindings. On a synthetic translation unit the flat version cost
# 62/101/224/574 MB of peak RSS at 104/208/416/832 source lines -- doubling the
# input for 2.5x the memory, which is decision-001's binding constraint being
# spent on bookkeeping rather than on the program.
#
# Chunking splits each table into buckets of `chunk' entries. An insert then
# copies one bucket plus the (much shorter) list of buckets, so the cost per
# insert is `chunk + n/chunk' instead of `n'. With chunk = 64 that is about an
# 18-fold reduction in copied bindings at three thousand entries, and it grows
# with the input rather than against it.
#
# This is NOT a cache and NOT derived state: it is the one copy of each table.
# `minimise state, never duplicate' is why the state carries the store and not
# also an index into it.
let
  b = builtins;
  chunk = 64;
in
rec {
  empty = { };

  bucketOf = id: toString (id / chunk);

  get = what: st: id:
    let
      c = bucketOf id;
      k = toString id;
    in
    st.${c}.${k} or (throw "store: no ${what} #${k}");

  set = st: id: v:
    let c = bucketOf id; in
    st // { ${c} = (st.${c} or { }) // { ${toString id} = v; }; };

  # Everything in the store, in no particular order. Used only by checks; no
  # compilation path walks a whole table.
  values = st: b.concatLists (map (c: b.attrValues st.${c}) (b.attrNames st));
}
