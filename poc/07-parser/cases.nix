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
#   * `programs' are the three that must COMPILE AND RUN (criterion #4), and
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
    quals = "const and volatile, both of which change the IR";
    scopes = "nested blocks, shadowing, an explicit register";
    ternary = "?:, including a nested one";
    unary = "- ~ + !";
    unsig = "unsigned arithmetic and the constant comparisons";
    warns = "the expression forms lcc diagnoses, for criterion #7";
    whileloop = "while with break and continue";
  };

  # Declared and checked for EQUALITY, so the number cannot drift from the
  # directory in silence.
  corpusCount = 21;

  # The three programs of criterion #4, also derived from their directory,
  # with the argument the driver passes each. `programCount' is what makes
  # "three programs RUN" a claim the suite checks rather than one it states:
  # without it, deleting a program leaves every stage green.
  programNames = b.sort (x: y: x < y) (map (n: b.substring 0 (b.stringLength n - 2) n)
    (b.filter (n: b.match ".*\\.c" n != null) (b.attrNames (b.readDir ./run))));
  args = { gcd = 10; primes = 10; sumto = 10; };
  programs = map (n: { name = n; arg = args.${n} or (throw
    "cases: run/${n}.c has no argument in `args'; add one rather than letting it default"); })
    programNames;
  programCount = 3;

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

  # The arguments come from `args' above rather than being restated, so that
  # changing what the driver passes cannot leave the expectation quietly
  # describing a different run. The arithmetic mirrors the C: `n << 3' is
  # `n * 8', and Nix's application-binds-tightest makes the last line
  # `((countPrimes args.primes) * 100) / 7', which is what primes.c computes.
  expectedStdout = {
    sumto = "${toString (sumTo args.sumto)}\n";
    gcd = "${toString (gcd 1071 462)} ${toString (fib args.gcd)}\n";
    primes = "${toString (countPrimes (args.primes * 8))} ${
      toString (countPrimes args.primes * 100 / 7)}\n";
  };

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
  opcodes = [
    "ADDI4"
    "ADDRFP4"
    "ADDRGP4"
    "ADDRLP4"
    "ADDU4"
    "ARGI4"
    "ASGNI4"
    "ASGNU4"
    "BANDI4"
    "BCOMI4"
    "BORI4"
    "BXORI4"
    "CALLI4"
    "CALLV"
    "CNSTI4"
    "CNSTU4"
    "CVIU4"
    "CVUI4"
    "DIVI4"
    "DIVU4"
    "EQI4"
    "GEI4"
    "GEU4"
    "GTI4"
    "INDIRI4"
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
    "RETI4"
    "RETU4"
    "RSHI4"
    "RSHU4"
    "SUBI4"
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
