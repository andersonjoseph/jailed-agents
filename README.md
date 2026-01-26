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
inputs.jailed-agents.url = "github:andersonjoseph/jailed-agents";
```

## Quick Start

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
  };

  outputs = { nixpkgs, jailed-agents, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          (jailed-agents.lib.${system}.makeJailedOpencode {})
        ];
      };
    };
}
```

Run `nix develop` and you'll have the `jailed-opencode` command available. The same pattern works for all pre-configured agents.

## Available Pre-Configured Agents

| Agent | Maker Function | Default Command |
|-------|----------------|-----------------|
| `crush` | `makeJailedCrush` | `jailed-crush` |
| `opencode` | `makeJailedOpencode` | `jailed-opencode` |

Each agent comes with pre-configured config paths and sensible defaults. See the API Reference for customization options.

## Usage Examples

### Basic Usage

```nix
(jailed-agents.lib.${system}.makeJailedOpencode {})
```

All pre-configured agents follow this pattern - just replace `makeJailedOpencode` with the agent builder you want (e.g., `makeJailedCrush`).

### Customizing Pre-Configured Agents

By default, pre-configured agents use packages from [`llm-agents.nix`](https://github.com/numtide/llm-agents.nix). You can override any option:

```nix
# Use a custom package
(jailed-agents.lib.${system}.makeJailedOpencode {
  pkg = pkgs.my-custom-opencode;
})

# Combine custom package with custom name and extra packages
(jailed-agents.lib.${system}.makeJailedOpencode {
  name = "secure-opencode";
  pkg = pkgs.opencode_2_0;
  extraPkgs = [ pkgs.nodejs pkgs.python3 ];
})

# Mount additional directories
(jailed-agents.lib.${system}.makeJailedOpencode {
  extraReadwriteDirs = ["~/projects"];
  extraReadonlyDirs = ["~/readonly-cache"];
})
```

> **Note:** Default command names use the `jailed-` prefix (e.g., `jailed-crush`, `jailed-opencode`) to make it explicit that these are sandboxed versions with restricted permissions. This helps prevent confusion:
>
> - **Expected behavior:** Permission denied errors are normal when the agent tries to access files outside its sandbox
> - **Not a bug:** If you encounter permission issues, the agent is working correctly. It's the sandbox enforcing security
> - **Customize access:** You can customize jail options (e.g., mount additional directories) or open a PR to add missing state/config paths if they should be accessible by default

### Mount Additional Directories

You can mount additional directories with read-write or read-only access:

```nix
# Mount directories with read-write access
(jailed-agents.lib.${system}.makeJailedOpencode {
  extraReadwriteDirs = [
    "~/projects"
    "~/custom-config"
  ];
})

# Mount directories with read-only access
(jailed-agents.lib.${system}.makeJailedCrush {
  extraReadonlyDirs = [
    "~/readonly-cache"
    "/usr/share/something"
  ];
})

# Combine both
(jailed-agents.lib.${system}.makeJailedOpencode {
  extraReadwriteDirs = ["~/projects"];
  extraReadonlyDirs = ["~/readonly-cache"];
})
```

For advanced custom jail options (beyond directory mounting), see the [jail.nix combinators documentation](https://alexdav.id/projects/jail-nix/combinators/).

### Go Development Example

```nix
{
  description = "Go development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
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

Use `makeJailedAgent` for agents not pre-configured by `jailed-agents`:

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

> **Tip:** For supported agents (`crush`, `opencode`), prefer `makeJailedCrush`/`makeJailedOpencode` over `makeJailedAgent` for pre-configured paths and simpler API. Use `makeJailedAgent` only for unsupported agents or when you need full control over the configuration.

## API Reference

### Pre-Configured Agent Builders

All pre-configured agents follow the same pattern:

```nix
makeJailed<agent-name> {
  name ? "jailed-agentname",
  pkg ? default-pkg,
  extraPkgs ? [],
  extraReadwriteDirs ? [],
  extraReadonlyDirs ? [],
  baseJailOptions ? commonJailOptions,
  basePackages ? commonPkgs
}
```

**Parameters:**
- `name` - The command name (default: `"jailed-<agentname>"`)
- `pkg` - The agent package (default: from llm-agents.nix)
- `extraPkgs` - Additional packages to include (optional)
- `extraReadwriteDirs` - Additional directories to mount read/write (optional)
- `extraReadonlyDirs` - Additional directories to mount read-only (optional)
- `baseJailOptions` - Override base jail options (optional)
- `basePackages` - Override base package set (optional)

**Available Builders:**
- `makeJailedCrush` - Pre-configured with crush's config paths
- `makeJailedOpencode` - Pre-configured with opencode's config paths

Each builder includes agent-specific config paths for a seamless experience out of the box.

### makeJailedAgent

```nix
makeJailedAgent {
  name,
  pkg,
  configPaths,
  extraPkgs ? [],
  extraReadwriteDirs ? [],
  extraReadonlyDirs ? [],
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
- `extraReadwriteDirs` - Additional directories to mount read/write (optional)
- `extraReadonlyDirs` - Additional directories to mount read-only (optional)
- `baseJailOptions` - Override base jail options (optional)
- `basePackages` - Override base package set (optional)

### Exposed Utilities

```nix
{
  inherit commonJailOptions;   # Base jail configuration
  inherit commonPkgs;          # Base package set
  inherit makeJailedAgent;     # Generic builder for any agent
  inherit makeJailed<agent-name>;    # Pre-configured <agent-name> agent builder
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

