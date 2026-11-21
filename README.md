# jailed-agents

Secure Nix sandbox for LLM agents. Run AI coding agents in isolated environments with controlled access.

> **Linux only.** The sandbox is built on [`bubblewrap`](https://github.com/containers/bubblewrap), which depends on Linux namespaces and bind mounts. There is no equivalent on macOS. `jailed-agents` supports Linux only.

## Features

- **Zero-Trust Sandbox**: By default, agents have no access to your home directory, SSH keys, or other sensitive files.
- **Sensible Defaults**: A curated set of 14 common packages and secure jail options comes enabled out-of-the-box.
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

Build and run a pre-configured agent with one command:

```bash
nix run github:andersonjoseph/jailed-agents#jailed-opencode
```

For a custom devShell setup, see [Getting Started](https://github.com/andersonjoseph/jailed-agents/wiki/Getting-Started) in the wiki.

> **Note on Security:** The `jailed-` prefix (e.g. `jailed-crush`) makes it clear that you are running a sandboxed version of the agent. If the agent attempts to access a file outside of its approved directories, you will see a "Permission denied" error. This is the sandbox correctly enforcing its security boundaries, not a bug.

## Available Agents

| Agent        | Builder Function       | Default Command     |
| ------------ | ---------------------- | ------------------- |
| `claude-code`| `makeJailedClaudeCode` | `jailed-claude-code`|
| `codex`      | `makeJailedCodex`      | `jailed-codex`      |
| `crush`      | `makeJailedCrush`      | `jailed-crush`      |
| `goose`      | `makeJailedGoose`      | `jailed-goose`      |
| `hermes-agent` | `makeJailedHermesAgent` | `jailed-hermes-agent` |
| `omp`        | `makeJailedOmp`        | `jailed-omp`        |
| `opencode`   | `makeJailedOpencode`   | `jailed-opencode`   |
| `opencode2`  | `makeJailedOpencode2`  | `jailed-opencode2`  |
| `pi`         | `makeJailedPi`         | `jailed-pi`         |

These builders come with sensible defaults and include the necessary config paths for the agent to function correctly out of the box.

## Documentation

The full documentation lives in the [wiki](https://github.com/andersonjoseph/jailed-agents/wiki):

- [Getting Started](https://github.com/andersonjoseph/jailed-agents/wiki/Getting-Started) — install and first run
- [Customization](https://github.com/andersonjoseph/jailed-agents/wiki/Customization) — packages, names, mounts, and environment
- [Git Worktrees](https://github.com/andersonjoseph/jailed-agents/wiki/Git-Worktrees) — run the agent inside git worktrees
- [Integrations](https://github.com/andersonjoseph/jailed-agents/wiki/Integrations) — open URLs on the host, herdr, Nix access
- [Examples](https://github.com/andersonjoseph/jailed-agents/wiki/Examples) — a Go development environment
- [API Reference](https://github.com/andersonjoseph/jailed-agents/wiki/API-Reference) — all builders, options, and defaults

Full documentation as one file for LLMs: [llms.txt](llms.txt).

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
