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

  if ! nix build ".#$package"; then
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

if ! nix build "./tests"; then
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

if ! nix build "./tests#nix-enabled-test"; then
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
if ! nix build "./tests#nixconfig-readonly-test"; then
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
if ! nix build "./tests#nixconfig-writable-test"; then
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

# --- Summary ---
echo "----------------------------------------"
echo "Results: $pass passed, $fail failed"

if [ "$fail" -ne 0 ]; then
  exit 1
fi

# --- Test common tools availability ---
echo "----------------------------------------"
echo "Testing common tools availability..."

if ! nix build "./tests#tools-test"; then
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
