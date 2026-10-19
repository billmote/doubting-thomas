#!/usr/bin/env bash
# test.sh - synthetic-stdin tests for the Thomas hooks. Throwaway state dir; touches nothing real.
#   bash tests/test.sh
HERE="$(cd "$(dirname "$0")" && pwd)"; BIN="$HERE/../hooks/scripts"
export SKEPTIC_HOME="$(mktemp -d)"; unset CLAUDE_CODE_SESSION_ID
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; echo "       got: $2"; }
run() { printf '%s' "$2" | "$BIN/$1"; }          # run HOOK JSON
has() { case "$2" in *"$1"*) return 0;; esac; return 1; }
S=sess1
edit() { printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$S" "$1" "$2"; }

echo "== plan-gate"
out=$(run plan-gate.sh "$(edit Edit '{"file_path":"/a/b.txt","old_string":"x","new_string":"y"}')")
has '"permissionDecision":"deny"' "$out" && ok "denies first edit without a marker" || bad "deny without marker" "$out"
has '/skeptic plan' "$out" && ok "deny message names the command" || bad "deny names command" "$out"
out=$(run plan-gate.sh '{"session_id":"sess1","tool_name":"Read","tool_input":{}}')
[ -z "$out" ] && ok "non-edit tool allowed" || bad "non-edit tool" "$out"
out=$(run plan-gate.sh '{"session_id":"sess1","agent_id":"ag1","agent_type":"Explore","tool_name":"Edit","tool_input":{"file_path":"/x"}}')
[ -z "$out" ] && ok "genuine subagent payload allowed" || bad "subagent" "$out"
for v in old_string new_string file_path; do
  case $v in
    old_string) ti='{"file_path":"/a","old_string":"agent_type","new_string":"z"}';;
    new_string) ti='{"file_path":"/a","old_string":"z","new_string":"agent_type"}';;
    file_path)  ti='{"file_path":"agent_type","old_string":"z","new_string":"q"}';;
  esac
  out=$(run plan-gate.sh "$(edit Edit "$ti")")
  has deny "$out" && ok "BYPASS: $v exactly agent_type still denied" || bad "bypass $v" "$out"
done
out=$(run plan-gate.sh "$(edit Edit '{"file_path":"/a","old_string":"\"agent_type\":\"x\" \"agent_id\":\"y\"","new_string":"q"}')")
has deny "$out" && ok "BYPASS: escaped agent_type/agent_id inside content still denied" || bad "bypass escaped" "$out"
out=$(run plan-gate.sh "$(edit NotebookEdit '{"notebook_path":"agent_type","new_source":"{\"agent_id\":\"z\"}"}')")
has deny "$out" && ok "BYPASS: NotebookEdit equivalent denied" || bad "bypass notebook" "$out"
out=$(run plan-gate.sh '{"tool_input":{"agent_id":"nested","session_id":"evil"},"session_id":"sess1","tool_name":"Edit"}')
has deny "$out" && ok "BYPASS: nested agent_id/session_id keys ignored" || bad "bypass nested" "$out"
out=$(run plan-gate.sh '{"tool_name":"Edit","tool_input":{"file_path":"/a"}}')
[ -z "$out" ] && ok "missing session id fails open" || bad "no sid" "$out"
SKEPTIC_SID_TEST=1
CLAUDE_CODE_SESSION_ID=sess1 "$BIN/record.sh" plan "test plan" </dev/null >/dev/null 2>"$SKEPTIC_HOME/err"
has "recorded plan" "$(cat "$SKEPTIC_HOME/err")" && ok "record.sh reports success on stderr" || bad "record stderr" "$(cat "$SKEPTIC_HOME/err")"
out=$(run plan-gate.sh "$(edit Write '{"file_path":"/a","content":"x"}')")
[ -z "$out" ] && ok "allows after a plan marker" || bad "allow after plan" "$out"
mkdir -p "$SKEPTIC_HOME/state/ro"; chmod 555 "$SKEPTIC_HOME/state/ro"
out=$(printf '%s' '{"session_id":"ro","tool_name":"Edit","tool_input":{}}' | "$BIN/plan-gate.sh")
if [ "$(id -u)" = 0 ]; then ok "unwritable dir (skipped: running as root, chmod does not bind)"; else [ -z "$out" ] && ok "unwritable state dir ALLOWS (fail open)" || bad "unwritable" "$out"; fi
chmod 755 "$SKEPTIC_HOME/state/ro"
out=$(SKEPTIC_HOME=/proc/nope/x printf '%s' '{"session_id":"zz","tool_name":"Edit","tool_input":{}}' | SKEPTIC_HOME=/proc/nope/x "$BIN/plan-gate.sh")
[ -z "$out" ] && ok "uncreatable state dir ALLOWS (fail open)" || bad "uncreatable" "$out"

for v in null false 0 '{}' '[]'; do
  out=$(run plan-gate.sh "{\"session_id\":\"sessx\",\"tool_name\":\"Edit\",\"agent_id\":$v,\"tool_input\":{}}")
  has deny "$out" && ok "agent_id=$v is not a subagent: denied" || bad "agent_id $v" "$out"
done

out=$(run plan-gate.sh '{"session_id":"sessy","tool_name":"Write","tool_input":{"file_path":"/p/.claude/plans/x.md","content":"x"}}')
[ -z "$out" ] && ok "record-keeping path exempt from the plan gate" || bad "exempt" "$out"
out=$(run plan-gate.sh '{"session_id":"sessy","tool_name":"Edit","tool_input":{"file_path":"/p/scripts/x.py","old_string":"/.claude/plans/x.md","new_string":"q"}}')
has deny "$out" && ok "exempt path only counts as file_path, not as content" || bad "exempt content" "$out"
out=$(run plan-gate.sh '{"session_id":"sessy","tool_name":"Write","tool_input":{"file_path":"/p/operations/../scripts/x.py"}}')
has deny "$out" && ok "path with .. is never exempt" || bad "dotdot" "$out"
run post-tool.sh '{"session_id":"sessz","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/p/.claude/plans/a.md"}}'
[ ! -e "$SKEPTIC_HOME/state/sessz/edits" ] && ok "exempt edits are not counted" || bad "exempt count" ""

echo "== done-gate + edit counter"
S=sess2
post() { run post-tool.sh "{\"session_id\":\"sess2\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"$1\",\"tool_input\":{},\"tool_response\":{}}"; }
stop() { run done-gate.sh '{"session_id":"sess2","hook_event_name":"Stop","stop_hook_active":true}'; }
out=$(stop); [ -z "$out" ] && ok "no edits: stop allowed" || bad "no edits" "$out"
post Edit; post Read; post Write
out=$(stop); has '"decision":"block"' "$out" && ok "edits, no PASS: stop blocked (even with stop_hook_active)" || bad "block" "$out"
[ "$(cat "$SKEPTIC_HOME/state/sess2/edits")" = 2 ] && ok "counter counts edits only (2 of 3 calls)" || bad "counter" "$(cat "$SKEPTIC_HOME/state/sess2/edits")"
out=$(printf '%s' '{"session_id":"sess2","agent_id":"a","hook_event_name":"Stop"}' | "$BIN/done-gate.sh")
[ -z "$out" ] && ok "subagent stop allowed" || bad "subagent stop" "$out"
r=$(CLAUDE_CODE_SESSION_ID=sess2 "$BIN/record.sh" done "all good" </dev/null 2>/dev/null)
case "$r" in T-*) ok "PASS prints a receipt ($r)";; *) bad "receipt" "$r";; esac
grep -q "^$r " "$SKEPTIC_HOME/ledger" && ok "receipt is in the ledger" || bad "ledger" "$(cat "$SKEPTIC_HOME/ledger" 2>&1)"
out=$(stop); [ -z "$out" ] && ok "stop allowed after a done PASS" || bad "allow after pass" "$out"
post Edit
out=$(stop); has block "$out" && ok "one more edit re-blocks" || bad "re-block" "$out"
r=$(CLAUDE_CODE_SESSION_ID=sess2 "$BIN/record.sh" done --defer "thomas down" </dev/null 2>"$SKEPTIC_HOME/err")
[ -z "$r" ] && has DEFERRED "$(cat "$SKEPTIC_HOME/err")" && ok "done --defer: no receipt, says no review recorded" || bad "defer" "$r"
out=$(stop); [ -z "$out" ] && ok "deferral clears the gate for this count" || bad "defer clears" "$out"
post Edit
out=$(stop); has block "$out" && ok "edit after deferral re-arms the gate" || bad "defer re-arm" "$out"
out=$(printf '%s' '{"session_id":"sess2","hook_event_name":"Stop"}' | SKEPTIC_HOME=/proc/nope/x "$BIN/done-gate.sh")
[ -z "$out" ] && ok "done-gate fails open on unwritable state" || bad "done failopen" "$out"
echo "kind=pass edits=oops" > "$SKEPTIC_HOME/state/sess2/done"
out=$(stop); [ -z "$out" ] && ok "garbage marker = cannot tell = allow" || bad "garbage marker" "$out"
"$BIN/record.sh" done x </dev/null >/dev/null 2>"$SKEPTIC_HOME/err"; rc=$?
[ $rc -ne 0 ] && has REFUSED "$(cat "$SKEPTIC_HOME/err")" && ok "record.sh refuses with no session id" || bad "refuse" "rc=$rc"

echo "== error nudge"
fail1() { run post-tool.sh "{\"session_id\":\"sess3\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"make\"},\"error\":\"$1\"}"; }
o1=$(fail1 "Exit code 2 line 17: boom 0xdead"); o2=$(fail1 "Exit code 2 line 99: boom 0xbeef"); o3=$(fail1 "Exit code 2 line 3: boom 0x1")
[ -z "$o1" ] && has additionalContext "$o2" && [ -z "$o3" ] && ok "nudge fires exactly once, on the 2nd normalised repeat" || bad "nudge" "1=[$o1] 2=[$o2] 3=[$o3]"
o4=$(fail1 "a different failure entirely"); [ -z "$o4" ] && ok "a different error does not nudge" || bad "diff error" "$o4"

echo "== session-start"
printf '# Charter\nline "quoted" \\ back\n' > "$SKEPTIC_HOME/charter.md"
out=$(printf '{"session_id":"s"}' | "$BIN/session-start.sh")
has 'additionalContext' "$out" && has 'Charter' "$out" && ok "injects the charter" || bad "charter" "$out"
mkdir -p "$SKEPTIC_HOME/state/old" "$SKEPTIC_HOME/state/new"; touch -t 202001010000 "$SKEPTIC_HOME/state/old"
printf '{}' | "$BIN/session-start.sh" >/dev/null
[ ! -e "$SKEPTIC_HOME/state/old" ] && [ -e "$SKEPTIC_HOME/state/new" ] && ok "GC removes old dirs, keeps new" || bad "gc" "$(ls "$SKEPTIC_HOME/state")"
out=$(printf '{}' | SKEPTIC_HOME=/proc/nope "$BIN/session-start.sh"); rc=$?
[ $rc -eq 0 ] && ok "session-start tolerates errors (exit 0)" || bad "ss rc" "$rc"

printf '# C\r\nline\r\n' > "$SKEPTIC_HOME/charter.md"
out=$(printf '{}' | "$BIN/session-start.sh"); has '\r' "$out" && bad "CR leaked" "$out" || ok "CR in charter stripped (valid JSON)"

echo "== corrections log (auto-log)"
CH=$(mktemp -d); CF="$CH/corrections.md"
SKEPTIC_HOME="$CH" "$BIN/log-correction.sh" "added an unasked step" "do only what was asked"
has "After: do only what was asked" "$(cat "$CF" 2>/dev/null)" && ok "log-correction writes a dated before/after line" || bad "log-correction write" "$(cat "$CF" 2>&1)"
SKEPTIC_HOME="$CH" "$BIN/log-correction.sh" "second thing" "second fix"
case "$(head -1 "$CF")" in *"second fix"*) ok "newest correction goes on top" ;; *) bad "newest first" "$(head -1 "$CF")" ;; esac
SKEPTIC_HOME="$CH" "$BIN/log-correction.sh" "second thing again" "second fix"
[ "$(wc -l < "$CF" | tr -d ' ')" = 2 ] && ok "an exact repeat is not logged twice" || bad "dedupe" "$(cat "$CF")"
i=0; while [ $i -lt 60 ]; do i=$((i+1)); SKEPTIC_HOME="$CH" "$BIN/log-correction.sh" "before number $i padded padded padded padded padded padded padded padded padded" "after number $i padded padded padded padded padded padded padded padded padded"; done
sz=$(wc -c < "$CF" | tr -d ' ')
[ "$sz" -le 5000 ] && [ -s "$CH/corrections-archive.md" ] && ok "log stays under 5 KB; older lines move to the archive ($sz bytes)" || bad "cap" "size=$sz"
SKEPTIC_HOME="$CH" "$BIN/log-correction.sh" "only one arg" >/dev/null 2>&1; rc=$?
[ $rc -eq 2 ] && ok "missing argument is refused (usage, exit 2)" || bad "usage" "rc=$rc"
SKEPTIC_HOME=/proc/nope/x "$BIN/log-correction.sh" a b >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "unwritable log fails open (exit 0)" || bad "log failopen" "rc=$rc"
rm -rf "$CH"

echo "== prompt-submit (correction note)"
up() { printf '{"session_id":"s","hook_event_name":"UserPromptSubmit","prompt":"%s"}' "$1"; }
out=$(run prompt-submit.sh "$(up 'I told you not to add things')")
has additionalContext "$out" && has log-correction.sh "$out" && ok "a correction phrase injects the logging note" || bad "note" "$out"
out=$(run prompt-submit.sh '{"session_id":"s","prompt":"that'"'"'s not what I asked"}')
has additionalContext "$out" && ok "'that's not what I asked' is caught" || bad "thats not" "$out"
out=$(run prompt-submit.sh "$(up 'please run the tests again')"); [ -z "$out" ] && ok "an ordinary request injects nothing" || bad "plain" "$out"
out=$(run prompt-submit.sh '{"session_id":"s","tool_input":{"prompt":"I told you"}}'); [ -z "$out" ] && ok "a nested prompt key is ignored" || bad "nested prompt" "$out"
out=$(run prompt-submit.sh '{"session_id":"s"}'); [ -z "$out" ] && ok "no prompt: no note" || bad "no prompt" "$out"

echo "== risk (review depth)"
if command -v git >/dev/null 2>&1; then
  mk() { d=$(mktemp -d); ( cd "$d" && git init -q . && echo base > README.md && git add README.md && git -c user.email=t@t -c user.name=t commit -q -m base ) >/dev/null 2>&1; printf '%s' "$d"; }
  d=$(mk); echo "a small edit" >> "$d/README.md"
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = light ] && ok "small doc edit is light" || bad "light" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mk); echo "print(1)" > "$d/app.py"
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "a code file is full" || bad "code" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mk); echo "rule" > "$d/charter.md"
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "a charter file is full even though it is markdown" || bad "charter" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mk); mkdir "$d/commands"; echo "x" > "$d/commands/run.md"
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "a commands file is full" || bad "commands" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mk); i=0; while [ $i -lt 60 ]; do i=$((i+1)); echo "line $i" >> "$d/README.md"; done
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "a large doc change is full" || bad "large" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mk); echo "api_key = abc123" >> "$d/README.md"
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "a secret-looking line is full" || bad "secret" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mk)
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "no changes found is full" || bad "nochange" "$("$BIN/risk.sh" "$d" 2>&1)"
  d=$(mktemp -d)
  [ "$("$BIN/risk.sh" "$d" 2>/dev/null)" = full ] && ok "not a git folder is full" || bad "nogit" "$("$BIN/risk.sh" "$d" 2>&1)"
else
  ok "risk tests skipped: git not installed"
fi

echo "== review history"
HH=$(mktemp -d)
out=$(SKEPTIC_HOME="$HH" "$BIN/history.sh" stats); has "No reviews" "$out" && ok "stats with no history says so" || bad "empty stats" "$out"
CLAUDE_CODE_SESSION_ID=hs SKEPTIC_HOME="$HH" "$BIN/history.sh" fail done security "leaked a token" 2>/dev/null
has "|done|fail|security|leaked a token" "$(cat "$HH/history.log" 2>&1)" && ok "a FAIL is recorded with its principle" || bad "fail line" "$(cat "$HH/history.log" 2>&1)"
CLAUDE_CODE_SESSION_ID=hs SKEPTIC_HOME="$HH" "$BIN/history.sh" fail plan "[Nonsense]" "odd" 2>/dev/null
has "|plan|fail|other|odd" "$(cat "$HH/history.log")" && ok "an unknown principle is filed as other" || bad "other tag" "$(cat "$HH/history.log")"
CLAUDE_CODE_SESSION_ID=hs SKEPTIC_HOME="$HH" "$BIN/record.sh" done "fine" </dev/null >/dev/null 2>&1
has "|done|pass|-|fine" "$(cat "$HH/history.log")" && ok "record.sh PASS adds a history line" || bad "pass line" "$(cat "$HH/history.log")"
out=$(SKEPTIC_HOME="$HH" "$BIN/history.sh" stats)
has "Failures by principle" "$out" && has "security: 1" "$out" && has "Too few reviews" "$out" && ok "stats shows failures by principle and refuses to judge on few reviews" || bad "stats" "$out"
i=0; while [ $i -lt 20 ]; do i=$((i+1)); printf '2026-01-01T00:00:00-0500|x|done|pass|-|n\n' >> "$HH/history.log"; done
out=$(SKEPTIC_HOME="$HH" "$BIN/history.sh" stats)
has "never caused a failure:" "$out" && has "reuse" "$out" && ok "with 20+ reviews stats names principles that never failed anything" || bad "never failed" "$out"
case "$out" in *"never caused a failure: "*security*) bad "security listed as never" "$out" ;; *) ok "a principle that did fail is not listed as unused" ;; esac
( . "$BIN/lib.sh"; SK_HOME="$HH"; sid=x; i=0; while [ $i -lt 520 ]; do i=$((i+1)); sk_history done pass - n; done )
[ "$(wc -l < "$HH/history.log" | tr -d ' ')" -le 500 ] && ok "history is capped at 500 lines" || bad "history cap" "$(wc -l < "$HH/history.log")"
SKEPTIC_HOME=/proc/nope/x "$BIN/history.sh" fail done other x >/dev/null 2>&1; rc=$?
[ $rc -eq 0 ] && ok "history write fails open" || bad "history failopen" "rc=$rc"
rm -rf "$HH"

rm -rf "$SKEPTIC_HOME"
echo; echo "passed $pass, failed $fail"; [ "$fail" -eq 0 ]
