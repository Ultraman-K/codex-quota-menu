#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/CodexQuotaMenu/bin"
BIN="$INSTALL_DIR/codex-quota-menu"
LOG_DIR="logs"

cd "$ROOT"
swift build -c release --disable-sandbox
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"
install -m 755 .build/release/codex-quota-menu "$BIN"

CODEX_PATH="$(command -v codex || true)"
if ! pgrep -f "${BIN}" >/dev/null 2>&1; then
  if [[ -n "$CODEX_PATH" ]]; then
    CODEX_QUOTA_MENU_CODEX_PATH="$CODEX_PATH" "$BIN" >"$LOG_DIR/launcher.log" 2>&1 &
  else
    "$BIN" >"$LOG_DIR/launcher.log" 2>&1 &
  fi
fi

print "Installed: $BIN"
print "Login startup is off by default; enable it from the menu-bar item."
