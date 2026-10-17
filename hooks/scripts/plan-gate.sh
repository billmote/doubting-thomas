#!/usr/bin/env bash
# plan-gate.sh - PreToolUse on Edit|Write|NotebookEdit. Denies the MAIN agent's first edit of a
# session until a plan PASS (or deferral) is recorded. Subagents (agent_id present) pass.
#
# FAIL-OPEN INVARIANT (do not break): any internal/I-O error must ALLOW. The ERR trap below makes
# every unexpected non-zero exit an allow. So the DENY branch is reached ONLY through an explicit
# `if` after a SUCCESSFUL state read ("marker absent"). Never let a command's own non-zero exit
# mean "block": the trap would swallow it and the gate would silently go advisory.
set -eEu
trap 'exit 0' ERR
. "$(dirname "$0")/lib.sh" || exit 0
INPUT=$(cat)
tool=$(json_top tool_name)
case "$tool" in Edit|Write|NotebookEdit|MultiEdit) ;; *) exit 0 ;; esac
agent=$(json_top agent_id)
case "$agent" in ''|null|false|0|"{}"|"[]") ;; *) exit 0 ;; esac   # only a real id marks a subagent
if sk_exempt; then exit 0; fi
sid=$(sk_sid)
if [ -z "$sid" ]; then exit 0; fi
if ! sk_ensure_dir "$sid"; then exit 0; fi
if [ -e "$(sk_dir "$sid")/plan" ]; then exit 0; fi
msg="Thomas has not reviewed a plan this session, so the first edit is held. Run /skeptic plan (summary of the plan as the argument). If Thomas cannot run, /skeptic plan --defer records no review and lets the edit through."
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(sk_esc "$msg")"
exit 0
