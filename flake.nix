{
  description = "nix-tcc: a C compiler for RISC-V, written in interpreted Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lcc-src = { url = "github:drh/lcc"; flake = false; };
    tinycc-src = { url = "git+https://repo.or.cz/tinycc.git"; flake = false; };
    nix-riscv = { url = "github:eisbaw/nix-riscv"; flake = false; };
  };

  outputs = { self, nixpkgs, lcc-src, tinycc-src, nix-riscv }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Reference oracle: lcc's own frontend, used to diff our Nix IR against.
      # lcc 4.2 predates strict aliasing and miscompiles at -O1 on modern gcc
      # (rcc segfaults before emitting anything), hence -O0 -fno-strict-aliasing.
      rcc = pkgs.stdenv.mkDerivation {
        pname = "lcc-rcc";
        version = "4.2";
        src = lcc-src;
        nativeBuildInputs = [ pkgs.byacc ];
        buildPhase = ''
          mkdir -p $PWD/build
          make BUILDDIR=$PWD/build HOSTFILE=etc/linux.c \
               CFLAGS='-g -O0 -std=gnu89 -w -fno-strict-aliasing' \
               $PWD/build/rcc
        '';
        installPhase = "install -Dm755 build/rcc $out/bin/rcc";
      };
    in {
      packages.${system} = { inherit rcc; default = rcc; };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          rcc
          pkgs.just
          pkgs.python3
          # oracle for the instruction encoder: diff our bytes against GNU as
          pkgs.pkgsCross.riscv32-embedded.buildPackages.binutils
          # for building the tinycc reference compiler when needed
          pkgs.gcc pkgs.gnumake pkgs.byacc
        ];
        shellHook = ''
          export LCC_SRC=${lcc-src}
          export TINYCC_SRC=${tinycc-src}
          export NIX_RISCV=${nix-riscv}
        '';
      };
    };
}
