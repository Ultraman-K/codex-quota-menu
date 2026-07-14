#!/bin/zsh
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--purge" ) ]]; then
  print -u2 "Usage: $0 [--purge]"
  exit 2
fi

BIN="$HOME/Library/Application Support/CodexQuotaMenu/bin/codex-quota-menu"
PLIST="$HOME/Library/LaunchAgents/com.codex.quota-menu.plist"
LABEL="com.codex.quota-menu"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

for pid in $(pgrep -f "$BIN" 2>/dev/null || true); do
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$command" == "$BIN"* ]]; then
    kill "$pid" 2>/dev/null || true
  fi
done

rm -f "$BIN"
rmdir "$HOME/Library/Application Support/CodexQuotaMenu/bin" 2>/dev/null || true

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$HOME/Library/Application Support/CodexQuotaMenu"
  rm -rf "$ROOT/logs"
fi

print "Codex Quota Menu removed."
