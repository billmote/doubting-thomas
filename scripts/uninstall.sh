#!/usr/bin/env bash
# uninstall.sh - remove Thomas's hook entries from ~/.claude/settings.json (only ours, by command
# path) and delete the installed command. State/ledger stay. `--restore-backup` instead puts back
# the newest settings.json.bak.* (discarding any settings changes made since install).
set -eu
SET="$HOME/.claude/settings.json"; SK="$HOME/.claude/skeptic"
if [ "${1:-}" = "--restore-backup" ]; then
  b=$(ls -t "$SET".bak.* 2>/dev/null | head -1); [ -n "$b" ] || { echo "no backup found"; exit 1; }
  cp "$b" "$SET"; echo "restored $b"
else
  python3 - "$SET" "$SK/bin" <<'PY'
import json, sys
path, bindir = sys.argv[1], sys.argv[2]
s = json.load(open(path))
for ev in list(s.get("hooks", {})):
    for g in s["hooks"][ev]:
        g["hooks"] = [x for x in g.get("hooks", []) if not x.get("command", "").startswith(bindir + "/")]
    s["hooks"][ev] = [g for g in s["hooks"][ev] if g["hooks"]]
    if not s["hooks"][ev]: del s["hooks"][ev]
if not s.get("hooks"): s.pop("hooks", None)
json.dump(s, open(path, "w"), indent=2); json.load(open(path)); print("hook entries removed")
PY
fi
rm -f "$HOME/.claude/commands/skeptic.md"; echo "Restart Claude Code."
