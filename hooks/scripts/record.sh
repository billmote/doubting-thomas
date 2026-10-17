#!/usr/bin/env bash
# record.sh - the ONE state helper. Usage: record.sh plan|done [--defer] [note...]
# The /skeptic command runs it after a PASS (or with --defer). Writes the marker atomically, reads
# it back, and reports success or failure on stderr. Never claim a gate cleared without reading it.
# On a real PASS it prints a receipt (T-<epoch>-<n>) on stdout and appends it to the ledger
# ($SK_HOME/ledger), so a commit-message check can verify a PASS line was earned.
# A hatch (--defer) records NO review and prints no receipt. The marker is an honesty checkpoint,
# not a security control: the main agent could call this directly.
set -u
. "$(dirname "$0")/lib.sh" || { echo "skeptic: lib.sh missing" >&2; exit 1; }
which="${1:-}"; shift || true
kind=pass
if [ "${1:-}" = "--defer" ]; then kind=deferred; shift; fi
note=$(printf '%s' "$*" | tr '\n\r\t' '   ' | cut -c1-300)
case "$which" in plan|done) ;; *) echo "skeptic: usage: record.sh plan|done [--defer] [note]" >&2; exit 2 ;; esac
INPUT=""
if [ ! -t 0 ]; then IFS= read -r -t 1 -d '' INPUT || true; fi
sid=$(sk_sid)
if [ -z "$sid" ]; then echo "skeptic: REFUSED - no session id on stdin or in CLAUDE_CODE_SESSION_ID; marker NOT recorded" >&2; exit 1; fi
if ! sk_ensure_dir "$sid"; then echo "skeptic: FAILED - state dir not writable; marker NOT recorded" >&2; exit 1; fi
dir=$(sk_dir "$sid"); ts=$(sk_now); edits=$(sk_edits "$sid")
if [ "$which" = "plan" ]; then line="kind=$kind ts=$ts note=$note"; else line="kind=$kind edits=$edits ts=$ts note=$note"; fi
if ! sk_atomic_write "$dir/$which" "$line"; then echo "skeptic: FAILED - marker did not read back; $which NOT recorded" >&2; exit 1; fi
echo "skeptic: recorded $which ($kind) for session $sid at edit count $edits -> $dir/$which" >&2
if [ "$kind" = "pass" ]; then
  r="T-$(date +%s)-$(printf '%s' "$sid|$which|$edits|$ts" | cksum | cut -d' ' -f1)"
  printf '%s %s %s %s\n' "$r" "$(date +%s)" "$sid" "$which" >> "$SK_HOME/ledger" 2>/dev/null || echo "skeptic: warning - ledger not writable; receipt will not verify" >&2
  printf '%s\n' "$r"
else
  echo "skeptic: DEFERRED - no review was done and none is recorded" >&2
fi
exit 0
