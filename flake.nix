{
  description = "Secure Nix sandbox for LLM agents - Run AI coding agents in isolated environments with controlled access";

  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

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
          readonlyDirs = [ "/etc/nix/nix.conf" ];
          pkgs = [ pkgs.nix ];
        };

        openUrls = import ./lib/open-urls.nix {
          inherit
            jail
            pkgs
            ;
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
            fwdEnv ? [ ],
            enableGitWorktrees ? { },
            enableOpenUrls ? false,
            nixConfigDir ? null,
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
            extraJailOptions ? [ ],
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

            gitWorktrees = import ./lib/git-worktrees.nix {
              inherit pkgs jail enableGitWorktrees;
            };

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
              ) resolvedNixConfigDir.path
              ++ gitWorktrees.readwriteDirs;
            extraPackages = extraPkgs ++ pkgs.lib.optionals enableNix nixDaemonAccess.pkgs;

            guardedJail =
              pkg':
              let
                jailed = jail name pkg' (
                  with jail.combinators;
                  (
                    baseJailOptions
                    ++ pkgs.lib.optionals enableOpenUrls [ openUrls ]
                    ++ extraJailOptions
                    ++ (map (p: readonly (noescape p)) readonlyDirs)
                    ++ pkgs.lib.optionals enableNix [ (defer (ro-bind "/nix" "/nix")) ]
                    ++ [ mount-cwd ]
                    ++ (map (p: readwrite (noescape p)) (configPaths ++ readwriteDirs))
                    ++ [ (add-pkg-deps basePackages) ]
                    ++ [ (add-pkg-deps extraPackages) ]
                    ++ (map try-fwd-env fwdEnv)
                    ++ (pkgs.lib.mapAttrsToList set-env env)
                    ++ gitWorktrees.perms
                  )
                );
              in
              pkgs.writeShellApplication {
                inherit name;
                text = ''
                  export TERM="''${TERM:-dumb}"
                  export LANG="''${LANG:-C.UTF-8}"
                  export PATH="''${PATH:-/bin}"
                  if [ -z "''${HOME:-}" ]; then
                    unset HOME
                    HOME=~
                    export HOME
                  fi
                  exec "${jailed}/bin/${name}" "$@"
                '';
              }
              // pkgs.lib.optionalAttrs (pkg' ? man) { inherit (pkg') man; }
              // pkgs.lib.optionalAttrs (pkg' ? shellPath) { inherit (pkg') shellPath; }
              // pkgs.lib.optionalAttrs (pkg' ? override) {
                override = overrideFn: guardedJail (pkg'.override overrideFn);
              };
          in
          guardedJail pkg;

        makePreconfiguredAgent =
          {
            defaultName,
            defaultPkg,
            configPaths,
            defaultExtraPkgs ? [ ],
            defaultEnv ? { },
            defaultExtraJailOptions ? [ ],
          }:
          {
            name ? defaultName,
            pkg ? defaultPkg,
            extraPkgs ? [ ],
            extraJailOptions ? [ ],
            extraReadwriteDirs ? [ ],
            extraReadonlyDirs ? [ ],
            env ? { },
            enableNix ? false,
            fwdEnv ? [ ],
            enableGitWorktrees ? { },
            enableOpenUrls ? false,
            nixConfigDir ? null,
            baseJailOptions ? commonJailOptions,
            basePackages ? commonPkgs,
          }:
          makeJailedAgent {
            extraPkgs = defaultExtraPkgs ++ extraPkgs;
            env = defaultEnv // env;
            extraJailOptions = defaultExtraJailOptions ++ extraJailOptions;
            inherit
              name
              pkg
              enableOpenUrls
              extraReadwriteDirs
              extraReadonlyDirs
              enableNix
              fwdEnv
              enableGitWorktrees
              nixConfigDir
              baseJailOptions
              basePackages
              configPaths
              ;
          };

        agents = import ./lib/agents {
          inherit
            makePreconfiguredAgent
            llm-agents
            pkgs
            system
            jail
            ;
        };

      in
      {
        lib = {
          inherit
            commonJailOptions
            openUrls
            ;

          inherit makeJailedAgent;
          inherit (agents)
            makeJailedClaudeCode
            makeJailedCodex
            makeJailedCrush
            makeJailedGoose
            makeJailedHermesAgent
            makeJailedOmp
            makeJailedOpencode
            makeJailedOpencode2
            makeJailedPi
            ;

          internals = {
            inherit jail;
          };
        };

        packages = {
          jailed-claude-code = agents.makeJailedClaudeCode { };
          jailed-codex = agents.makeJailedCodex { };
          jailed-crush = agents.makeJailedCrush { };
          jailed-goose = agents.makeJailedGoose { };
          jailed-hermes-agent = agents.makeJailedHermesAgent { };
          jailed-omp = agents.makeJailedOmp { };
          jailed-opencode = agents.makeJailedOpencode { };
          jailed-opencode2 = agents.makeJailedOpencode2 { };
          jailed-pi = agents.makeJailedPi { };
        };

        formatter = pkgs.nixfmt;

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixd
            pkgs.nixfmt
            pkgs.statix
            (agents.makeJailedOpencode {
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
