{
  description = "Secure Nix sandbox for LLM agents - Run AI coding agents in isolated environments with controlled access";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      jail-nix,
      llm-agents,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        jail = jail-nix.lib.init pkgs;
        commonPkgs = with pkgs; [
          bashInteractive
          curl
          wget
          jq
          git
          which
          ripgrep
          gnugrep
          gawkInteractive
          ps
          findutils
          gzip
          unzip
          gnutar
          diffutils
        ];

        commonJailOptions = with jail.combinators; [
          network
          time-zone
          no-new-session
          mount-cwd
        ];

        makeJailedAgent =
          {
            name,
            pkg,
            configPaths,
            extraPkgs ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          jail name pkg (
            with jail.combinators;
            (
              baseJailOptions
              ++ (map (p: readwrite (noescape p)) (configPaths ++ extraReadwriteDirs))
              ++ (map (p: readonly (noescape p)) extraReadonlyDirs)
              ++ [ (add-pkg-deps basePackages) ]
              ++ [ (add-pkg-deps extraPkgs) ]
            )
          );

        makeJailedCrush =
          {
            name ? "jailed-crush",
            pkg ? llm-agents.packages.${system}.crush,
            extraPkgs ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          makeJailedAgent {
            inherit
              name
              pkg
              extraPkgs
              extraReadwriteDirs
              extraReadonlyDirs
              baseJailOptions
              basePackages
              ;
            configPaths = [
              "~/.config/crush"
              "~/.local/share/crush"
            ];
          };

        makeJailedOpencode =
          {
            name ? "jailed-opencode",
            pkg ? llm-agents.packages.${system}.opencode,
            extraPkgs ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          makeJailedAgent {
            inherit
              name
              pkg
              extraPkgs
              extraReadwriteDirs
              extraReadonlyDirs
              baseJailOptions
              basePackages
              ;
            configPaths = [
              "~/.config/opencode"
              "~/.local/share/opencode"
              "~/.local/state/opencode"
            ];
          };

        makeJailedGeminiCli =
          {
            name ? "jailed-gemini-cli",
            pkg ? llm-agents.packages.${system}.gemini-cli,
            extraPkgs ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          makeJailedAgent {
            inherit
              name
              pkg
              extraPkgs
              extraReadwriteDirs
              extraReadonlyDirs
              baseJailOptions
              basePackages
              ;
            configPaths = [
              "~/.gemini"
            ];
          };

      in
      {
        lib = {
          inherit commonJailOptions;

          inherit makeJailedAgent;
          inherit makeJailedCrush;
          inherit makeJailedOpencode;
          inherit makeJailedGeminiCli;

          internals = {
            inherit jail;
          };
        };

        packages = {
          jailed-crush = makeJailedCrush { };
          jailed-gemini-cli = makeJailedGeminiCli { };
          jailed-opencode = makeJailedOpencode { };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixd
            pkgs.nixfmt
            pkgs.statix
            (makeJailedOpencode {
              extraPkgs = [
                pkgs.nixd
                pkgs.nixfmt
                pkgs.statix
              ];
            })
          ];
        };
      }
    );
}
