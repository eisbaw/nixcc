# What the parser PoC is tested on, and what the answers are.
#
# Two kinds of entry, and the difference matters:
#
#   * `corpus' is the set of C files whose LISTING is diffed node for node
#     against rcc-rv32 (criteria #2 and #3). Nothing here says what those
#     listings should contain -- oracle.py asks lcc. What this file pins is the
#     population: which files are in the corpus, and what opcodes they must
#     between them produce, so that a case quietly losing its interesting
#     operator is a failure rather than a smaller diff that still passes.
#
#   * `programs' are the ones that must COMPILE AND RUN (criterion #4), and
#     their expected output is COMPUTED HERE IN NIX rather than written down.
#     `gcd' below is Euclid's algorithm a second time, in a second language;
#     agreeing with the compiled C is then two independent derivations meeting,
#     which a pinned "21 55" would not be. poc/05-loop/driver.nix makes the
#     same argument about its vector.
let
  b = builtins;
in
rec {
  # The IR corpus is DERIVED from the directory, not listed. A hand-written
  # list catches a file deleted from it and never a file added to c/ and
  # forgotten -- which is this project's own recurring lesson, and which would
  # mean a new case compared by nothing. `notes' documents what each file is
  # for, and the two are checked against each other in both directions below,
  # so a file without a note and a note without a file are both failures.
  corpus = b.sort (x: y: x < y) (map (n: b.substring 0 (b.stringLength n - 2) n)
    (b.filter (n: b.match ".*\\.c" n != null) (b.attrNames (b.readDir ./c))));

  notes = {
    arith = "every integer binary operator";
    arrays = "array TYPES, whose printing collapses nested dimensions";
    calls = "nested call, discarded result, void call";
    cmp = "the six comparisons, inverted by the false-label branch";
    dowhile = "do/while";
    empty = "a void function and an empty statement";
    folds = "the identities and folds simp.c applies";
    forloop = "for, and the entry test foldcond removes";
    incr = "++ and --, prefix and postfix, used and discarded";
    inits = "local initialisers, which reset the reference count";
    layout = "locals ordered by reference count, not by declaration";
    linkage = "the DECLARATION diagnostics, which no IR diff can see";
    logic = "&& || and short-circuit labels";
    longs = "long, which shares every opcode with int";
    ptrs = "subscripting, pointer arithmetic and both addrtree paths";
    quals = "const and volatile, both of which change the IR";
    scopes = "nested blocks, shadowing, an explicit register";
    strs = "string literals: the join, the interning, the NUL and the lit segment";
    ternary = "?:, including a nested one";
    unary = "- ~ + !";
    unsig = "unsigned arithmetic and the constant comparisons";
    warns = "the expression forms lcc diagnoses, for criterion #7";
    whileloop = "while with break and continue";
  };

  # Declared and checked for EQUALITY, so the number cannot drift from the
  # directory in silence.
  corpusCount = 23;

  # The programs of criterion #4, also derived from their directory, with the
  # argument the driver passes each. `programCount' is what makes "the
  # programs RUN" a claim the suite checks rather than one it states: without
  # it, deleting a program leaves every stage green.
  #
  # It was three, then five, and is six. bits.c and unsig.c were written for
  # slice 1 and dropped from it, because poc/03-matcher/rules.nix had no rule for `&',
  # `|', `^', `~', unary `-' or any U-typed opcode and refused them at
  # instruction selection -- loudly, by name, which was the right failure and
  # still a failure. task-051 added those rules; these two are what says so
  # from the C end rather than from the rule table's. strings.c is slice 2's
  # (task-028): a char array, a string literal and the NUL in the middle of it.
  programNames = b.sort (x: y: x < y) (map (n: b.substring 0 (b.stringLength n - 2) n)
    (b.filter (n: b.match ".*\\.c" n != null) (b.attrNames (b.readDir ./run))));
  # `unsigned' and not `unsig': c/unsig.c already exists, and the oracle
  # differential keys its answers by BASENAME across both directories, so two
  # files sharing one would have compared one program's listing against the
  # other's lcc output. oracle.py says so in its own words now -- that guard
  # was there and unreachable, because the file count it sits behind fell over
  # first and reported an arithmetic problem.
  args = { bits = 10; gcd = 10; primes = 10; strings = 10; sumto = 10; unsigned = 10; };
  programs = map (n: { name = n; arg = args.${n} or (throw
    "cases: run/${n}.c has no argument in `args'; add one rather than letting it default"); })
    programNames;
  programCount = 6;

  # --- the expected output, derived --------------------------------------
  # A second implementation of what each program computes. Written in Nix over
  # the same arguments the driver passes, so that "the compiled C is right"
  # means two derivations agree rather than one matching a string.
  sumTo = n: b.foldl' (a: i: a + i) 0 (b.genList (i: i + 1) n);

  gcd = a: b0: if b0 == 0 then a else gcd b0 (a - (a / b0) * b0);

  fib = n: if n < 2 then n else fib (n - 1) + fib (n - 2);

  isPrime = n:
    if n < 2 then false
    else
      let
        go = d: if d * d > n then true else if n - (n / d) * d == 0 then false else go (d + 1);
      in
      go 2;

  countPrimes = n: b.length (b.filter isPrime (b.genList (i: i) n));

  # --- bits.c, in Nix's own bitwise builtins -----------------------------
  # `bitAnd', `bitOr' and `bitXor' are Nix's own, so this is a second
  # implementation of the same operators rather than a restatement of the C.
  # ONE HALF OF IT IS NOT INDEPENDENT and should be read as such: Nix has no
  # `bitNot', so `~x' is written here as `x ^ -1' -- which is exactly what
  # poc/03-matcher/rules.nix emits for BCOMI4, so the two cannot disagree
  # about it. What is independent is the bit count, the right shift spelled
  # as a division, and the unary minus around them.
  bnot = x: b.bitXor x (-1);
  bitCount = n: if n == 0 then 0 else (b.bitAnd n 1) + bitCount (n / 2);
  twos = n: 0 - (bnot n + (0 - n));
  mix = x: y: b.bitOr (b.bitAnd x y) (b.bitXor x y);

  # --- unsig.c, 32-bit unsigned arithmetic in 64-bit signed integers -----
  # Nix has no unsigned type and no modulo, and its integers THROW on
  # overflow (decision-001), so every value here is kept inside [0, 2^32) by
  # hand: `u32' masks and `umod' is spelled the way `gcd' above spells it.
  u32 = x: b.bitAnd x 4294967295;
  umod = x: y: x - (x / y) * y;
  # `x / 32' is `x >> 5' because x is known non-negative here, which is the
  # whole reason the C's shift has to be the LOGICAL one: on the same bit
  # pattern read as a signed integer, `>>' would bring ones down from the top.
  hashMix = x: b.bitAnd (b.bitXor x (x / 32)) 65535;

  # The arguments come from `args' above rather than being restated, so that
  # changing what the driver passes cannot leave the expectation quietly
  # describing a different run. The arithmetic mirrors the C: `n << 3' is
  # `n * 8', and Nix's application-binds-tightest makes the last line
  # `((countPrimes args.primes) * 100) / 7', which is what primes.c computes.
  expectedStdout = {
    sumto = "${toString (sumTo args.sumto)}\n";
    bits = "${toString (bitCount (args.bits * 7))} ${
      toString (twos args.bits)} ${toString (mix args.bits (args.bits + 5))}\n";
    # The C says `0xffffff00u + n', and 0xffffff00 is 4294967040. Written as
    # the decimal here because Nix has no hexadecimal literal for it and
    # spelling it in hex would mean a second conversion to get wrong.
    unsigned =
      let u = u32 (4294967040 + args.unsigned); in
      "${toString (u / 3)} ${toString (umod u 7)} ${toString (hashMix u)}\n";
    gcd = "${toString (gcd 1071 462)} ${toString (fib args.gcd)}\n";
    # run/strings.c copies `"ab" "\0cd"' out a byte at a time, writing `-'
    # where the embedded NUL is, and then the argument's two digits. The `-'
    # is a JOIN here rather than a replacement, which is the point: the C
    # reaches "ab-cd" by surviving a NUL in the middle of a literal and this
    # reaches it by putting two strings either side of a separator. They agree
    # only if the literal really held five units.
    strings = "${b.concatStringsSep "-" [ "ab" "cd" ]}${toString twoDigitArg}\n";
    primes = "${toString (countPrimes (args.primes * 8))} ${
      toString (countPrimes args.primes * 100 / 7)}\n";
  };

  # run/strings.c spells the argument as two digits -- `n / 10' and `n % 10'
  # -- so an argument outside 10..99 would make the C print something this
  # expectation does not describe, and the failure would read as a compiler
  # bug. poc/05-loop/driver.nix keeps the same kind of guard over the same
  # kind of assumption, and for the same reason: it is the C's assumption
  # about its input, not a matter of taste.
  twoDigitArg =
    if args.strings >= 10 && args.strings <= 99 then args.strings
    else throw "cases: run/strings.c prints its argument as exactly two digits, so `args.strings' must be between 10 and 99; it is ${toString args.strings}";

  # --- the opcode population ---------------------------------------------
  # Checked for EQUALITY, in both directions. A pinned list catches an opcode
  # the corpus stopped producing; equality also catches one it STARTED
  # producing that nobody looked at -- which is the direction a hand-written
  # list of things-that-must-be-true always misses.
  # RETV is deliberately absent: lcc's retcode() returns without building a
  # tree when the value is NULL, so a `void' function emits no RET node at
  # all. empty.c is in the corpus to hold that -- the fall-through from a void
  # function is one forest shorter than a reader would guess, and it is worth
  # a case even though it adds no opcode.
  # The thirteen this slice added are the shape of what it is: a pointer that
  # is ADDED to and SUBTRACTED from (ADDP4, SUBU4, CVPU4), a byte that is
  # loaded, converted and stored (INDIRI1, CVII1, CVII4, CNSTI1, ASGNI1), a
  # pointer that is assigned, loaded, passed and returned (ASGNP4, INDIRP4,
  # ARGP4, RETP4), and a wide literal's halfword (INDIRU2). The null pointer
  # constant brings four more: CNSTP4, CVUP4 and the two unsigned equality
  # comparisons a pointer test lowers to.
  #
  # FIVE OF THESE HAVE NO ROW IN poc/03-matcher/rules.nix -- CNSTP4, CVUP4,
  # CVPU4, SUBP4 and RETP4 -- and that is task-054. They diff clean against lcc
  # and would be refused at instruction selection, loudly and by name, which is
  # why no program under run/ compares a pointer against zero, subtracts two
  # pointers or returns one. This list is a claim about the FRONTEND; it is not
  # a claim that the backend can lower what the frontend emits.
  opcodes = [
    "ADDI4"
    "ADDP4"
    "ADDRFP4"
    "ADDRGP4"
    "ADDRLP4"
    "ADDU4"
    "ARGI4"
    "ARGP4"
    "ASGNI1"
    "ASGNI4"
    "ASGNP4"
    "ASGNU4"
    "BANDI4"
    "BCOMI4"
    "BORI4"
    "BXORI4"
    "CALLI4"
    "CALLV"
    "CNSTI1"
    "CNSTI4"
    "CNSTP4"
    "CNSTU4"
    "CVII1"
    "CVII4"
    "CVIU4"
    "CVPU4"
    "CVUI4"
    "CVUP4"
    "DIVI4"
    "DIVU4"
    "EQI4"
    "EQU4"
    "GEI4"
    "GEU4"
    "GTI4"
    "INDIRI1"
    "INDIRI4"
    "INDIRP4"
    "INDIRU2"
    "INDIRU4"
    "JUMPV"
    "LEI4"
    "LSHI4"
    "LTI4"
    "LTU4"
    "MODI4"
    "MODU4"
    "MULI4"
    "NEGI4"
    "NEI4"
    "NEU4"
    "RETI4"
    "RETP4"
    "RETU4"
    "RSHI4"
    "RSHU4"
    "SUBI4"
    "SUBU4"
  ];

  # The source a translation unit of `n' functions is made of, for the memory
  # ladder. Each function is the same shape so that cost per line is a
  # meaningful quotient; the body is deliberately ordinary, because a file of
  # nothing but declarations would measure the wrong thing.
  synthetic = n:
    b.concatStringsSep "\n" (b.genList
      (i: ''
        int f${toString i}(int a, int b)
        {
            int x;
            int y;
            x = a + b * ${toString (i + 1)};
            y = x - a;
            if (x > y)
                y = y + x / ${toString (i + 2)};
            while (y > 0)
                y = y - 1;
            return x + y;
        }
      '')
      n);
  # ONE function of `n' statements, against `synthetic' n functions of ten.
  # The two shapes cost very differently: a finished function's trees and dag
  # nodes are released, so a file of many small functions peaks far below one
  # whose peak is a single large function. Measuring only the first would
  # report a per-line figure the second does not obey.
  syntheticOne = n: ''
    int big(int a, int b)
    {
        int x;
        int y;

        x = a;
        y = b;
    ${b.concatStringsSep "\n" (b.genList
      (i: "    x = x + y * ${toString (i + 1)};\n    y = y + x / ${toString (i + 2)};") n)}
        return x + y;
    }
  '';

}
