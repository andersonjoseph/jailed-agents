#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Agents to build and smoke-test
packages=(
  jailed-crush
  jailed-goose
  jailed-opencode
  jailed-opencode2
  jailed-hermes-agent
  jailed-claude-code
  jailed-codex
  jailed-pi
  jailed-omp
)

pass=0
fail=0

# --- Ensure each agent's config/data dirs exist so bwrap can bind-mount them ---
mkdir -p \
  ~/.config/crush ~/.local/share/crush \
  ~/.config/goose ~/.local/share/goose ~/.local/state/goose \
  ~/.opencode \
  ~/.config/opencode ~/.local/share/opencode ~/.local/state/opencode \
  ~/.hermes ~/.claude ~/.codex ~/.pi ~/.omp
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
  output=$(./result/bin/env-test -c 'echo "$MY_TEST_VAR $ANOTHER_VAR"') || true
  if [ "$output" = "hello world" ]; then
    echo "SUCCESS: env vars correctly set in jail"
    ((pass++)) || true
  else
    echo "ERROR: expected 'hello world', got '$output'"
    ((fail++)) || true
  fi
fi

# --- Test fwdEnv (set vars forwarded, unset vars skipped) ---
echo "----------------------------------------"
echo "Testing fwdEnv..."

if ! nix build --accept-flake-config "./tests#fwd-env-uppercase"; then
  echo "ERROR: Failed to build fwd-env-uppercase."
  ((fail++)) || true
else
  out=$(PKG_CONFIG_PATH=/demo ./result/bin/fwd-env-uppercase -c 'echo "$PKG_CONFIG_PATH"') || true
  if [ "$out" = "/demo" ]; then
    echo "SUCCESS: set variable forwarded into jail"
    ((pass++)) || true
  else
    echo "ERROR: expected '/demo', got '$out'"
    ((fail++)) || true
  fi

  # Unset variable must not fail the launch (try-fwd-env), and must be absent in the jail
  if env -u PKG_CONFIG_PATH ./result/bin/fwd-env-uppercase -c '[ -z "${PKG_CONFIG_PATH+x}" ]'; then
    echo "SUCCESS: unset variable skipped, jail starts without it"
    ((pass++)) || true
  else
    echo "ERROR: unset variable broke the jail or leaked into it"
    ((fail++)) || true
  fi
fi

# Regression for #152: mixed-case names used to fail the build with shellcheck SC2154
if ! nix build --accept-flake-config "./tests#fwd-env-mixedcase"; then
  echo "ERROR: Failed to build fwd-env-mixedcase (mixed-case fwdEnv names must build)."
  ((fail++)) || true
else
  out=$(anthropicApiKey=dummy ./result/bin/fwd-env-mixedcase -c 'echo "$anthropicApiKey"') || true
  if [ "$out" = "dummy" ]; then
    echo "SUCCESS: mixed-case variable builds and is forwarded"
    ((pass++)) || true
  else
    echo "ERROR: expected 'dummy', got '$out'"
    ((fail++)) || true
  fi
fi

# --- Test headless parents: TERM LANG HOME PATH unset must not kill the wrapper ---
echo "----------------------------------------"
echo "Testing headless parent environment..."

if ! nix build --accept-flake-config "./tests#headless-env-test"; then
  echo "ERROR: Failed to build headless-env-test."
  ((fail++)) || true
else
  out=$(env -u TERM -u LANG -u HOME -u PATH ./result/bin/headless-env-test -c 'echo headless-ok') || true
  if [ "$out" = "headless-ok" ]; then
    echo "SUCCESS: jail starts with TERM LANG HOME PATH unset"
    ((pass++)) || true
  else
    echo "ERROR: unset TERM LANG HOME PATH broke the jail"
    ((fail++)) || true
  fi

  out=$(env TERM= LANG= HOME= PATH= ./result/bin/headless-env-test -c 'echo headless-empty-ok') || true
  if [ "$out" = "headless-empty-ok" ]; then
    echo "SUCCESS: jail starts with TERM LANG HOME PATH empty"
    ((pass++)) || true
  else
    echo "ERROR: empty TERM LANG HOME PATH broke the jail"
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

# --- Test openUrls (xdg-open relays http(s) URLs to the host browser) ---
echo "----------------------------------------"
echo "Testing openUrls..."

if ! nix build --accept-flake-config "./tests#open-urls-test"; then
  echo "ERROR: Failed to build open-urls-test."
  ((fail++)) || true
else
  # BROWSER=echo acts as a fake host browser: the relayed URL comes back via stdout
  out=$(BROWSER=echo ./result/bin/open-urls-test -c 'xdg-open https://example.com') || true
  if [ "$out" = "https://example.com" ]; then
    echo "SUCCESS: xdg-open inside jail relays http(s) URL to host browser"
    ((pass++)) || true
  else
    echo "ERROR: expected 'https://example.com', got '$out'"
    ((fail++)) || true
  fi

  # Non-http(s) schemes must not reach the host handler
  out=$(BROWSER=echo ./result/bin/open-urls-test -c 'xdg-open file:///etc/hostname') || true
  if [ -z "$out" ]; then
    echo "SUCCESS: non-http(s) URL is not relayed to the host"
    ((pass++)) || true
  else
    echo "ERROR: non-http(s) URL was relayed to the host: '$out'"
    ((fail++)) || true
  fi

  # Host BROWSER unset → fallback to host xdg-open (fake one on PATH as observer)
  fakebin=$(mktemp -d)
  printf '#!/usr/bin/env bash\nprintf "xdg-open %%s\\n" "$1"\n' > "$fakebin/xdg-open"
  chmod +x "$fakebin/xdg-open"
  out=$(env -u BROWSER PATH="$fakebin:$PATH" ./result/bin/open-urls-test -c 'xdg-open https://example.com') || true
  rm -rf "$fakebin"
  if [ "$out" = "xdg-open https://example.com" ]; then
    echo "SUCCESS: host BROWSER unset falls back to host xdg-open"
    ((pass++)) || true
  else
    echo "ERROR: expected 'xdg-open https://example.com', got '$out'"
    ((fail++)) || true
  fi

  # enableOpenUrls flag must produce the same relay
  if ! nix build --accept-flake-config "./tests#open-urls-flag-test"; then
    echo "ERROR: Failed to build open-urls-flag-test."
    ((fail++)) || true
  else
    out=$(BROWSER=echo ./result/bin/open-urls-flag-test -c 'xdg-open https://flag.example.com') || true
    if [ "$out" = "https://flag.example.com" ]; then
      echo "SUCCESS: enableOpenUrls flag relays http(s) URL to host browser"
      ((pass++)) || true
    else
      echo "ERROR: expected 'https://flag.example.com', got '$out'"
      ((fail++)) || true
    fi
  fi
fi

# --- Preconfigured builders must accept extraJailOptions (README example) ---
echo "----------------------------------------"
echo "Testing extraJailOptions on preconfigured builder..."

if nix build --accept-flake-config "./tests#open-urls-preconfigured-test"; then
  echo "SUCCESS: makeJailedOpencode accepts extraJailOptions"
  ((pass++)) || true
else
  echo "ERROR: makeJailedOpencode rejected extraJailOptions"
  ((fail++)) || true
fi

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

# --- Test enableT3 (T3 Code mounts and env forwarding) ---
echo "----------------------------------------"
echo "Testing enableT3..."

if ! nix build --accept-flake-config "./tests#t3-test"; then
  echo "ERROR: Failed to build t3-test."
  ((fail++)) || true
else
  # (A) with ~/.t3 present: files readable, env forwarded, extension read-only
  T3_HOME="$(mktemp -d)"
  mkdir -p "$T3_HOME/.t3/caches" "$T3_HOME/.t3/userdata/attachments"
  echo "t3-ext-sentinel" > "$T3_HOME/.t3/caches/pi-t3-mcp-extension.ts"
  echo "t3-att-sentinel" > "$T3_HOME/.t3/userdata/attachments/a.txt"

  t3_ext="$(HOME="$T3_HOME" ./result/bin/t3-test -c 'cat ~/.t3/caches/pi-t3-mcp-extension.ts' 2>/dev/null || true)"
  t3_att="$(HOME="$T3_HOME" ./result/bin/t3-test -c 'cat ~/.t3/userdata/attachments/a.txt' 2>/dev/null || true)"
  t3_env="$(T3_MCP_URL=http://127.0.0.1:9 T3_MCP_BEARER_TOKEN=t3-token T3_PI_MCP_EXTENSION_PATH=/ext/path.ts T3_PI_RUNTIME_MODE=rpc HOME="$T3_HOME" ./result/bin/t3-test -c 'printf "%s|%s|%s|%s" "$T3_MCP_URL" "$T3_MCP_BEARER_TOKEN" "$T3_PI_MCP_EXTENSION_PATH" "$T3_PI_RUNTIME_MODE"' 2>/dev/null || true)"
  t3_write_failed=0
  HOME="$T3_HOME" ./result/bin/t3-test -c 'echo mutated > ~/.t3/caches/pi-t3-mcp-extension.ts' 2>/dev/null || t3_write_failed=1
  t3_att_write_failed=0
  HOME="$T3_HOME" ./result/bin/t3-test -c 'echo mutated > ~/.t3/userdata/attachments/new.txt' 2>/dev/null || t3_att_write_failed=1
  t3_after="$(cat "$T3_HOME/.t3/caches/pi-t3-mcp-extension.ts")"

  if [ "$t3_ext" = "t3-ext-sentinel" ] && [ "$t3_att" = "t3-att-sentinel" ] \
     && [ "$t3_env" = "http://127.0.0.1:9|t3-token|/ext/path.ts|rpc" ] \
     && [ "$t3_write_failed" -eq 1 ] && [ "$t3_att_write_failed" -eq 1 ] && [ "$t3_after" = "t3-ext-sentinel" ]; then
    echo "SUCCESS: enableT3 mounts ~/.t3 read-only and forwards T3_* env"
    ((pass++)) || true
  else
    echo "ERROR: enableT3 misbehaved (ext='$t3_ext', att='$t3_att', env='$t3_env', write_failed=$t3_write_failed, att_write_failed=$t3_att_write_failed, after='$t3_after')"
    ((fail++)) || true
  fi
  rm -rf "$T3_HOME"

  # (B) without ~/.t3: the jail still launches (try-readonly tolerates absence)
  T3_EMPTY_HOME="$(mktemp -d)"
  t3_out="$(HOME="$T3_EMPTY_HOME" ./result/bin/t3-test -c 'echo t3-launch-ok' 2>&1)" || true
  if [ "$t3_out" = "t3-launch-ok" ]; then
    echo "SUCCESS: jail launches when ~/.t3 is missing"
    ((pass++)) || true
  else
    echo "ERROR: missing ~/.t3 broke the jail launch (got '$t3_out')"
    ((fail++)) || true
  fi
  rm -rf "$T3_EMPTY_HOME"
fi

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
