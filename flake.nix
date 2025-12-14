{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, jail-nix, llm-agents, ... }:
  let 
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      system = system;
      config.allowUnfree = true;
    };
    jail = jail-nix.lib.init pkgs;
    crush-pkg = llm-agents.packages.${system}.crush;
  in 
  {
    jailed-crush = jail "jailed-crush" crush-pkg (with jail.combinators; [
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

	  pkgs.gopls
	  pkgs.go
	])
    ]);

    packages.${system}.default = self.jailed-crush;

    devShells.${system}.default = pkgs.mkShell {
      packages = [
	self.jailed-crush
      ];
    };
  };
}
