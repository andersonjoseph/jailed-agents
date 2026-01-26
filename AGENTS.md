# AGENTS.md

Guidelines for agentic coding assistants working on `jailed-agents`.

## Development Commands

### Formatting
```bash
nixfmt
```
Format all Nix files using `nixfmt`.

### Linting
```bash
nix shell nixpkgs#statix -c statix check
```
Check for Nix code style issues.

### Building
```bash
nix build .#<package>
```
Build any package from flake outputs. Use `llm-agents.packages.${system}.<agent>` pattern for package access.

### Testing
No external tests. Create a test flake that imports this repository, build the agent config, and verify sandbox constraints:

```nix
{
  inputs.jailed-agents.url = "path:/path/to/jailed-agents";
  outputs = { jailed-agents, ... }: {
    packages.x86_64-linux.default = jailed-agents.lib.x86_64-linux.makeJailedOpencode {};
  };
}
```

### Development Shell
```bash
nix develop
```
Enter dev shell with nixd, nixfmt, statix, and jailed agents.

## Code Style Guidelines

### Nix Formatting
- Use `nixfmt` for all Nix files (automatically applied via `nix fmt`)
- 2-space indentation for nested structures
- Keep line length reasonable (~100 characters, but not strictly enforced)
- Use trailing commas in multi-line lists and attribute sets

### Function Definitions
- Use camelCase for function names (e.g., `makeJailedAgent`, `makeJailedCrush`)
- Define parameters with `? []` pattern for defaults (e.g., `extraPkgs ? []`)
- Align parameters on new lines for multi-argument functions:

```nix
makeJailedAgent = {
  name,
  pkg,
  configPaths,
  extraPkgs ? [],
  baseJailOptions ? commonJailOptions,
  basePackages ? commonPkgs,
}: ...
```

### Imports and Scope
- Use `with pkgs;` for package imports when building package lists
- Use `with jail.combinators;` when using jail combinators
- Avoid mixing `with` statements in the same scope
- Use `inherit` for passing multiple attributes vertically:

```nix
makeJailedAgent {
  inherit
    name
    pkg
    extraPkgs
    baseJailOptions
    ;
  configPaths = ["~/.config/app"];
};
```

### Lists and Attributes
- Place list items on separate lines with proper indentation and trailing commas
- Example: `commonPkgs = with pkgs; [ bashInteractive curl wget jq git ];`
- Add empty lines between logical sections in let-bindings (e.g., between `commonPkgs` and `commonJailOptions`)
- Use trailing semicolon for multi-line `inherit` blocks

### Naming Conventions
- Functions: `camelCase` (e.g., `makeJailedCrush`, `makeJailedOpencode`)
- Variables: `camelCase` (e.g., `commonJailOptions`, `basePackages`)
- Constants: `camelCase` (e.g., `commonPkgs`)
- Parameter names: `camelCase` (e.g., `configPaths`, `extraPkgs`)
- Package names: lowercase with hyphens (e.g., `bashInteractive`, `gnugrep`)

### Library Structure
- Export all public functions via `lib` attribute
- Keep common utilities at top-level (e.g., `commonJailOptions`, `commonPkgs`)
- Separate builder functions from utility exports: `lib = { inherit commonJailOptions commonPkgs jail makeJailedAgent makeJailedCrush makeJailedOpencode; };`
- Use `internals` namespace for non-public exports (e.g., `jail` object)
- Use `eachDefaultSystem` from flake-utils for multi-platform support

### Error Handling
- Nix flake outputs will fail automatically at evaluation time if errors exist
- Use `lib.init pkgs` pattern for jail initialization
- Ensure all required parameters are validated in function signatures

### Nixpkgs Configuration
- Set `config.allowUnfree = true` when importing nixpkgs to support all packages
- Pattern: `pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };`

### Path Handling
- Use `noescape` combinator for home directory paths to prevent expansion
- Pattern: `(readwrite (noescape "~/.config/appname"))`
- Use `noescape` for any path containing `~` or other shell expansions
- Separate readwrite and readonly directory mounting with `++` operator in jail combinators

### Comments
- No inline comments in current codebase - keep it minimal
- Use descriptive function names and parameter names instead of comments
- Documentation lives in README.md and API reference sections

### Adding New Agents
To add support for a new agent, create a builder that calls `makeJailedAgent` with agent-specific `configPaths`:

```nix
makeJailed<AgentName> = { name ? "jailed-agentname", pkg ? llm-agents.packages.${system}.<agent-name>, extraPkgs ? [], extraReadwriteDirs ? [], extraReadonlyDirs ? [], baseJailOptions ? commonJailOptions, basePackages ? commonPkgs, }:
makeJailedAgent { inherit name pkg extraPkgs extraReadwriteDirs extraReadonlyDirs baseJailOptions basePackages; configPaths = [ "~/.config/<agent>" "~/.local/share/<agent>" ]; };
```

Export via `lib` attribute and update README.md documentation.

### Commit Message Style
- Use lowercase, concise messages (e.g., "add name/alias to packages")
- Keep messages short and descriptive
- No period at end of commit message

## Project Structure

```
.
├── flake.nix              # Main library with all builder functions
├── flake.lock             # Lock file for reproducible builds
├── README.md              # User documentation
├── LICENSE                # MIT License
└── .crush/               # Crush agent state (gitignored)
```

## Key Dependencies

- `jail-nix`: Provides the `jail` library and combinators for creating sandboxes
- `llm-agents.nix`: Provides pre-built agent packages (crush, opencode)
- `nixpkgs`: Base package set
- `flake-utils`: Provides `eachDefaultSystem` utility

## Security Considerations

This project creates secure sandboxes. When making changes, always preserve the principle of least privilege, default to no access before granting permissions, never expose sensitive files (SSH keys, home directory) by default, and test that permission denied errors are appropriate when agents try to access forbidden resources.
