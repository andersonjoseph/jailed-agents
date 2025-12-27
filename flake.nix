{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, jail-nix, llm-agents, flake-utils, ... }:
  flake-utils.lib.eachDefaultSystem (system: 
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

    makeJailedCrush = { extraPkgs ? [] }: jail "jailed-crush" crush-pkg (with jail.combinators; (
	commonJailOptions ++ [
	(readwrite (noescape "~/.config/crush"))
	(readwrite (noescape "~/.local/share/crush"))

	(add-pkg-deps commonPkgs)

	(add-pkg-deps extraPkgs)
    ]));

    makeJailedOpencode = { extraPkgs ? [] }: jail "jailed-opencode" opencode-pkg (with jail.combinators; (
	commonJailOptions ++ [
	(readwrite (noescape "~/.config/opencode"))
	(readwrite (noescape "~/.local/share/opencode"))
	(readwrite (noescape "~/.local/state/opencode"))

	(add-pkg-deps commonPkgs)

	(add-pkg-deps extraPkgs)
    ]));

  in 
  {
    lib = {
      inherit makeJailedCrush;
      inherit makeJailedOpencode;
    };

    devShells.default = pkgs.mkShell {
      packages = [
	pkgs.nixd

	(makeJailedCrush {})
	(makeJailedOpencode {})
      ];
    };
  });
}
