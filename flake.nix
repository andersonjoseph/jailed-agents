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

        crush-pkg = llm-agents.packages.${system}.crush;
        opencode-pkg = llm-agents.packages.${system}.opencode;

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
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          jail name pkg (
            with jail.combinators;
            (
              baseJailOptions
              ++ (map (p: readwrite (noescape p)) configPaths)
              ++ [ (add-pkg-deps basePackages) ]
              ++ [ (add-pkg-deps extraPkgs) ]
            )
          );

        makeJailedCrush =
          {
            name ? "jailed-crush",
            extraPkgs ? [ ],
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          jail name crush-pkg (
            with jail.combinators;
            (
              baseJailOptions
              ++ [
                (readwrite (noescape "~/.config/crush"))
                (readwrite (noescape "~/.local/share/crush"))

                (add-pkg-deps basePackages)

                (add-pkg-deps extraPkgs)
              ]
            )
          );

        makeJailedOpencode =
          {
            name ? "jailed-opencode",
            extraPkgs ? [ ],
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          jail name opencode-pkg (
            with jail.combinators;
            (
              baseJailOptions
              ++ [
                (readwrite (noescape "~/.config/opencode"))
                (readwrite (noescape "~/.local/share/opencode"))
                (readwrite (noescape "~/.local/state/opencode"))

                (add-pkg-deps basePackages)

                (add-pkg-deps extraPkgs)
              ]
            )
          );

      in
      {
        lib = {
          inherit commonJailOptions;
          inherit commonPkgs;
          inherit jail;
          inherit makeJailedAgent;
          inherit makeJailedCrush;
          inherit makeJailedOpencode;
        };
        formatter = flake-utils.lib.eachDefaultSystem (system: pkgs.nixfmt-tree);

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixd
            pkgs.nixfmt
            pkgs.statix

            (makeJailedCrush { })
            (makeJailedOpencode { })
          ];
        };
      }
    );
}
