# The listing's LIT SEGMENT, laid down as bytes.
#
# poc/03-matcher turns the FORESTS of lcc's listing into instructions and
# ignores everything else. That was right while the only thing outside a
# function was noise; a string literal is not noise -- it is the other half of
# the program, and `ADDRGP4 2' is a reference to bytes nobody had emitted.
#
# So this reads the half poc/03-matcher skips:
#
#     segment lit
#     global 2 type=array 4 of char sclass=static scope=GLOBAL flags=generated ...
#     defstring "abc\000"
#
# and produces the .data items that define `.Llit_2'. The LABEL comes from
# poc/03-matcher/emit.nix, passed in rather than spelled again here: the name
# this file defines and the name the instruction selector references have to be
# the same name, and two copies of a convention are two places for it to drift.
#
# WHY THE TEXT AND NOT THE COMPILER'S OWN BYTE LISTS. compile.nix's header
# makes the argument: the listing text IS the interface between the halves, and
# routing the data through it means the bytes the image gets are the bytes the
# oracle differential compared. Reaching into the frontend's state for them
# would be a second path that the differential does not see.
#
# THE ESCAPING IS symbolic.c's emitString, READ BACKWARDS. A byte is itself
# when printable, `\"' or `\\' when it is one of those two, and a THREE-DIGIT
# OCTAL escape otherwise. `\000' is how a NUL appears -- a Nix string cannot
# hold one (decision-001) -- so the decode below has to produce a byte LIST and
# never an intermediate string.
{ litLabel }:
let
  b = builtins;
  const = import ../06-constants/const.nix;
  it = import ../05-loop/items.nix;

  lines = text: b.filter b.isString (b.split "\n" text);
  words = s: b.filter (x: b.isString x && x != "") (b.split "[ \t]+" s);
  explode = s: b.genList (i: b.substring i 1 s) (b.stringLength s);

  octValue = s: b.foldl' (a: c: a * 8 + b.fromJSON c) 0 (explode s);

  # One `builtins.split' rather than a character walk that appends: `acc ++ [x]'
  # per byte is decision-001's quadratic accumulator, and a literal is exactly
  # the input that can be long. split returns literal runs and capture lists
  # alternately, so each piece decodes independently and they are joined once.
  unescape = s:
    b.concatLists (map
      (p:
        if b.isString p then map const.codeOf (explode p)
        else
          let e = b.head p; in
          if b.stringLength e == 3 then [ (octValue e) ] else [ (const.codeOf e) ])
      (b.split "\\\\([0-7][0-7][0-7]|.)" s));

  # `defconst unsigned.2 97'. The width is in the suffix and the bytes go down
  # LITTLE-ENDIAN, which is rcc-rv32's own `little_endian = 1' and the whole
  # reason decision-004 forbids the raw oracle.
  pow256 = n: b.foldl' (a: _: a * 256) 1 (b.genList (i: i) n);
  constBytes = where: spec: value:
    let
      # `void*' is DELIBERATELY not in this set. lcc spells a pointer constant
      # in hexadecimal, which `fromJSON' cannot read, so accepting the suffix
      # would turn a slice-3 pointer initialiser into an unreadable JSON error
      # instead of a refusal that names what is missing (task-029).
      m = b.match "(int|unsigned)\\.([0-9]+)" spec;
      w = if m == null
        then throw "data: ${where}: `defconst ${spec}' -- this lays out int and unsigned only; a pointer initialiser belongs to slice 3 (task-029) and a float one is deferred (decision-006)"
        else b.fromJSON (b.elemAt m 1);
      v = b.fromJSON value;
    in
    b.genList (k: b.bitAnd (v / pow256 k) 255) w;

  classify = raw:
    let ws = words raw; in
    if ws == [ ] then { kind = "other"; }
    else if b.head ws == "segment" then { kind = "segment"; name = b.elemAt ws 1; }
    else if b.head ws == "global" then { kind = "global"; name = b.elemAt ws 1; }
    else if b.head ws == "defstring" then
      let m = b.match "defstring \"(.*)\"" raw; in
      if m == null then throw "data: `${raw}' is a defstring whose text is not quoted"
      else { kind = "payload"; bytes = unescape (b.head m); }
    else if b.head ws == "defconst" then
      { kind = "payload"; bytes = constBytes raw (b.elemAt ws 1) (b.elemAt ws 2); }
    else { kind = "other"; };

  # Every definition in the lit segment, with its bytes. A `global' in `data'
  # or `bss' is a file-scope variable and belongs to slice 3 (task-029); it is
  # left alone here rather than half-emitted.
  defsOf = text:
    let
      items = map classify (lines text);
      n = b.length items;
      at = i: b.elemAt items i;
      idx = b.genList (i: i) n;
      segIdx = b.filter (i: (at i).kind == "segment") idx;
      segAt = i:
        let before = b.filter (j: j < i) segIdx; in
        if before == [ ] then "text"
        else (at (b.elemAt before (b.length before - 1))).name;
      # Where a definition's payload lines stop. Written as a filter and not as
      # a walk, because a WIDE literal emits one `defconst' line per unit and a
      # walk would recurse once per byte of the longest string in the file --
      # depth tracking the input rather than the nesting, which is the one
      # shape decision-001 says not to write.
      runEnd = i:
        let xs = b.filter (j: j >= i && (at j).kind != "payload") idx; in
        if xs == [ ] then n else b.head xs;
      lits = b.filter (i: (at i).kind == "global" && segAt i == "lit") idx;
    in
    map
      (i:
        let
          from = i + 1;
          upto = runEnd from;
          chunks = b.genList (k: (at (from + k)).bytes) (upto - from);
        in
        if upto == from
        then throw "data: `${(at i).name}' is announced in the lit segment and nothing follows it, so the reference to it would resolve to whatever came next"
        else { inherit ((at i)) name; bytes = b.concatLists chunks; })
      lits;
in
{
  inherit defsOf;

  # `.align 2' -- four bytes -- before every definition, not because a char
  # array needs it but because a WIDE literal does and the alignment of the
  # next one depends on the length of the last. Cheap, and the alternative is
  # a rule about which kinds need it.
  items = text:
    let ds = defsOf text; in
    if ds == [ ] then [ ]
    else [ (it.section ".data") ]
      ++ b.concatLists (map
        (d: [ (it.align 2) (it.label (litLabel d.name)) (it.bytes d.bytes) ])
        ds);
}
