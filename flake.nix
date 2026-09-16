{
  description = "nixcc: a C compiler for RISC-V, written in interpreted Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lcc-src = { url = "github:drh/lcc"; flake = false; };
    # Pinned to a tag, not the mob branch: repo.or.cz's `mob` gets rewritten,
    # which would eventually break evaluation. We want it for the tests2 corpus
    # (139 cases with .expect files) rather than for its compiler.
    tinycc-src = { url = "git+https://repo.or.cz/tinycc.git?ref=refs/tags/release_0_9_27"; flake = false; };
    nix-riscv = { url = "github:eisbaw/nix-riscv"; flake = false; };
  };

  outputs = { nixpkgs, lcc-src, tinycc-src, nix-riscv, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # lcc's own frontend, used as the oracle we diff our Nix frontend against.
      #
      # Build flags: -O0 is the load-bearing one. lcc's arena allocator
      # (alloc.c's `union align`) predates 16-byte-aligned types, so sym.c's
      # install() returns under-aligned memory -- live UB on every symbol
      # installation. x86 tolerates it at -O0; from -O1 GCC's alignment
      # assumptions kill it and rcc crashes on every input. -fno-strict-aliasing
      # does NOT fix this (measured: -O2 with it still crashes 18/18).
      rcc = pkgs.stdenv.mkDerivation {
        pname = "lcc-rcc";
        version = "4.2";
        src = lcc-src;
        nativeBuildInputs = [ pkgs.byacc ];

        # Upstream bug: every IR override flag uses its literal's length except
        # -mulops_calls=, which compares 18 bytes against a 14-char string and so
        # can never match -- a silent no-op. Fixed here so it is not a trap for
        # later work, but NOT used by rcc-rv32: with the flag actually live,
        # dag.c promotes MUL/DIV/MOD to forest roots, and neither symbolic.c's
        # valid-forest switch nor dagcheck.md (whose only stmt roots are INDIR*,
        # CALL* and V) knows about that. Making it work needs patching both plus
        # regenerating lburg output, which would make the oracle less like real
        # lcc -- defeating the point of having one. The mul/div/mod libcall
        # promotion is therefore a known, separately-tested divergence.
        postPatch = ''
          substituteInPlace src/main.c \
            --replace-fail '"-mulops_calls=", 18' '"-mulops_calls=", 14' \
            --replace-fail "argv[i][18] - '0'" "argv[i][14] - '0'"

        '';

        buildPhase = ''
          mkdir -p $PWD/build
          make BUILDDIR=$PWD/build HOSTFILE=etc/linux.c \
               CFLAGS='-g -O0 -std=gnu89 -w' \
               $PWD/build/rcc
        '';

        # A miscompiled rcc installs perfectly happily, and a one-function smoke
        # test does not catch it: an -O1 build passes `int f(int a){return a+1;}`
        # while crashing on every real file. So gate on lcc's own corpus.
        doCheck = true;
        nativeCheckInputs = [ pkgs.gcc ];
        checkPhase = ''
          fail=0 pass=0
          for f in tst/*.c; do
            case "$(basename $f)" in
              front.c|paranoia.c|yacc.c) continue ;;   # diagnostics test / need headers we do not ship
            esac
            gcc -E -P -std=gnu89 -nostdinc -Iinclude/x86/linux "$f" > t.i 2>/dev/null || continue
            if ./build/rcc -target=symbolic < t.i > t.sym 2>/dev/null && [ -s t.sym ]; then
              pass=$((pass + 1))
            else
              echo "rcc failed on $f"; fail=$((fail + 1))
            fi
          done
          echo "rcc corpus: $pass passed, $fail failed"
          [ "$fail" = 0 ] || { echo "rcc is miscompiled"; exit 1; }
          [ "$pass" -ge 15 ] || { echo "corpus shrank to $pass; expected >= 15"; exit 1; }
        '';

        installPhase = ''
          install -Dm755 build/rcc $out/bin/rcc
          # symbolicIR declares little_endian = 0, i.e. a big-endian machine.
          # decl.c and init.c consult it for bitfield and initializer layout:
          # measured, `unsigned b:5` shifts by 24 at 0 and by 3 at 1. Diffing
          # against raw `rcc -target=symbolic` would silently compare us to a
          # target that is not ours, so always go through this wrapper.
          #
          # symbolicIR also declares wants_argb = 1, which keeps a by-value
          # struct argument a STRUCT all the way to the backend: an ARGB node
          # and a PARAM symbol with flags=computed, which poc/03-matcher's
          # `frameOf' throws on. decision-009 chose the other lowering, the one
          # null.c and bytecode.c -- the real backends in lcc's own tree --
          # both choose: with wants_argb = 0 the FRONTEND turns the parameter
          # into `pointer to struct P flags=structarg' and the call site into a
          # temporary plus ASGNB plus an ordinary ARGP4. Measured before it was
          # taken: across all 62 .c files under poc/ the two settings produce
          # byte-identical output, because nothing in the corpus passed a
          # struct by value until task-058.
          mkdir -p $out/bin
          cat > $out/bin/rcc-rv32 <<EOF
          #!${pkgs.runtimeShell}
          exec $out/bin/rcc -target=symbolic -little_endian=1 -wants_argb=0 "\$@"
          EOF
          chmod +x $out/bin/rcc-rv32
        '';
        meta.mainProgram = "rcc";
      };

      encoder = import ./poc/01-encoder/encode.nix;
      cases = import ./poc/01-encoder/cases.nix;
    in {
      packages.${system} = { inherit rcc; default = rcc; };

      checks.${system} = {
        # The encoder is a pure expression, so evaluate it in the flake's own
        # evaluation and hand the results to the builder as plain text. The
        # earlier version ran `nix eval` inside a nix build, which needed
        # pkgs.nix in the sandbox, a private store and NIX_CONFIG. This way a
        # throwing encoder fails at flake-eval time instead of inside a builder.
        encoder = pkgs.runCommand "encoder-diff"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.pkgsCross.riscv32-embedded.buildPackages.binutils
            ];
            asm = pkgs.writeText "cases.s"
              (builtins.concatStringsSep "\n" (map (c: c.asm) cases) + "\n");
            ours = pkgs.writeText "cases.hex"
              (builtins.concatStringsSep "\n" (map (c: encoder.toHex c.word) cases));
            # Forcing this throws if any reject case encoded or any control case did not.
            mustFail = import ./poc/01-encoder/must-fail.nix;
          }
          ''
            riscv32-none-elf-as -march=rv32i -o a.o "$asm"
            riscv32-none-elf-objcopy -O binary --only-section=.text a.o a.bin
            cp "$asm" in.s; cp "$ours" ours.txt
            python3 ${./poc/01-encoder/compare.py} . | tee $out
            echo "$mustFail" >> $out
          '';

        # The lexer is a pure expression as well, so the same trick applies:
        # its tables, its reject paths and the byte-for-byte round-trip over
        # every lcc source are forced during flake evaluation, and a failure is
        # a throw at eval time rather than a builder that dies with no output.
        # The throughput ladder, the mutation test and the check on the text
        # of each diagnostic stay in run.sh: they time subprocesses and read
        # thrown messages, neither of which an evaluation can do to itself.
        # The matcher is pure in the same way, so its rule table, its label
        # tables and the text it emits are forced during flake evaluation.
        #
        # This is a contract on the emitted TEXT, not on what the code
        # computes: a rule template can be changed to compute the wrong thing
        # while satisfying every assertion here. The semantic oracle -- which
        # assembles, links and runs the result in the Nix RV32I emulator and
        # compares against the host compiler -- is in run.sh, along with the
        # scale ladder and the mutation test, because all three run and time
        # subprocesses. `just poc-matcher' is the stronger gate of the two.
        matcher = pkgs.runCommand "matcher-check"
          {
            # Derived from cases.nix so the case list has one definition;
            # run.sh builds the same attrset from the same place.
            report = import ./poc/03-matcher/check.nix {
              sources = builtins.listToAttrs (map
                (c: { inherit (c) name; value = ./poc/03-matcher/ir + "/${c.name}.sym"; })
                (import ./poc/03-matcher/cases.nix).functions);
            };
            mustFail = (import ./poc/03-matcher/must-fail.nix).summary;
          }
          ''
            printf '%s%s' "$report" "$mustFail" | tee $out
          '';

        # The assembler is pure as well: its layout, its label addresses, its
        # lui/addi expansions and its reject paths are all forced during flake
        # evaluation. What stays in run.sh is the differential against GNU as,
        # the execution in the Nix RV32I emulator, the check on the text of
        # each diagnostic, the mutation test and the scale ladder -- every one
        # of which runs a subprocess. `just poc-assembler' is the stronger
        # gate; this one fails at eval time, which is worth having on its own.
        assembler = pkgs.runCommand "assembler-check"
          {
            report = import ./poc/04-assembler/check.nix {
              progs = ./poc/04-assembler/progs;
            };
            mustFail = (import ./poc/04-assembler/must-fail.nix).summary;
          }
          ''
            printf '%s%s' "$report" "$mustFail" | tee $out
          '';

        # The closed loop is pure too: the C program's IR is read, the
        # function is compiled, the image is assembled and the RV32I machine
        # is RUN, all during flake evaluation, along with the eight malformed
        # programs that must each halt with their own reported fault. What
        # stays in run.sh is the check that lcc still produces this IR, the
        # single-eval stage with the toolchain taken off PATH, the memory
        # measurement and the mutation test.
        loop = pkgs.runCommand "loop-check"
          {
            report = import ./poc/05-loop/check.nix {
              cpu = import (nix-riscv + "/rv32.nix");
            };
            mustFail = (import ./poc/05-loop/must-fail.nix).summary;
          }
          ''
            printf '%s%s' "$report" "$mustFail" | tee $out
          '';

        # The parser is pure as well: every corpus listing is produced, poc/03-
        # matcher's listing parser re-checks the numbering and the reference
        # counts from the consumer's side, and the programs of
        # criterion #4 are compiled from .c, assembled and RUN, all during
        # flake evaluation. What stays in run.sh is everything that needs a
        # subprocess -- the byte-for-byte differential against lcc's own
        # frontend, the generated corpus, the check on the text of each
        # refusal, the memory ladder and the mutation test. `just poc-parser'
        # is by far the stronger gate; this one fails at eval time, which is
        # worth having on its own.
        parser = pkgs.runCommand "parser-check"
          {
            report = import ./poc/07-parser/check.nix {
              cpu = import (nix-riscv + "/rv32.nix");
            };
            mustFail = (import ./poc/07-parser/must-fail.nix).summary;
          }
          ''
            printf '%s%s' "$report" "$mustFail" | tee $out
          '';

        # The preprocessor is pure as well: its expansion, `#if' and
        # line-number tables, its refusals, and the two programs it
        # preprocesses, compiles and RUNS on the Nix RV32I machine are all
        # forced during flake evaluation. What stays in run.sh is everything
        # that needs a subprocess -- the token-stream differential against
        # `gcc -E', lcc's own frontend reading our linemarkers, the check on
        # the text of each refusal, and the mutation test. `just poc-cpp' is
        # the stronger gate; this one fails at eval time, which is worth
        # having on its own.
        cpp = pkgs.runCommand "cpp-check"
          {
            report = import ./poc/08-cpp/check.nix;
            ran = import ./poc/08-cpp/execute.nix {
              cpu = import (nix-riscv + "/rv32.nix");
            };
            mustFail = (import ./poc/08-cpp/must-fail.nix).summary;
          }
          ''
            printf '%s%s%s' "$report" "$ran" "$mustFail" | tee $out
          '';

        lexer = pkgs.runCommand "lexer-check"
          {
            report = import ./poc/02-lexer/check.nix {
              sources = import ./poc/02-lexer/sources.nix (lcc-src + "/src");
            };
            mustFail = (import ./poc/02-lexer/must-fail.nix).summary;
          }
          ''
            printf '%s%s' "$report" "$mustFail" | tee $out
          '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          rcc
          pkgs.just pkgs.python3
          pkgs.pkgsCross.riscv32-embedded.buildPackages.binutils
          pkgs.gcc pkgs.gnumake pkgs.byacc
          pkgs.shellcheck pkgs.statix pkgs.deadnix
        ];
        shellHook = ''
          # tinycc is not a port source, it is the test corpus. nix-riscv is the
          # execution substrate for the closed loop. Pinned so the versions the
          # tests are written against cannot drift.
          export LCC_SRC=${lcc-src}
          export TINYCC_SRC=${tinycc-src}
          export NIX_RISCV=${nix-riscv}
        '';
      };
    };
}
