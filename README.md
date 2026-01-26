# jailed-agents

Secure Nix sandbox for LLM agents. Run AI coding agents in isolated environments with controlled access.

## What is it?

`jailed-agents` provides a secure sandbox for running LLM coding agents using Nix and `jail.nix` (built on `bubblewrap`). It gives your AI agents the autonomy to be useful without giving them full access to your system.

## Features

- **Zero-trust sandbox** - No access to your home directory, SSH keys, or sensitive files by default
- **Composable building blocks** - Reuse common configurations and create custom jails
- **Pre-configured agents** - Ready-to-use jails for `crush` and `opencode` agents
- **Custom agent builder** - Create secure jails for any agent with `makeJailedAgent`
- **Configurable tools** - Explicitly approve which commands and packages the agent can use
- **Seamless Nix integration** - Works perfectly with your existing Nix Flakes setup

## Installation

Add `jailed-agents` as a flake input:

```nix
inputs.jailed-agents.url = "github:username/jailed-agents";
```

## Quick Start

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jailed-agents.url = "github:username/jailed-agents";
  };

  outputs = { nixpkgs, jailed-agents, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (jailed-agents.lib.${system}.makeJailedCrush {})
          (jailed-agents.lib.${system}.makeJailedOpencode {})
        ];
      };
    };
}
```

Run `nix develop` and you'll have `jailed-crush` and `jailed-opencode` commands available.

## Usage Examples

### Basic Usage

```nix
(jailed-agents.lib.${system}.makeJailedCrush {})
(jailed-agents.lib.${system}.makeJailedOpencode {})
```

### Custom Command Names

```nix
# Use default names: jailed-crush, jailed-opencode
(jailed-agents.lib.${system}.makeJailedCrush {})
(jailed-agents.lib.${system}.makeJailedOpencode {})

# Customize the command names
(jailed-agents.lib.${system}.makeJailedCrush { name = "crush"; })
(jailed-agents.lib.${system}.makeJailedOpencode { name = "secure-opencode"; })
```

> **Note:** Default command names use the `jailed-` prefix (e.g., `jailed-crush`, `jailed-opencode`) to make it explicit that these are sandboxed versions with restricted permissions. This helps prevent confusion:
>
> - **Expected behavior:** Permission denied errors are normal when the agent tries to access files outside its sandbox
> - **Not a bug:** If you encounter permission issues, the agent is working correctly—it's the sandbox enforcing security
> - **Customize access:** You can customize jail options (e.g., mount additional directories) or open a PR to add missing state/config paths if they should be accessible by default

### Adding Extra Packages

```nix
(jailed-agents.lib.${system}.makeJailedCrush {
  extraPkgs = [ pkgs.nodejs pkgs.python3 ];
})
```

### Go Development Example

```nix
{
  description = "Go development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jailed-agents.url = "github:username/jailed-agents";
  };

  outputs = { nixpkgs, jailed-agents }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        hardeningDisable = [ "fortify" ];
        packages = with pkgs; [
          go
          gopls
          golangci-lint
          go-task

          (jailed-agents.lib.${system}.makeJailedCrush {
            extraPkgs = [
              go
              gopls
              golangci-lint
              go-task
              libgcc
              gcc
            ];
          })
        ];
      };
    };
}
```

### Custom Agent

```nix
(jailed-agents.lib.${system}.makeJailedAgent {
  name = "my-custom-agent";
  pkg = pkgs.my-agent-package;
  configPaths = [
    "~/.config/my-agent"
    "~/.local/share/my-agent"
  ];
  extraPkgs = [
    pkgs.pandoc
    pkgs.ffmpeg
  ];
})
```

## API Reference

### makeJailedCrush

```nix
makeJailedCrush {
  name ? "jailed-crush",
  extraPkgs ? [],
  baseJailOptions ? commonJailOptions,
  basePackages ? commonPkgs
}
```

Creates a jailed environment for the `crush` agent.

**Parameters:**
- `name` - The command name (default: "jailed-crush")
- `extraPkgs` - Additional packages to include (optional)
- `baseJailOptions` - Override base jail options (optional)
- `basePackages` - Override base package set (optional)

### makeJailedOpencode

```nix
makeJailedOpencode {
  name ? "jailed-opencode",
  extraPkgs ? [],
  baseJailOptions ? commonJailOptions,
  basePackages ? commonPkgs
}
```

Creates a jailed environment for the `opencode` agent.

**Parameters:**
- `name` - The command name (default: "jailed-opencode")
- `extraPkgs` - Additional packages to include (optional)
- `baseJailOptions` - Override base jail options (optional)
- `basePackages` - Override base package set (optional)

### makeJailedAgent

```nix
makeJailedAgent {
  name,
  pkg,
  configPaths,
  extraPkgs ? [],
  baseJailOptions ? commonJailOptions,
  basePackages ? commonPkgs
}
```

Creates a generic jailed environment for any agent.

**Parameters:**
- `name` - The name of the jail
- `pkg` - The agent package to run
- `configPaths` - List of paths to mount read/write (e.g., `["~/.config/my-app"]`)
- `extraPkgs` - Additional packages to include (optional)
- `baseJailOptions` - Override base jail options (optional)
- `basePackages` - Override base package set (optional)

### Exposed Utilities

```nix
{
  inherit commonJailOptions;  # Base jail configuration
  inherit commonPkgs;         # Base package set
  inherit jail;               # Raw jail reference for custom builds
  inherit makeJailedAgent;    # Generic builder
  inherit makeJailedCrush;     # Crush agent builder
  inherit makeJailedOpencode; # Opencode agent builder
}
```

## Why Not Docker?

Docker feels heavy for sandboxing AI agents and requires duplicating your Nix environment in a Dockerfile. `jailed-agents` leverages:
- **`bubblewrap`** - Lightweight sandboxing (same tech as Flatpak)
- **`jail.nix`** - Declarative, Nix-native library for building bubblewrap sandboxes
- **Nix Flakes** - Seamless integration with your existing development setup

## License

MIT License - see [LICENSE](LICENSE) file for details

## Contributing

Contributions are welcome! We accept PRs for:
- New agent configurations
- Composable building blocks
- Bug fixes and improvements

## Credits

Built with:
- [jail.nix](https://alexdav.id/projects/jail-nix/) by Alex David
- [llm-agents.nix](https://github.com/numtide/llm-agents.nix) by Numtide
- [bubblewrap](https://github.com/containers/bubblewrap)

