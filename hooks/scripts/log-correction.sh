#!/usr/bin/env bash
# log-correction.sh - append ONE dated correction to the top of ~/.claude/skeptic/corrections.md.
#   log-correction.sh "<what was done>" "<what to do instead>"
# The prompt-submit hook asks Claude to run this when the user corrects how it works, so the log
# feeds itself and "a repeat of a logged correction is an automatic FAIL" has something to bite on.
# Newest first. Skips an exact repeat. Keeps the file under ~5 KB (Thomas's context is capped at
# about 12 KB across charter and corrections); older lines move to corrections-archive.md, never lost.
# Fails open: any I/O problem exits 0 without touching the log.
set -u
. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
before=$(printf '%s' "${1:-}" | tr '\n\r\t' '   ' | cut -c1-240)
after=$(printf '%s' "${2:-}" | tr '\n\r\t' '   ' | cut -c1-240)
if [ -z "$before" ] || [ -z "$after" ]; then echo 'usage: log-correction.sh "<what was done>" "<what to do instead>"' >&2; exit 2; fi
mkdir -p "$SK_HOME" 2>/dev/null || exit 0
f="$SK_HOME/corrections.md"; arch="$SK_HOME/corrections-archive.md"
if [ -e "$f" ] && grep -qF -- "After: $after" "$f" 2>/dev/null; then exit 0; fi
line="- **$(date +%Y-%m-%d).** Before: $before After: $after"
tmp="$f.tmp.$$"
{ printf '%s\n' "$line"; if [ -e "$f" ]; then cat "$f"; fi; } > "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }
awk -v max=5000 -v arch="$arch" '{ n += length($0) + 1; if (n <= max) print; else print >> arch }' "$tmp" > "$tmp.keep" 2>/dev/null || { rm -f "$tmp" "$tmp.keep"; exit 0; }
mv -f "$tmp.keep" "$f" 2>/dev/null || true
rm -f "$tmp" "$tmp.keep"
exit 0
