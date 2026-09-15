# Assembly text -> assembler items.
#
# This is a FRONT END, not the assembler. asm.nix consumes items and never
# looks at text; a code generator should build items directly and skip this
# file entirely (task-002 carried that forward, and it is still the plan).
# parse.nix exists because poc/03-matcher already emits .s TEXT, and that text
# is the only real corpus available to test an assembler against today -- both
# as input to us and as input to riscv32-none-elf-as for the differential.
#
# Operand types are NOT guessed from how they look. `beq a0,a1,.L3' has two
# registers and a label, and `sw a0,-60(s0)' has a register and a memory
# operand, and which is which comes from asm.nix's own operand-kind table.
# That is the single source of truth: a mnemonic added there is parsed here
# without touching this file, and a label that happens to be spelled `a0'
# cannot be mistaken for a register.
#
# builtins.substring copies its haystack (decision-001), so it is used here
# only on operands -- never on the source text, which is exploded once with
# builtins.split and cut with concatStringsSep.
{
  asm ? import ./asm.nix { },
}:
let
  b = builtins;

  chars = s: map b.head (b.filter b.isList (b.split "(.)" s));
  hexDigit = b.listToAttrs (b.genList
    (i: {
      name = b.substring i 1 "0123456789abcdef";
      value = i;
    })
    16);

  parseInt = where: s:
    let
      neg = b.substring 0 1 s == "-";
      body = if neg then b.substring 1 (b.stringLength s - 1) s else s;
      isHex = b.match "0[xX][0-9a-fA-F]+" body != null;
      digits = chars (b.substring 2 (b.stringLength body - 2) body);
      lower = c: b.replaceStrings [ "A" "B" "C" "D" "E" "F" ] [ "a" "b" "c" "d" "e" "f" ] c;
      mag =
        if isHex then b.foldl' (acc: c: acc * 16 + hexDigit.${lower c}) 0 digits
        else if b.match "[0-9]+" body != null then b.fromJSON body
        else throw "parse: ${where}: `${s}' is not an integer";
    in
    if neg then -mag else mag;

  trim = s: let m = b.match "[ \t]*(.*[^ \t]|)[ \t]*" s; in if m == null then "" else b.head m;

  # Block comments first -- runtime.s has them spanning lines -- then `#' to
  # end of line. Split rather than sliced: the whole file is never substring'd.
  stripBlockComments = where: text:
    let
      pieces = b.filter b.isString (b.split "/\\*" text);
      tailOf = p:
        let parts = b.filter b.isString (b.split "\\*/" p); in
        if b.length parts < 2 then throw "parse: ${where}: unterminated /* comment"
        else b.concatStringsSep "*/" (b.tail parts);
    in
    b.concatStringsSep "" ([ (b.head pieces) ] ++ map tailOf (b.tail pieces));

  stripLineComment = line:
    let parts = b.filter b.isString (b.split "#" line); in b.head parts;

  # --- directives ----------------------------------------------------------
  # Anything not listed is REFUSED. Silently dropping a directive is how an
  # assembler quietly loses data, and `.string' or `.comm' would do exactly
  # that if "unknown means ignore" were the rule.
  ignorable = [ "type" "size" "file" "ident" "option" "attribute" "local" "cfi_startproc" "cfi_endproc" ];
  widthOf = { byte = 1; half = 2; short = 2; word = 4; long = 4; };

  directive = where: name: rest:
    let
      operands = map trim (b.filter b.isString (b.split "," rest));
      one = if b.length operands == 1 && b.head operands != "" then b.head operands
      else throw "parse: ${where}: `.${name}' takes exactly one operand, got `${rest}'";
    in
    if name == "text" || name == "data" then [{ kind = "section"; name = ".${name}"; }]
    else if name == "section" then [{ kind = "section"; name = one; }]
    else if name == "align" || name == "p2align" then [{ kind = "align"; pow = parseInt where one; }]
    else if name == "globl" || name == "global" then [{ kind = "global"; name = one; }]
    else if name == "zero" || name == "space" then [{ kind = "zero"; count = parseInt where one; }]
    else if widthOf ? ${name} then
      [{
        kind = "bytes";
        width = widthOf.${name};
        values = map
          (o:
            if b.match "-?(0[xX][0-9a-fA-F]+|[0-9]+)" o != null then parseInt where o
            else if b.match "[.A-Za-z_][-A-Za-z0-9_.$]*" o != null then o
            else throw "parse: ${where}: `${o}' is neither a number nor a symbol")
          operands;
      }]
    else if b.elem name ignorable then [{ kind = "ignored"; directive = ".${name}"; }]
    else throw "parse: ${where}: directive `.${name}' is not implemented; this assembler refuses directives rather than dropping them";

  # --- one instruction -----------------------------------------------------
  instruction = where: mnemonic: rest:
    let
      alts = asm.operandShapes.${mnemonic}
        or (throw "parse: ${where}: unknown mnemonic `${mnemonic}'");
      raw = b.filter (s: s != "") (map trim (b.filter b.isString (b.split "," rest)));
      hit = b.filter (o: b.length o == b.length raw) alts;
      ops = if hit == [ ] then [ ] else b.head hit;
      memOf = o:
        let m = b.match "(-?(0[xX][0-9a-fA-F]+|[0-9]+))\\(([a-z0-9]+)\\)" o; in
        if m == null then throw "parse: ${where}: `${o}' is not a memory operand of the form disp(base)"
        else { disp = parseInt where (b.head m); base = b.elemAt m 2; };
      conv = i:
        let
          k = b.elemAt ops i;
          o = b.elemAt raw i;
        in
        if k == "i" then parseInt where o
        else if k == "m" then memOf o
        else o;
    in
    if hit == [ ] then
      throw ("parse: ${where}: `${mnemonic}' takes "
        + b.concatStringsSep " or " (map (o: toString (b.length o)) alts)
        + " operand(s), given ${toString (b.length raw)} in `${rest}'")
    else [{ kind = "insn"; inherit mnemonic; args = b.genList conv (b.length ops); }];

  # --- one line ------------------------------------------------------------
  # A line may carry several labels and then a statement, as `1: beqz a1,2f'
  # in poc/03-matcher/runtime.s does. Recursion depth here is labels-per-line,
  # not lines-per-file, so it does not grow with the input.
  statement = where: s:
    let
      t = trim s;
      lbl = b.match "([^ \t:,()]+):[ \t]*(.*)" t;
      dir = b.match "\\.([a-zA-Z0-9_]+)[ \t]*(.*)" t;
      ins = b.match "([a-z][a-z0-9.]*)[ \t]*(.*)" t;
    in
    if t == "" then [ ]
    else if lbl != null then
      [{ kind = "label"; name = b.head lbl; }] ++ statement where (b.elemAt lbl 1)
    else if dir != null then directive where (b.head dir) (trim (b.elemAt dir 1))
    else if ins != null then instruction where (b.head ins) (trim (b.elemAt ins 1))
    else throw "parse: ${where}: cannot make sense of `${t}'";

  parse = name: text:
    let
      lines = b.filter b.isString (b.split "\n" (stripBlockComments name text));
    in
    b.concatLists (b.genList
      (i: statement "${name}:${toString (i + 1)}" (stripLineComment (b.elemAt lines i)))
      (b.length lines));

  parseFile = path: parse (b.baseNameOf path) (b.readFile path);
in
{
  inherit parse parseFile;
  # Concatenating translation units is how a whole program is built until
  # there is a linker (task-022): one item list, one layout, one symbol table.
  parseAll = paths: b.concatLists (map parseFile paths);
}
