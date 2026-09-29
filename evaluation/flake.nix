{
  description = "Toolchain for building and benchmarking the PAC proof checkers";

  # Same nixpkgs as ../isabelle/flake.nix, and flake.lock is copied from there,
  # so the compilers here are the ones the Isabelle exports were built against.
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
              mlton # Pasteque, Imperative-HOL/MLton backend
              clang # Pasteque, Isabelle-LLVM backend (-mllvm is clang-only)
              gcc # pacheck (C++20)
              gnumake
              time # GNU time: wall clock and peak RSS per run
              # results aggregation (pandas) and plotting (matplotlib)
              (python3.withPackages (ps: [
                ps.pandas
                ps.matplotlib
              ]))
            ];
            buildInputs = [ pkgs.gmp ];
          };
        }
      );
    };
}
