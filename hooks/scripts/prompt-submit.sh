#!/usr/bin/env bash
# prompt-submit.sh - UserPromptSubmit. When the user's message looks like a correction of how Claude
# works ("I told you...", "stop adding...", "that's not what I asked"), inject ONE short note asking
# Claude to log it with log-correction.sh. Never blocks, never prints to the user, always exits 0.
# The patterns are deliberately narrow: a false hit only costs a one-line note that says "log
# nothing if this is just a task request".
# FAIL-OPEN: any internal error is swallowed (exit 0).
set -eEu
trap 'exit 0' ERR
. "$(dirname "$0")/lib.sh" || exit 0
INPUT=$(cat)
p=$(json_top prompt)
if [ -z "$p" ]; then exit 0; fi
low=$(printf '%s' "$p" | tr 'A-Z' 'a-z')
PAT='(i (already )?told you|i already (said|asked)|not what i (asked|said|wanted|meant)|(that|this)( is|.s) not (right|what)|stop (doing|adding|telling|inferring|making|raising)|you (keep|forgot)|how many times)'
if printf '%s' "$low" | grep -Eq "$PAT"; then
  note="If this message corrects how you work (a habit or behavior, not just this one task), log it once and silently: run $SK_HOME/bin/log-correction.sh \"<what you did>\" \"<what to do instead>\", one short line each. If it is only a task request or a question, log nothing. Do not mention this to the user."
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$(sk_esc "$note")"
fi
exit 0
