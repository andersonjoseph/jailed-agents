#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Agents to build and smoke-test
packages=(
  jailed-crush
  jailed-goose
  jailed-opencode
  jailed-hermes-agent
  jailed-claude-code
  jailed-codex
  jailed-pi
)

pass=0
fail=0

# --- Ensure each agent's config/data dirs exist so bwrap can bind-mount them ---
mkdir -p \
  ~/.config/crush ~/.local/share/crush \
  ~/.config/goose ~/.local/share/goose ~/.local/state/goose \
  ~/.config/opencode ~/.local/share/opencode ~/.local/state/opencode \
  ~/.hermes ~/.claude ~/.codex ~/.pi
touch ~/.claude.json

# --- Build and smoke-test each agent ---
for package in "${packages[@]}"; do
  echo "----------------------------------------"
  echo "Building and testing $package..."

  if ! nix build --accept-flake-config ".#$package"; then
    echo "ERROR: Failed to build $package."
    ((fail++)) || true
    continue
  fi

  echo "Build successful. Testing the binary..."

  if ./result/bin/"$package" --help; then
    echo "SUCCESS: $package built and tested successfully."
    ((pass++)) || true
  else
    echo "ERROR: Test for $package failed."
    ((fail++)) || true
  fi
done

# --- Test env parameter propagation ---
echo "----------------------------------------"
echo "Testing env parameter propagation..."

if ! nix build --accept-flake-config "./tests"; then
  echo "ERROR: Failed to build env-test."
  ((fail++)) || true
else
  output=$(./result/bin/env-test -c 'echo "$MY_TEST_VAR $ANOTHER_VAR"')
  if [ "$output" = "hello world" ]; then
    echo "SUCCESS: env vars correctly set in jail"
    ((pass++)) || true
  else
    echo "ERROR: expected 'hello world', got '$output'"
    ((fail++)) || true
  fi
fi

# --- Test enableNix (nix binary + daemon mounts) ---
echo "----------------------------------------"
echo "Testing enableNix..."

if ! nix build --accept-flake-config "./tests#nix-enabled-test"; then
  echo "ERROR: Failed to build nix-enabled-test."
  ((fail++)) || true
else
  if ./result/bin/nix-enabled-test -c 'nix --version' \
    && ./result/bin/nix-enabled-test -c 'ls /nix/store >/dev/null' \
    && ./result/bin/nix-enabled-test -c 'ls /nix/var/nix/daemon-socket >/dev/null'; then
    echo "SUCCESS: nix binary and daemon mounts present in jail"
    ((pass++)) || true
  else
    echo "ERROR: nix binary or daemon mounts not accessible in jail"
    ((fail++)) || true
  fi

  if ./result/bin/nix-enabled-test -c 'nix store info >/dev/null 2>&1'; then
    echo "SUCCESS: nix daemon reachable from inside the jail"
    ((pass++)) || true
  else
    echo "ERROR: nix daemon not reachable from inside the jail"
    ((fail++)) || true
  fi
fi

# --- Test nixConfigDir readonly vs writable ---
echo "----------------------------------------"
echo "Testing nixConfigDir readonly/writable..."

NIXCFG_DIR="/tmp/jailed-agents-nixconfig-test"
rm -rf "$NIXCFG_DIR"
mkdir -p "$NIXCFG_DIR"
echo "sentinel" > "$NIXCFG_DIR/configuration.nix"

# readonly: read works, write fails
if ! nix build --accept-flake-config "./tests#nixconfig-readonly-test"; then
  echo "ERROR: Failed to build nixconfig-readonly-test."
  ((fail++)) || true
else
  ro_read=$(./result/bin/nixconfig-readonly-test -c 'cat /tmp/jailed-agents-nixconfig-test/configuration.nix' 2>/dev/null || true)
  ro_write_failed=0
  ./result/bin/nixconfig-readonly-test -c 'echo mutated > /tmp/jailed-agents-nixconfig-test/configuration.nix' 2>/dev/null || ro_write_failed=1
  if [ "$ro_read" = "sentinel" ] && [ "$ro_write_failed" -eq 1 ]; then
    echo "SUCCESS: nixConfigDir readonly mounts read-only"
    ((pass++)) || true
  else
    echo "ERROR: nixConfigDir readonly misbehaved (read='$ro_read', write_failed=$ro_write_failed)"
    ((fail++)) || true
  fi
fi

# writable: read and write both succeed
if ! nix build --accept-flake-config "./tests#nixconfig-writable-test"; then
  echo "ERROR: Failed to build nixconfig-writable-test."
  ((fail++)) || true
else
  echo "sentinel" > "$NIXCFG_DIR/configuration.nix"
  rw_read=$(./result/bin/nixconfig-writable-test -c 'cat /tmp/jailed-agents-nixconfig-test/configuration.nix' 2>/dev/null || true)
  rw_write_ok=1
  ./result/bin/nixconfig-writable-test -c 'echo mutated > /tmp/jailed-agents-nixconfig-test/configuration.nix' 2>/dev/null || rw_write_ok=0
  rw_after=$(./result/bin/nixconfig-writable-test -c 'cat /tmp/jailed-agents-nixconfig-test/configuration.nix' 2>/dev/null || true)
  if [ "$rw_read" = "sentinel" ] && [ "$rw_write_ok" -eq 1 ] && [ "$rw_after" = "mutated" ]; then
    echo "SUCCESS: nixConfigDir writable mounts read-write"
    ((pass++)) || true
  else
    echo "ERROR: nixConfigDir writable misbehaved (read='$rw_read', write_ok=$rw_write_ok, after='$rw_after')"
    ((fail++)) || true
  fi
fi

rm -rf "$NIXCFG_DIR"

# --- Test git worktree support (enableGitWorktrees) ---
echo "----------------------------------------"
echo "Testing enableGitWorktrees..."

WT_ROOT="$HOME/jailed-agents-wt-test"
rm -rf "$WT_ROOT"
mkdir -p "$WT_ROOT"
git -C "$WT_ROOT" init -q main
git -C "$WT_ROOT/main" config user.email t@t.com
git -C "$WT_ROOT/main" config user.name tester
git -C "$WT_ROOT/main" config commit.gpgsign false
echo hi > "$WT_ROOT/main/README.md"
git -C "$WT_ROOT/main" add -A
git -C "$WT_ROOT/main" commit -qm init
git -C "$WT_ROOT/main" worktree add "$WT_ROOT/wt-feature" -b feature

# (A) + (B) work inside an existing worktree: resolver mounts the shared .git
if ! nix build "./tests#git-worktree-test"; then
  echo "ERROR: Failed to build git-worktree-test."
  ((fail++)) || true
else
  GWT_BIN="$(realpath ./result/bin/git-worktree-test)"

  wt_log="$(cd "$WT_ROOT/wt-feature" && "$GWT_BIN" log --oneline 2>&1)" || true
  if printf '%s' "$wt_log" | grep -q "init"; then
    echo "SUCCESS: git resolves shared .git from inside a worktree"
    ((pass++)) || true
  else
    echo "ERROR: worktree git resolution failed: $wt_log"
    ((fail++)) || true
  fi

  (cd "$WT_ROOT/wt-feature" && echo more >> README.md && "$GWT_BIN" add -A && "$GWT_BIN" commit -qm wt-commit) || true
  if git -C "$WT_ROOT/main" log --oneline feature 2>/dev/null | grep -q "wt-commit"; then
    echo "SUCCESS: commit from worktree reaches the shared object store"
    ((pass++)) || true
  else
    echo "ERROR: worktree commit did not reach shared store"
    ((fail++)) || true
  fi

  # (D) regression: a crafted .git gitdir-file must NOT bind another repo's .git
  WT_SECRET="$HOME/jailed-agents-wt-secret"
  WT_ATTACK="$HOME/jailed-agents-wt-attack"
  rm -rf "$WT_SECRET" "$WT_ATTACK"
  mkdir -p "$WT_SECRET" "$WT_ATTACK"
  git -C "$WT_SECRET" init -q
  git -C "$WT_SECRET" config user.email leaked@example.com
  printf 'gitdir: %s/.git\n' "$WT_SECRET" > "$WT_ATTACK/.git"
  attack_out="$(cd "$WT_ATTACK" && "$GWT_BIN" config --get user.email 2>&1)" || true
  (cd "$WT_ATTACK" && "$GWT_BIN" config backdoor.pwned yes 2>/dev/null) || true
  host_backdoor="$(git -C "$WT_SECRET" config --get backdoor.pwned 2>/dev/null || true)"
  if printf '%s' "$attack_out" | grep -q "leaked@example.com" || [ -n "$host_backdoor" ]; then
    echo "ERROR: crafted .git pointer leaked into another repo (read='$attack_out', backdoor='$host_backdoor')"
    ((fail++)) || true
  else
    echo "SUCCESS: crafted .git pointer does not bind another repo's .git"
    ((pass++)) || true
  fi
  rm -rf "$WT_SECRET" "$WT_ATTACK"
fi

# (C) create new worktrees from inside via enableGitWorktrees.dir
WT_CREATE_DIR="$HOME/jailed-agents-wt-create-test"
if ! nix build "./tests#git-worktree-create-test"; then
  echo "ERROR: Failed to build git-worktree-create-test."
  ((fail++)) || true
else
  GWT_CREATE_BIN="$(realpath ./result/bin/git-worktree-create-test)"
  rm -rf "$WT_CREATE_DIR"
  mkdir -p "$WT_CREATE_DIR"
  (cd "$WT_ROOT/wt-feature" && "$GWT_CREATE_BIN" worktree add "$WT_CREATE_DIR/inner" -b inner) || true
  if [ -f "$WT_CREATE_DIR/inner/README.md" ] \
     && git -C "$WT_ROOT/main" worktree list 2>/dev/null | grep -q "$WT_CREATE_DIR/inner"; then
    echo "SUCCESS: agent created a worktree into the configured dir"
    ((pass++)) || true
  else
    echo "ERROR: agent could not create worktree in configured dir"
    ((fail++)) || true
  fi
fi

# (E) mountGitConfig: the global ~/.gitconfig is visible inside the jail
if ! nix build "./tests#git-worktree-gitconfig-test"; then
  echo "ERROR: Failed to build git-worktree-gitconfig-test."
  ((fail++)) || true
else
  GWT_GC_BIN="$(realpath ./result/bin/git-worktree-gitconfig-test)"
  GC_HOME="$(mktemp -d)"
  # global-only key, so repo-local identity cannot mask it
  printf '[gwt]\n\tidentity = global\n' > "$GC_HOME/.gitconfig"
  gc_out="$(cd "$WT_ROOT/wt-feature" && HOME="$GC_HOME" "$GWT_GC_BIN" config --get gwt.identity 2>&1)" || true
  if printf '%s' "$gc_out" | grep -q "global"; then
    echo "SUCCESS: mountGitConfig exposes the global ~/.gitconfig"
    ((pass++)) || true
  else
    echo "ERROR: mountGitConfig did not expose global gitconfig (got '$gc_out')"
    ((fail++)) || true
  fi
  rm -rf "$GC_HOME"
fi

rm -rf "$WT_ROOT" "$WT_CREATE_DIR"

# --- Summary ---
echo "----------------------------------------"
echo "Results: $pass passed, $fail failed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi

# --- Test common tools availability ---
echo "----------------------------------------"
echo "Testing common tools availability..."

if ! nix build --accept-flake-config "./tests#tools-test"; then
  echo "ERROR: Failed to build tools-test."
  ((fail++)) || true
else
  output=$(./result/bin/tools-test -c 'echo "hello world" | sed "s/world/sed/"')
  if [ "$output" = "hello sed" ]; then
    echo "SUCCESS: sed available and working in jail"
    ((pass++)) || true
  else
    echo "ERROR: expected 'hello sed', got '$output'"
    ((fail++)) || true
  fi
fi

echo "----------------------------------------"
