# jailed-agents

Secure Nix sandbox for LLM agents. Run AI coding agents in isolated environments with controlled access.

## What is it?

`jailed-agents` provides a secure sandbox for running LLM coding agents using Nix and `jail.nix` (which is built on `bubblewrap`). It gives your AI agents the autonomy to be useful without giving them full access to your system.

> **Linux only.** The sandbox is built on [`bubblewrap`](https://github.com/containers/bubblewrap), which depends on Linux namespaces (user, pid, net, …) and bind mounts. These have no equivalent on macOS/Darwin, so `jailed-agents` is **not compatible with Nix on macOS** and currently supports Linux only.

## Features

- **Zero-Trust Sandbox**: By default, agents have no access to your home directory, SSH keys, or other sensitive files.
- **Sensible Defaults**: Comes with a curated set of 14 common packages and secure jail options enabled out-of-the-box.
- **Composable**: Reuse common configurations to create custom, sandboxed environments for your agents.
- **Pre-configured Agents**: Ready-to-use jails for popular agents like `crush`, `opencode`, and `pi`.
- **Custom Agent Builder**: Easily create secure jails for any agent with the `makeJailedAgent` function.
- **Declarative Tooling**: Explicitly define which commands, packages, and directories the agent can access.
- **Seamless Nix Integration**: Works perfectly with your existing Nix Flakes setup.

## Installation

Add `jailed-agents` as an input to your `flake.nix`:

```nix
inputs.jailed-agents.url = "github:andersonjoseph/jailed-agents";
```

## Quick Start

You can use `jailed-agents` in two ways:

### Option 1: Run Pre-built Packages Directly

Build and run a pre-configured agent in one command:

```bash
nix run github:andersonjoseph/jailed-agents#jailed-opencode
```

Or add `jailed-agents` as an input and run:

```bash
nix run .#jailed-opencode
```

### Option 2: Customize with Lib Functions

Add a customized agent to your `devShell`:

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
          (jailed-agents.lib.${system}.makeJailedOpencode {
            extraPkgs = [ pkgs.nodejs pkgs.python3 ];
          })
        ];
      };
    };
}
```

Run `nix develop`, and the `jailed-opencode` command will be available in your shell.

> **Note on Security:** The `jailed-` prefix (e.g., `jailed-crush`) makes it clear that you are running a sandboxed version of the agent. If the agent attempts to access a file outside of its approved directories, you will see a "Permission denied" error. This is the sandbox correctly enforcing its security boundaries, not a bug.

## Available Agents

`jailed-agents` provides pre-configured builders for the following agents:

| Agent        | Builder Function       | Default Command     |
| ------------ | ---------------------- | ------------------- |
| `claude-code`| `makeJailedClaudeCode` | `jailed-claude-code`|
| `codex`      | `makeJailedCodex`      | `jailed-codex`      |
| `crush`      | `makeJailedCrush`      | `jailed-crush`      |
| `goose`      | `makeJailedGoose`      | `jailed-goose`      |
| `hermes-agent` | `makeJailedHermesAgent` | `jailed-hermes-agent` |
| `opencode`   | `makeJailedOpencode`   | `jailed-opencode`   |
| `pi`         | `makeJailedPi`         | `jailed-pi`         |

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

Some agents read from directories beyond their defaults. For example, Goose also uses `~/.agents` for global hints (`AGENTS.md`) and its installed-agents/plugins features — mount it if you rely on those:

```nix
(jailed-agents.lib.${system}.makeJailedGoose {
  extraReadwriteDirs = [ "~/.agents" ];
})
```

### Set Environment Variables

Set environment variables inside the jail.

```nix
(jailed-agents.lib.${system}.makeJailedPi {
  env = {
    EDITOR = "${pkgs.neovim}/bin/nvim";
    VISUAL = "${pkgs.neovim}/bin/nvim";
  };
})
```

### Forward Environment Variables

Set environment variables inside the jail by copying them from the outside.
```nix
(jailed-agents.lib.${system}.makeJailedPi {
  fwdEnv = [ "PKG_CONFIG_PATH" ];
})
```

Take care to not forward any secrets. Trying to forward nonexistent variables will result in an error.

### Running under herdr

[herdr](https://herdr.dev) detects jailed agents and shows their working/idle/blocked state in its sidebar with **no jail changes** — it reads the pane's screen from the host. Because the sandbox hides the real foreground process, give herdr a hint so it applies the right screen manifest:

```bash
HERDR_AGENT=pi jailed-pi        # use herdr's `pi` manifest for this pane
```

`HERDR_AGENT` is a host-side env var on the wrapper command (one of herdr's known agents: `pi`, `claude`, `codex`, etc), not something configured inside the jail. If herdr still can't see the agent process (some `bubblewrap` setups don't expose a terminal foreground process group), start the herdr server with `HERDR_PROCESS_DETECTION=child-groups`.

> **Why not expose the herdr socket to the jail?** herdr's socket is a control API. It spawn panes, run commands, send keystrokes. Herdr serves with your full host privileges, and it doesn't distinguish sandboxed callers. Exposing it would let the agent open panes in directories the jail forbids, defeating the sandbox. So jailed-agents does **not** wire the socket in. The `HERDR_AGENT` hint gives you herdr's state tracking without that hole.

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

> **Tip:** Prefer using the pre-configured builders (`makeJailedCrush`, `makeJailedOpencode`, `makeJailedPi`) when possible, as they provide simpler APIs and sensible defaults. Use `makeJailedAgent` only for unsupported agents or for full control.

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
  env ? {},
  fwdEnv ? [],
  enableNix ? false,
  nixConfigDir ? null,
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
  env ? {},
  fwdEnv ? [],
  enableNix ? false,
  nixConfigDir ? null,
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
- **`env`**: An attribute set of environment variables to set inside the jail (e.g. `{ EDITOR = "nvim"; }`).
- **`fwdEnv`**: A list of environment variables to forward from the host shell into the jail (e.g. `[ "PKG_CONFIG_PATH" ]`). Errors at startup if a variable is unset.
- **`enableNix`**: When `true`, grants the agent access to the host Nix daemon: mounts `/nix` and `/etc/nix/nix.conf` read-only, the daemon socket `/nix/var/nix/daemon-socket` read-write, and adds the `nix` package.

  > **Warning:** `enableNix = true` lets the agent build and execute arbitrary packages from nixpkgs via the Nix daemon, bypassing the sandbox's curated toolset. Only enable it for agents you trust to run arbitrary code.

- **`nixConfigDir`**: Mounts a NixOS/system config directory into the jail so the agent can read (or edit) the declaration. Pass a path string to mount it read-only (e.g. `"/etc/nixos"`), or `{ path = "/etc/nixos"; writable = true; }` to mount it read-write. Defaults to `null` (nothing mounted). Independent of `enableNix`.
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
