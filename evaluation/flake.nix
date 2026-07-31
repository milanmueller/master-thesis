{
  description = "An empty flake template that you can adapt to your own environment";

  # Flake inputs
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1"; # unstable Nixpkgs

  # Flake outputs
  outputs =
    { self, ... }@inputs:

    let
      # The systems supported for this flake
      supportedSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      # Helper to provide system-specific attributes
      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }
        );

    in
    {
      devShells = forEachSupportedSystem (
        { pkgs }:
        let
          isabelle-fhs = pkgs.buildFHSEnv {
            name = "isabelle-fhs";
            targetPkgs =
              pkgs: with pkgs; [
                bash
                coreutils
                glibc
                nss
                libGL
                freetype
                fontconfig
                dbus
                zlib
                libxext
                libx11
                libxrender
                libxtst
                libxi
                glib
                nspr
                atk
                cups
                libdrm
                gtk3
                pango
                cairo
                libxcomposite
                libxdamage
                libxfixes
                libxrandr
                libgbm
                expat
                libxcb
                libxkbcommon
                alsa-lib
                vscode
                clang-tools
                clang
                gcc
                gmp.dev
                gmp
                lldb
                valgrind
                parallel
                gnuplot
                (python3.withPackages (ps: with ps; [ matplotlib ]))
              ];
            runScript = "bash";
          };
        in
        {
          default = pkgs.mkShellNoCC {
            # The Nix packages provided in the environment
            # Add any you need here
            packages =
              with pkgs;
              [
                ripgrep
                claude-code # For generating tests in c
                (pkgs.writeShellScriptBin "emacs" ''
                  export EMACSDIR="''${USER_HOME:-.}/.emacs/doom"
                  export DOOMDIR="''${USER_HOME:-.}/.emacs/user"
                  export SHELL="${pkgs.bash}/bin/bash"
                  exec ${isabelle-fhs}/bin/isabelle-fhs -c '${pkgs.emacs}/bin/emacs --init-directory "$EMACSDIR"' "$@"
                '')
                (pkgs.writeShellScriptBin "doom" ''
                  export EMACSDIR="''${USER_HOME:-.}/.emacs/doom"
                  export DOOMDIR="''${USER_HOME:-.}/.emacs/user"
                  export EMACS="${pkgs.emacs}/bin/emacs"
                  exec ${isabelle-fhs}/bin/isabelle-fhs -c '"$EMACSDIR/bin/doom"' "$@"
                '')
                # Doom Emacs wants this
                symbola
                fd
                nerd-fonts.symbols-only
                nixfmt
                # Isabelle specific stuff
                (pkgs.writeShellScriptBin "isa" ''
                  exec ${isabelle-fhs}/bin/isabelle-fhs -c '/home/milan/git/isabelle-big-numbers/isabelle-emacs/bin/isabelle jedit' "$@"
                '')
                # Typst stuff for slides
                tinymist
                typstyle
                typst
                pympress # for presentation
              ]
              ++ (pkgs.lib.optional pkgs.stdenv.isLinux isabelle-fhs);

            # Set any environment variables for your dev shell
            env = {
              ISABELLE_HOME_USER = "/home/milan/git/isabelle-big-numbers/.isabelle";
              ISABELLE_HOME = "/home/milan/git/isabelle-big-numbers/.isabelle";
              USER_HOME = "/home/milan/git/isabelle-big-numbers";
            };
          };
        }
      );
    };
}
