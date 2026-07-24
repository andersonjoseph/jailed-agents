#!/usr/bin/env bash
# check-latest-pr.sh
# Checkout the latest open PR, run the test suite, print a report.
# You still click the merge button.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Bootstrap gh via nix if it's not already on PATH.
if ! command -v gh >/dev/null 2>&1; then
  echo "gh not found — re-running under nix shell nixpkgs#gh"
  exec nix shell nixpkgs#gh -c bash "$0" "$@"
fi

# Refuse on a dirty tree — checkout would clobber it.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree has uncommitted changes. Commit or stash first:"
  git status --short
  exit 1
fi

START_BRANCH=$(git branch --show-current)

if [ -n "${1:-}" ]; then
  # Explicit PR number passed in — escape hatch for testing anything else.
  PR_JSON=$(gh pr view "$1" --json number,headRefName,title)
else
  # Only act on auto-generated llm-agents update PRs.
  # auto-release.yml names its branches: update/llm-agents-<rev>
  PR_JSON=$(gh pr list --state open --json number,headRefName,title,createdAt \
    | jq '[.[] | select(.headRefName | startswith("update/llm-agents-"))]
          | sort_by(.createdAt) | reverse | .[0]')
  AUTO_PR=1
fi

if [ "$PR_JSON" = "null" ] || [ -z "$PR_JSON" ]; then
  echo "No matching open PR found."
  echo "Pass an explicit number: ./scripts/check-latest-pr.sh 42"
  exit 0
fi

NUM=$(jq -r '.number' <<<"$PR_JSON")
BRANCH=$(jq -r '.headRefName' <<<"$PR_JSON")
TITLE=$(jq -r '.title' <<<"$PR_JSON")

echo "Latest open PR:"
echo "  #$NUM  $TITLE"
echo "  branch: $BRANCH"
echo "----------------------------------------"

# Auto PRs should touch flake.lock and nothing else. Bail if not.
if [ "${AUTO_PR:-0}" = "1" ]; then
  CHANGED=$(gh pr view "$NUM" --json files -q '.files[].path')
  EXTRA=$(grep -vx 'flake.lock' <<<"$CHANGED" || true)
  if [ -n "$EXTRA" ]; then
    echo "Auto PR touches more than flake.lock — review manually:"
    echo "$EXTRA"
    exit 1
  fi
fi

gh pr checkout "$NUM"

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

echo "Running ./tests/test.sh ..."
echo "----------------------------------------"
set +e
./tests/test.sh 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

# Pull the summary line(s) test.sh printed, if any.
SUMMARY=$(grep -E '^Results:|^ERROR:' "$LOG" || true)

echo "========================================"
if [ "$STATUS" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL (exit $STATUS)"
fi
[ -n "$SUMMARY" ] && echo "$SUMMARY"
echo "========================================"
echo "merge:   gh pr merge $NUM --merge"
echo "return:  git checkout $START_BRANCH"
