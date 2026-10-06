{
  description = "Toolchain for the parser fuzzing benchmarks of the PAC proof checkers";

  # Same nixpkgs as ../flake.nix, and flake.lock is copied from there, so the
  # compilers here are the ones the full checkers in ../main are built with.
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # unstable Nixpkgs

  outputs =
    { self, ... }@inputs:

    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system: f { pkgs = import inputs.nixpkgs { inherit system; }; }
        );
    in
    {
      devShells = forEachSupportedSystem (
        { pkgs }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # ./collect-parsers.sh
              mlton # parse-sml, Imperative-HOL/MLton backend
              clang # parse-llvm, Isabelle-LLVM backend (-mllvm is clang-only)
              gnumake # the Makefile of the LLVM code directory
              # ./run-sweep.sh
              gawk # averages and standard deviations
              # ./gen-instance.py needs only the standard library;
              # ./render-graph.py needs pandas and matplotlib
              (python3.withPackages (ps: [
                ps.pandas
                ps.matplotlib
              ]))
            ];
            buildInputs = [ pkgs.gmp ]; # MLton links its runtime against GMP
          };
        }
      );
    };
}
