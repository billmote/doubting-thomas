#!/usr/bin/env bash
# done-gate.sh - Stop. Blocks ending a session that made any edit until a done PASS (or deferral)
# bound to the CURRENT edit count is recorded. An edit after the PASS moves the counter past it.
# Subagent stops (agent_id present) pass. stop_hook_active is deliberately NOT honoured: that would
# turn the gate into "block once, then allow", which is advisory.
#
# FAIL-OPEN INVARIANT (do not break): any internal/I-O error must ALLOW. The ERR trap turns every
# unexpected non-zero exit into an allow, so the BLOCK branch is reached ONLY through an explicit
# `if` after SUCCESSFUL reads. Never let a command's own non-zero exit mean "block".
set -eEu
trap 'exit 0' ERR
. "$(dirname "$0")/lib.sh" || exit 0
INPUT=$(cat)
agent=$(json_top agent_id)
case "$agent" in ''|null|false|0|"{}"|"[]") ;; *) exit 0 ;; esac   # only a real id marks a subagent
sid=$(sk_sid)
if [ -z "$sid" ]; then exit 0; fi
if ! sk_ensure_dir "$sid"; then exit 0; fi
dir=$(sk_dir "$sid")
edits=$(sk_edits "$sid")
if [ "$edits" -eq 0 ]; then exit 0; fi
if [ -e "$dir/done" ]; then
  at=$(sk_field "$dir/done" edits)
  case "$at" in ''|*[!0-9]*) exit 0 ;; esac   # unreadable marker = cannot tell = allow
  if [ "$at" -ge "$edits" ]; then exit 0; fi
  why="Edits were made after Thomas's last sign-off (edit $at, now at edit $edits)."
else
  why="This session made $edits edit(s) and Thomas has not signed off."
fi
msg="$why Run /skeptic done (summary as the argument). If Thomas cannot run, /skeptic done --defer records no review and ends the gate for the current edit count."
printf '{"decision":"block","reason":"%s"}\n' "$(sk_esc "$msg")"
exit 0
