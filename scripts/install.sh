#!/usr/bin/env bash
# install.sh - put Thomas's hooks on THIS machine for every Claude Code session.
#   bash scripts/install.sh        (re-run any time; it is idempotent)
# Copies bin/ + command + charter into ~/.claude/skeptic, then MERGES hook entries into
# ~/.claude/settings.json (timestamped backup first, JSON validated, existing hooks kept).
# Restart Claude Code afterwards. Undo with uninstall.sh.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
SK="$HOME/.claude/skeptic"; SET="$HOME/.claude/settings.json"
command -v python3 >/dev/null || { echo "python3 needed for the settings merge"; exit 1; }
mkdir -p "$SK/bin" "$SK/state" "$HOME/.claude/commands"
cp "$REPO"/hooks/scripts/*.sh "$SK/bin/"; chmod +x "$SK"/bin/*.sh
cp "$REPO/commands/skeptic.md" "$HOME/.claude/commands/skeptic.md"
cp "$REPO/charter.md" "$SK/charter.md"
[ -f "$SET" ] || echo '{}' > "$SET"
BK="$SET.bak.$(date +%Y%m%d-%H%M%S).$$"; cp "$SET" "$BK"
python3 - "$SET" "$SK/bin" <<'PY'
import json, sys
path, bindir = sys.argv[1], sys.argv[2]
s = json.load(open(path))
h = s.setdefault("hooks", {})
want = [
 ("SessionStart", "", "session-start.sh"),
 ("UserPromptSubmit", "", "prompt-submit.sh"),
 ("PreToolUse", "Edit|Write|NotebookEdit|MultiEdit", "plan-gate.sh"),
 ("PostToolUse", "Edit|Write|NotebookEdit|MultiEdit", "post-tool.sh"),
 ("PostToolUseFailure", "", "post-tool.sh"),
 ("Stop", "", "done-gate.sh"),
]
for ev, matcher, script in want:
    cmd = f"{bindir}/{script}"
    groups = h.setdefault(ev, [])
    g = next((g for g in groups if g.get("matcher", "") == matcher), None)
    if g is None:
        g = {"matcher": matcher, "hooks": []} if matcher else {"hooks": []}
        groups.append(g)
    g.setdefault("hooks", [])
    if not any(x.get("command") == cmd for x in g["hooks"]):
        g["hooks"].append({"type": "command", "command": cmd, "timeout": 15})
json.dump(s, open(path, "w"), indent=2)
json.load(open(path))
print("settings.json merged and validated")
PY
echo "Backup: $BK"; echo "Installed. Restart Claude Code, then run: bash $REPO/tests/test.sh"
