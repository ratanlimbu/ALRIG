#!/usr/bin/env sh
# PreToolUse guard for Edit / Write / MultiEdit. Blocks a hardcoded credential or an endpoint
# outside the allowlist from being written into an .al file.
#
# The fast path is the point of this wrapper: a write to anything that is not an .al file
# exits here, in the shell, without starting PowerShell — so the guard costs nothing on every
# other edit. It injects no context and prints nothing unless it blocks.
#
# Fails open: if no PowerShell is installed, or the check itself errors, the write proceeds.
# The commit-time and CI checks (secret-scan, release-check) are the enforcement; this is the
# early warning.

input=$(cat)
case "$input" in
  *'.al"'*|*'.AL"'*|*'.Al"'*|*'.aL"'*) ;;
  *) exit 0 ;;
esac

root="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"
script="$root/scripts/Test-AlWrite.ps1"

if command -v pwsh >/dev/null 2>&1; then
  ps=pwsh
elif command -v powershell.exe >/dev/null 2>&1; then
  ps=powershell.exe
  # Git Bash on Windows: hand Windows PowerShell a Windows path.
  case "$script" in
    /*) command -v cygpath >/dev/null 2>&1 && script=$(cygpath -w "$script") ;;
  esac
else
  exit 0
fi

printf '%s' "$input" | "$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$script"
