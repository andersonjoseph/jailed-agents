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
          gnused
        ];

        commonJailOptions = with jail.combinators; [
          network
          time-zone
          no-new-session
        ];

        nixDaemonAccess = {
          readwriteDirs = [ "/nix/var/nix/daemon-socket" ];
          readonlyDirs = [
            "/nix"
            "/etc/nix/nix.conf"
          ];
          pkgs = [ pkgs.nix ];
        };

        makeJailedAgent =
          {
            name,
            pkg,
            configPaths,
            extraPkgs ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            env ? { },
            enableNix ? false,
            nixConfigDir ? null,
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          let
            # Resolved form of `nixConfigDir`: null, or { path, writable }.
            resolvedNixConfigDir =
              if nixConfigDir == null then
                null
              else if builtins.isString nixConfigDir then
                {
                  path = nixConfigDir;
                  writable = false;
                }
              else if builtins.isAttrs nixConfigDir then
                if nixConfigDir ? path then
                  {
                    inherit (nixConfigDir) path;
                    writable = nixConfigDir.writable or false;
                  }
                else
                  throw "nixConfigDir attrset requires a 'path' attribute"
              else
                throw "nixConfigDir must be null, a path string, or an attrset { path, writable }";

            readonlyDirs =
              extraReadonlyDirs
              ++ pkgs.lib.optionals enableNix nixDaemonAccess.readonlyDirs
              ++ pkgs.lib.optional (
                resolvedNixConfigDir != null && !resolvedNixConfigDir.writable
              ) resolvedNixConfigDir.path;
            readwriteDirs =
              extraReadwriteDirs
              ++ pkgs.lib.optionals enableNix nixDaemonAccess.readwriteDirs
              ++ pkgs.lib.optional (
                resolvedNixConfigDir != null && resolvedNixConfigDir.writable
              ) resolvedNixConfigDir.path;
            extraPackages = extraPkgs ++ pkgs.lib.optionals enableNix nixDaemonAccess.pkgs;
          in
          jail name pkg (
            with jail.combinators;
            (
              baseJailOptions
              ++ (map (p: readonly (noescape p)) readonlyDirs)
              ++ [ mount-cwd ]
              ++ (map (p: readwrite (noescape p)) (configPaths ++ readwriteDirs))
              ++ [ (add-pkg-deps basePackages) ]
              ++ [ (add-pkg-deps extraPackages) ]
              ++ (pkgs.lib.mapAttrsToList set-env env)
            )
          );

        makePreconfiguredAgent =
          {
            defaultName,
            defaultPkg,
            configPaths,
          }:
          {
            name ? defaultName,
            pkg ? defaultPkg,
            extraPkgs ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            env ? { },
            enableNix ? false,
            nixConfigDir ? null,
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
              env
              enableNix
              nixConfigDir
              baseJailOptions
              basePackages
              configPaths
              ;
          };

        makeJailedCrush = makePreconfiguredAgent {
          defaultName = "jailed-crush";
          defaultPkg = llm-agents.packages.${system}.crush;
          configPaths = [
            "~/.config/crush"
            "~/.local/share/crush"
          ];
        };

        makeJailedOpencode = makePreconfiguredAgent {
          defaultName = "jailed-opencode";
          defaultPkg = llm-agents.packages.${system}.opencode;
          configPaths = [
            "~/.config/opencode"
            "~/.local/share/opencode"
            "~/.local/state/opencode"
          ];
        };

        makeJailedHermesAgent = makePreconfiguredAgent {
          defaultName = "jailed-hermes-agent";
          defaultPkg = llm-agents.packages.${system}.hermes-agent;
          configPaths = [ "~/.hermes" ];
        };

        makeJailedPi = makePreconfiguredAgent {
          defaultName = "jailed-pi";
          defaultPkg = llm-agents.packages.${system}.pi;
          configPaths = [ "~/.pi" ];
        };

        makeJailedClaudeCode = makePreconfiguredAgent {
          defaultName = "jailed-claude-code";
          defaultPkg = llm-agents.packages.${system}.claude-code;
          configPaths = [
            "~/.claude"
            "~/.claude.json"
          ];
        };

      in
      {
        lib = {
          inherit commonJailOptions;

          inherit makeJailedAgent;
          inherit makeJailedClaudeCode;
          inherit makeJailedCrush;
          inherit makeJailedHermesAgent;
          inherit makeJailedOpencode;
          inherit makeJailedPi;

          internals = {
            inherit jail;
          };
        };

        packages = {
          jailed-claude-code = makeJailedClaudeCode { };
          jailed-crush = makeJailedCrush { };
          jailed-hermes-agent = makeJailedHermesAgent { };
          jailed-opencode = makeJailedOpencode { };
          jailed-pi = makeJailedPi { };
        };

        formatter = pkgs.nixfmt;

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
