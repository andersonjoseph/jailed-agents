# jailed-agents

Secure Nix sandbox for LLM agents. Run AI coding agents in isolated environments with controlled access.

## What is it?

`jailed-agents` provides a secure sandbox for running LLM coding agents using Nix and `jail.nix` (which is built on `bubblewrap`). It gives your AI agents the autonomy to be useful without giving them full access to your system.

## Features

- **Zero-Trust Sandbox**: By default, agents have no access to your home directory, SSH keys, or other sensitive files.
- **Sensible Defaults**: Comes with a curated set of 14 common packages and secure jail options enabled out-of-the-box.
- **Composable**: Reuse common configurations to create custom, sandboxed environments for your agents.
- **Pre-configured Agents**: Ready-to-use jails for popular agents like `crush` and `opencode`.
- **Custom Agent Builder**: Easily create secure jails for any agent with the `makeJailedAgent` function.
- **Declarative Tooling**: Explicitly define which commands, packages, and directories the agent can access.
- **Seamless Nix Integration**: Works perfectly with your existing Nix Flakes setup.

## Installation

Add `jailed-agents` as an input to your `flake.nix`:

```nix
inputs.jailed-agents.url = "github:andersonjoseph/jailed-agents";
```

## Quick Start

To get started, add a pre-configured agent to your `devShell`. This example uses `jailed-opencode`.

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
          # Add the jailed agent to your shell
          (jailed-agents.lib.${system}.makeJailedOpencode {})
        ];
      };
    };
}
```

Run `nix develop`, and the `jailed-opencode` command will be available in your shell.

> **Note on Security:** The `jailed-` prefix (e.g., `jailed-crush`) makes it clear that you are running a sandboxed version of the agent. If the agent attempts to access a file outside of its approved directories, you will see a "Permission denied" error. This is the sandbox correctly enforcing its security boundaries, not a bug.

## Available Agents

`jailed-agents` provides pre-configured builders for the following agents:

| Agent      | Builder Function     | Default Command   |
| ---------- | -------------------- | ----------------- |
| `crush`    | `makeJailedCrush`    | `jailed-crush`    |
| `gemini-cli`| `makeJailedGeminiCli`| `jailed-gemini-cli`|
| `opencode` | `makeJailedOpencode` | `jailed-opencode` |

These builders come with sensible defaults and include the necessary config paths for the agent to function correctly out of the box.

## Customization

You can customize agents by overriding the default options.

### Use a Custom Package or Name

Override the agent's package or change the command name.

```nix
(jailed-agents.lib.${system}.makeJailedOpencode {
  name = "secure-opencode";
  pkg = pkgs.opencode_2_0;
})
```

### Add Extra Packages

Include additional packages in the sandbox environment.

```nix
(jailed-agents.lib.${system}.makeJailedOpencode {
  extraPkgs = [ pkgs.nodejs pkgs.python3 ];
})
```

### Mount Additional Directories

Provide read-write or read-only access to directories.

```nix
(jailed-agents.lib.${system}.makeJailedOpencode {
  extraReadwriteDirs = ["~/projects"];
  extraReadonlyDirs = ["~/readonly-cache"];
})
```

### Create a Custom Agent

If an agent is not pre-configured, you can easily create a jail for it using `makeJailedAgent`.

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

> **Tip:** Prefer using the pre-configured builders (`makeJailedCrush`, `makeJailedOpencode`) when possible, as they provide simpler APIs and sensible defaults. Use `makeJailedAgent` only for unsupported agents or for full control.

### Advanced Customization

For ultimate control, you can use the `internals` API to access the underlying `jail.nix` combinators. This allows you to modify base jail options, such as disabling network access.

```nix
let
  jail = jailed-agents.lib.${system}.internals.jail;
  combinators = jail.combinators;
in
{
  # Example: Disable network access for opencode
  packages.x86_64-linux.opencode-no-net = jailed-agents.lib.${system}.makeJailedOpencode {
    baseJailOptions = [
      combinators.time-zone
      combinators.no-new-session
      combinators.mount-cwd
    ];
  };
}
```

For a complete reference on available combinators, see the [jail.nix combinators documentation](https://alexdav.id/projects/jail-nix/combinators/).

## Go Development Example

Here is an example of how to set up a Go development environment with a jailed `crush` agent that has access to the Go toolchain.

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

          # Provide the Go toolchain to the jailed agent
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

## API Reference

### Pre-configured Builders (`makeJailed<AgentName>`)

```nix
makeJailed<AgentName> {
  name ? "jailed-<agent-name>",
  pkg ? /* default package from llm-agents.nix */,
  extraPkgs ? [],
  extraReadwriteDirs ? [],
  extraReadonlyDirs ? [],
  baseJailOptions ? commonJailOptions,
  basePackages ? commonPkgs
}
```

### Custom Agent Builder (`makeJailedAgent`)

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

- **`name`**: (Required) The command name for the jailed agent.
- **`pkg`**: (Required) The agent package to sandbox.
- **`configPaths`**: (Required for `makeJailedAgent`) A list of essential configuration paths the agent needs read-write access to (e.g., `["~/.config/my-agent"]`).
- **`extraPkgs`**: A list of additional packages to include in the sandbox.
- **`extraReadwriteDirs`**: A list of directories to mount with read-write access.
- **`extraReadonlyDirs`**: A list of directories to mount with read-only access.
- **`baseJailOptions`**: Overrides the default set of jail options.
- **`basePackages`**: Overrides the default set of base packages.

### What's Included by Default

- **Common Packages**: All agents include `bash`, `curl`, `wget`, `jq`, `git`, `ripgrep`, `gnugrep`, `gawk`, `ps`, `findutils`, `gzip`, `unzip`, `gnutar`, and `diffutils`.
- **Common Jail Options**: All jails include network access, system timezone propagation, prevention of new session creation, and mounting of the current working directory.

## Why Not Docker?

Docker is a heavy solution for this use case and would require you to duplicate your Nix environment inside a Dockerfile. `jailed-agents` is built on technologies that integrate seamlessly with a Nix-based workflow:

- **`bubblewrap`**: The same lightweight sandboxing technology used by Flatpak.
- **`jail.nix`**: A declarative, Nix-native library for building `bubblewrap` sandboxes.
- **Nix Flakes**: Integrates directly into your existing development environment without extra overhead.

## Contributing

Contributions are welcome! Please feel free to open a pull request for:

- New pre-configured agent setups
- Additional composable building blocks
- Bug fixes and general improvements

## Credits

This project is built on the great work of others:

- [jail.nix](https://alexdav.id/projects/jail-nix/) by Alex David
- [llm-agents.nix](https://github.com/numtide/llm-agents.nix) by Numtide
- [bubblewrap](https://github.com/containers/bubblewrap)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
