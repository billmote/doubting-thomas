# lib.sh - shared by every Thomas hook and by record.sh, so paths and formats never drift.
# bash 3.2 / BSD safe. Uses bash + coreutils + awk/sed/cksum only: NO jq, python3 or git
# (a missing dependency would make a gate fail open forever).
SK_HOME="${SKEPTIC_HOME:-$HOME/.claude/skeptic}"

# json_top KEY - print the value of KEY at DEPTH 1 of $INPUT (string value unquoted but still
# escaped; object/array value as raw text; scalar as-is). Never greps the whole input: a tool
# input whose string VALUE equals a key name must not count (the agent_type bypass).
json_top() {
  printf '%s' "$INPUT" | tr '\n\r\t' '   ' | awk -v want="$1" '
  { s = s $0 " " }
  END {
    n = length(s); depth = 0; expkey = 0; i = 1
    while (i <= n) {
      c = substr(s, i, 1)
      if (c == "\"") {
        j = i + 1; str = ""
        while (j <= n) {
          d = substr(s, j, 1)
          if (d == "\\") { str = str substr(s, j, 2); j += 2; continue }
          if (d == "\"") break
          str = str d; j++
        }
        if (depth == 1 && expkey) {
          k = j + 1
          while (k <= n && substr(s, k, 1) == " ") k++
          if (substr(s, k, 1) == ":") {
            expkey = 0
            if (str == want) {
              k++
              while (k <= n && substr(s, k, 1) == " ") k++
              v = substr(s, k, 1)
              if (v == "\"") {
                m = k + 1; out = ""
                while (m <= n) {
                  e = substr(s, m, 1)
                  if (e == "\\") { out = out substr(s, m, 2); m += 2; continue }
                  if (e == "\"") break
                  out = out e; m++
                }
                print out; exit
              } else if (v == "{" || v == "[") {
                dd = 0; ins = 0; m = k
                while (m <= n) {
                  e = substr(s, m, 1)
                  if (ins) {
                    if (e == "\\") { m += 2; continue }
                    if (e == "\"") ins = 0
                  } else {
                    if (e == "\"") ins = 1
                    else if (e == "{" || e == "[") dd++
                    else if (e == "}" || e == "]") { dd--; if (dd == 0) break }
                  }
                  m++
                }
                print substr(s, k, m - k + 1); exit
              } else {
                m = k; out = ""
                while (m <= n) {
                  e = substr(s, m, 1)
                  if (e == "," || e == "}" || e == " ") break
                  out = out e; m++
                }
                print out; exit
              }
            }
            i = k
            continue
          }
        }
        i = j + 1
        continue
      }
      if (c == "{" || c == "[") { depth++; if (depth == 1 && c == "{") expkey = 1 }
      else if (c == "}" || c == "]") depth--
      else if (c == "," && depth == 1) expkey = 1
      i++
    }
  }'
}

# sk_sid - session id: stdin JSON first (what the hooks themselves see), then the Bash-tool
# env var. Prints nothing when neither is usable. Never guesses a path.
sk_sid() {
  sid=$(json_top session_id)
  if [ -z "$sid" ]; then sid="${CLAUDE_CODE_SESSION_ID:-}"; fi
  case "$sid" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  printf '%s' "$sid"
}

sk_dir() { printf '%s/state/%s' "$SK_HOME" "$1"; }

# sk_ensure_dir SID - create the state dir; non-zero when it cannot be written (caller ALLOWS).
sk_ensure_dir() {
  d=$(sk_dir "$1")
  mkdir -p "$d" 2>/dev/null || return 1
  [ -w "$d" ] || return 1
  return 0
}

# sk_atomic_write FILE CONTENT - write, move into place, read back; non-zero if it did not take.
sk_atomic_write() {
  tmp="$1.tmp.$$"
  printf '%s\n' "$2" > "$tmp" 2>/dev/null || return 1
  mv -f "$tmp" "$1" 2>/dev/null || return 1
  back=$(cat "$1" 2>/dev/null) || return 1
  [ "$back" = "$2" ] || return 1
  return 0
}

# sk_field FILE KEY - value of KEY from a "k=v k=v ... note=..." line (values hold no spaces).
sk_field() { awk -v k="$2" '{ for (i = 1; i <= NF; i++) { if ($i ~ /^note=/) break; if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } } }' "$1" 2>/dev/null; }

# sk_edits SID - the monotonic edit counter (0 when absent or not a number).
sk_edits() {
  f="$(sk_dir "$1")/edits"
  n=0
  if [ -e "$f" ]; then n=$(cat "$f" 2>/dev/null) || n=0; fi
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

sk_now() { date '+%Y-%m-%dT%H:%M:%S%z'; }

# sk_history WHICH VERDICT TAG NOTE - append one line to the review history, capped at 500 lines.
# Fields: when|session|plan-or-done|pass/fail/deferred|principle|note. Always returns 0 (fail open).
sk_history() {
  h="$SK_HOME/history.log"
  mkdir -p "$SK_HOME" 2>/dev/null || return 0
  hn=$(printf '%s' "${4:-}" | tr '\n\r\t|' '    ' | cut -c1-200)
  printf '%s|%s|%s|%s|%s|%s\n' "$(sk_now)" "${sid:-?}" "$1" "$2" "$3" "$hn" >> "$h" 2>/dev/null || return 0
  hc=$(wc -l < "$h" 2>/dev/null | tr -d ' ') || return 0
  case "$hc" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$hc" -gt 500 ]; then
    tail -n 400 "$h" > "$h.tmp.$$" 2>/dev/null && mv -f "$h.tmp.$$" "$h" 2>/dev/null
  fi
  return 0
}

# sk_esc TEXT - make TEXT safe inside a JSON string.
sk_esc() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# sk_exempt - true when the edit in $INPUT touches ONLY Claude's own plan files (*/.claude/plans/*).
# Such edits are neither plan-gated nor counted toward the done gate. Add more globs to the case
# below if you have record-keeping files you never want reviewed.
sk_exempt() {
  ti=$(json_top tool_input)
  [ -n "$ti" ] || return 1
  saved="$INPUT"; INPUT="$ti"
  fp=$(json_top file_path)
  if [ -z "$fp" ]; then fp=$(json_top notebook_path); fi
  INPUT="$saved"
  case "$fp" in
    ''|*..*) return 1 ;;
    */.claude/plans/*) return 0 ;;
  esac
  return 1
}
