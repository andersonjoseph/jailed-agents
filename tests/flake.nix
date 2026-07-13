{
  inputs.jailed-agents.url = "path:..";

  outputs =
    { jailed-agents, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      packages.${system} = {
        default = jailed-agents.lib.${system}.makeJailedAgent {
          name = "env-test";
          pkg = pkgs.bashInteractive;
          configPaths = [ ];
          env = {
            MY_TEST_VAR = "hello";
            ANOTHER_VAR = "world";
          };
        };

        tools-test = jailed-agents.lib.${system}.makeJailedAgent {
          name = "tools-test";
          pkg = pkgs.bashInteractive;
          configPaths = [ ];
        };

        nix-enabled-test = jailed-agents.lib.${system}.makeJailedAgent {
          name = "nix-enabled-test";
          pkg = pkgs.bashInteractive;
          configPaths = [ ];
          enableNix = true;
        };

        nixconfig-readonly-test = jailed-agents.lib.${system}.makeJailedAgent {
          name = "nixconfig-readonly-test";
          pkg = pkgs.bashInteractive;
          configPaths = [ ];
          nixConfigDir = "/tmp/jailed-agents-nixconfig-test";
        };

        nixconfig-writable-test = jailed-agents.lib.${system}.makeJailedAgent {
          name = "nixconfig-writable-test";
          pkg = pkgs.bashInteractive;
          configPaths = [ ];
          nixConfigDir = {
            path = "/tmp/jailed-agents-nixconfig-test";
            writable = true;
          };
        };
      };
    };
}
