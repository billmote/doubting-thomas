#!/usr/bin/env bash
# session-start.sh - SessionStart. Injects Thomas's charter as context, then garbage-collects
# state dirs older than 7 days. Always exits 0; every step fails open.
set -u
. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
cat >/dev/null 2>&1 || true
# Plugin install: put a stable copy of the scripts and charter under $SK_HOME so /skeptic (which
# runs in the Bash tool, where CLAUDE_PLUGIN_ROOT is not set) can find record.sh. Fails open.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT/hooks/scripts" ]; then
  mkdir -p "$SK_HOME/bin" 2>/dev/null && cp "$CLAUDE_PLUGIN_ROOT"/hooks/scripts/*.sh "$SK_HOME/bin/" 2>/dev/null && chmod +x "$SK_HOME"/bin/*.sh 2>/dev/null || true
  if [ -f "$CLAUDE_PLUGIN_ROOT/charter.md" ]; then cp "$CLAUDE_PLUGIN_ROOT/charter.md" "$SK_HOME/charter.md" 2>/dev/null || true; fi
fi
find "$SK_HOME/state" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
if [ -r "$SK_HOME/charter.md" ]; then
  text=$(
    tr -d '\r' < "$SK_HOME/charter.md" 2>/dev/null
    # corrections.md is the user's own log: never overwritten by an update, so it is read here.
    if [ -r "$SK_HOME/corrections.md" ]; then printf '\n## Your corrections (newest first)\n\n'; tr -d '\r' < "$SK_HOME/corrections.md" 2>/dev/null; fi
  ) || text=""
  text=$(printf '%s' "$text" | cut -c1-600 | head -c 12000) || text=""
  if [ -n "$text" ]; then
    esc=$(printf '%s' "$text" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); gsub(/\t/," "); print $0 "\\n"}') || esc=""
    if [ -n "$esc" ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
    fi
  fi
fi
exit 0
