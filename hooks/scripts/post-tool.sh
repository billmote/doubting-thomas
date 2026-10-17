#!/usr/bin/env bash
# post-tool.sh - PostToolUse (edits) and PostToolUseFailure (errors). Never blocks, always exits 0.
#  * PostToolUse on Edit|Write|NotebookEdit: bump the monotonic edit counter (successful edits only;
#    failed tool calls arrive on PostToolUseFailure, a separate event).
#  * PostToolUseFailure: normalise + checksum the error, count it; on the 2nd occurrence inject ONE
#    "step back" note via additionalContext. Never blocks.
# FAIL-OPEN: any internal error is swallowed (exit 0). Nothing here can deny anything.
set -eEu
trap 'exit 0' ERR
. "$(dirname "$0")/lib.sh" || exit 0
INPUT=$(cat)
sid=$(sk_sid)
if [ -z "$sid" ]; then exit 0; fi
if ! sk_ensure_dir "$sid"; then exit 0; fi
dir=$(sk_dir "$sid")
event=$(json_top hook_event_name)
tool=$(json_top tool_name)
case "$event" in
  PostToolUseFailure)
    err=$(json_top error)
    if [ -z "$err" ]; then err="$tool $(json_top tool_input)"; fi
    norm=$(printf '%s' "$err" | tr 'A-Z' 'a-z' | sed -E 's/0x[0-9a-f]+/H/g; s/[0-9]+/N/g; s/[[:space:]]+/ /g' | cut -c1-400)
    sum=$(printf '%s' "$tool|$norm" | cksum | cut -d' ' -f1)
    file="$dir/errs"
    count=0
    if [ -e "$file" ]; then
      line=$(grep "^$sum " "$file" 2>/dev/null | head -1) || line=""
      if [ -n "$line" ]; then count=${line#* }; fi
    fi
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    count=$((count + 1))
    { if [ -e "$file" ]; then grep -v "^$sum " "$file" 2>/dev/null || true; fi; printf '%s %s\n' "$sum" "$count"; } > "$file.tmp.$$"
    mv -f "$file.tmp.$$" "$file"
    if [ "$count" -eq 2 ]; then
      note="The same error has now occurred twice this session. Thomas's second checkpoint applies: step back and ask whether the work is digging in the wrong place. Before trying again, run /skeptic plan with a NEW plan so a fresh Thomas reviews the approach."
      printf '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":"%s"}}\n' "$(sk_esc "$note")"
    fi
    ;;
  *)
    case "$tool" in
      Edit|Write|NotebookEdit|MultiEdit)
        if sk_exempt; then exit 0; fi
        n=$(sk_edits "$sid")
        n=$((n + 1))
        printf '%s\n' "$n" > "$dir/edits.tmp.$$"
        mv -f "$dir/edits.tmp.$$" "$dir/edits"
        ;;
    esac
    ;;
esac
exit 0
