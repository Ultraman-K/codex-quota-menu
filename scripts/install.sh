#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/CodexQuotaMenu/bin"
BIN="$INSTALL_DIR/codex-quota-menu"

cd "$ROOT"
swift build -c release --disable-sandbox
mkdir -p "$INSTALL_DIR"
install -m 755 .build/release/codex-quota-menu "$BIN"

CODEX_PATH="$(command -v codex || true)"
if ! pgrep -f "${BIN}" >/dev/null 2>&1; then
  if [[ -n "$CODEX_PATH" ]]; then
    CODEX_QUOTA_MENU_CODEX_PATH="$CODEX_PATH" "$BIN" >/dev/null 2>&1 &
  else
    "$BIN" >/dev/null 2>&1 &
  fi
fi

print "Installed: $BIN"
print "Login startup is off by default; enable it from the menu-bar item."
