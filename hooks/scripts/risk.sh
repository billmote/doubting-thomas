#!/usr/bin/env bash
# risk.sh - decide how deep the done review should be. Prints "light" or "full" on stdout and the
# reason on stderr. Usage: risk.sh [dir]   (default: current dir; looks at uncommitted changes)
# "light" only when EVERY change is a small documentation edit: doc files only, 40 changed lines or
# fewer, no secret-looking assignments, and nothing that steers an agent (charter, corrections,
# skills, prompts, personas, commands, hooks). Anything unclear is "full". It never fails and never
# skips a review; it only picks how much review.
set -u
LIMIT=40
dir="${1:-.}"
full() { echo full; echo "risk: full - $1" >&2; exit 0; }
cd "$dir" 2>/dev/null || full "cannot enter $dir"
command -v git >/dev/null 2>&1 || full "git not available"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || full "not a git work tree"
tracked=$(git diff --name-only HEAD 2>/dev/null) || tracked=""
untracked=$(git ls-files --others --exclude-standard 2>/dev/null) || untracked=""
files=$(printf '%s\n%s\n' "$tracked" "$untracked" | sed '/^$/d' | sort -u)
if [ -z "$files" ]; then full "no uncommitted changes found"; fi
count=0
while IFS= read -r f; do
  count=$((count + 1))
  low=$(printf '%s' "$f" | tr 'A-Z' 'a-z')
  case "$low" in
    *charter*|*correction*|*skill*|*persona*|*prompt*|*claude.md|*agents.md|*/commands/*|commands/*|*/hooks/*|hooks/*|.claude/*|*/.claude/*) full "$f steers an agent or the hooks" ;;
    *.md|*.txt|*.rst|*.adoc) ;;
    *) full "$f is not a documentation file" ;;
  esac
done <<EOF
$files
EOF
lines=$(git diff --numstat HEAD 2>/dev/null | awk '{ if ($1 ~ /^[0-9]+$/) a += $1; if ($2 ~ /^[0-9]+$/) a += $2 } END { print a + 0 }') || lines=0
if [ -n "$untracked" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    n=$(wc -l < "$f" 2>/dev/null | tr -d ' ') || n=0
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    lines=$((lines + n))
  done <<EOF
$untracked
EOF
fi
if [ "$lines" -gt "$LIMIT" ]; then full "$lines changed lines is over the $LIMIT-line limit"; fi
SECRET='(api[_-]?key|secret|token|passw(or)?d)[[:space:]]*[:=]|BEGIN [A-Z ]*PRIVATE KEY'
if git diff -U0 HEAD 2>/dev/null | grep '^+' | grep -Eiq "$SECRET"; then full "a line looks like a secret"; fi
if [ -n "$untracked" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if grep -Eiq "$SECRET" "$f" 2>/dev/null; then full "$f has a line that looks like a secret"; fi
  done <<EOF
$untracked
EOF
fi
echo light
echo "risk: light - $count documentation file(s), $lines changed line(s)" >&2
exit 0
