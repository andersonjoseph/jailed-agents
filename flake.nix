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

    makeJailedCrush = { extraPkgs ? [] }: jail "jailed-crush" crush-pkg (with jail.combinators; [
	network
	time-zone
	no-new-session

	mount-cwd

	(readwrite (noescape "~/.config/crush"))
	(readwrite (noescape "~/.local/share/crush"))

	(add-pkg-deps [
	  pkgs.bashInteractive
	  pkgs.curl
	  pkgs.wget
	  pkgs.jq
	  pkgs.git
	  pkgs.which
	  pkgs.ripgrep
	  pkgs.gnugrep
	  pkgs.gawkInteractive
	  pkgs.ps
	  pkgs.findutils
	  pkgs.gzip
	  pkgs.unzip
	  pkgs.gnutar
	  pkgs.diffutils
	])

	(add-pkg-deps extraPkgs)
    ]);
  in 
  {
    lib = {
      inherit makeJailedCrush;
    };

    devShells.default = pkgs.mkShell {
      packages = [
	pkgs.nixd

	(makeJailedCrush {})
      ];
    };
  });
}
