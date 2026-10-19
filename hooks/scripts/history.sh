#!/usr/bin/env bash
# history.sh - Thomas's review history. One line per review in $SK_HOME/history.log:
#   when|session|plan-or-done|pass/fail/deferred|principle|note
# record.sh adds PASS and deferral lines itself. This script adds FAIL lines and reports.
#   history.sh fail <plan|done> <principle> <reason...>   record a FAIL (changes no gate marker)
#   history.sh stats                                      which principles actually catch things
# Report only: it never edits the charter. Trimming or adding principles stays the owner's call.
# Fails open: a problem writing the log exits 0.
set -u
. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
VOCAB="reuse simplicity design correctness security ux pwa graphic verification maintainability correction other"
cmd="${1:-}"; shift || true
case "$cmd" in
  fail)
    which="${1:-}"; tag="${2:-other}"
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi
    case "$which" in plan|done) ;; *) echo "usage: history.sh fail <plan|done> <principle> <reason>" >&2; exit 2 ;; esac
    tag=$(printf '%s' "$tag" | tr 'A-Z' 'a-z' | tr -d '[]')
    case " $VOCAB " in *" $tag "*) ;; *) tag=other ;; esac
    INPUT=""; sid=$(sk_sid) || sid=""
    sk_history "$which" fail "$tag" "$*"
    echo "skeptic: recorded a FAIL ($tag) in the review history" >&2
    exit 0 ;;
  stats)
    h="$SK_HOME/history.log"
    if [ ! -s "$h" ]; then echo "No reviews recorded yet."; exit 0; fi
    awk -F'|' -v vocab="$VOCAB" '
      { total++; if ($4 == "pass") p++; else if ($4 == "fail") { f++; byTag[$5]++; recent[f] = substr($1, 1, 10) " [" $5 "] " $6 } else d++ }
      END {
        printf "Reviews: %d (%d passed, %d failed, %d skipped)\n", total, p, f, d
        if (f > 0) {
          print "Failures by principle:"
          for (t in byTag) printf "  %s: %d\n", t, byTag[t]
          print "Latest failures:"
          s = f - 4; if (s < 1) s = 1
          for (i = f; i >= s; i--) print "  " recent[i]
        }
        if (total < 20) { printf "Too few reviews (%d of 20) to say which principles never catch anything.\n", total }
        else {
          n = split(vocab, v, " "); out = ""
          for (i = 1; i <= n; i++) if (v[i] != "other" && v[i] != "correction" && !(v[i] in byTag)) out = out " " v[i]
          if (out == "") out = " none"
          print "Principles that have never caused a failure:" out
        }
      }' "$h"
    exit 0 ;;
  *) echo "usage: history.sh fail <plan|done> <principle> <reason> | history.sh stats" >&2; exit 2 ;;
esac
