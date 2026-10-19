---
description: Thomas (the Skeptic) reviews your plan or finished work in a fresh context and records the verdict that opens the gate
argument-hint: "[plan|done|stats] [--defer] [--full] [summary]"
---
Run Thomas, the Skeptic. Arguments: $ARGUMENTS

1. First word is `plan`, `done` or `stats` (if missing: `plan` when no edits have been made this session, else `done`). Keep the rest as the summary.
   - `stats`: run `~/.claude/skeptic/bin/history.sh stats`, show the output, and stop. It reports which principles actually cause FAILs; it changes nothing.
2. **`--defer`** present: do NOT spawn Thomas. Run `~/.claude/skeptic/bin/record.sh <plan|done> --defer <summary>`, read its stderr, and tell the user in one line that this recorded NO review.
3. Otherwise pick the depth, then spawn ONE fresh subagent.
   - `plan` is always a full review.
   - `done`: run `~/.claude/skeptic/bin/risk.sh` in the project directory. It prints `light` or `full` (reason on stderr). `--full` forces a full review. Any doubt means full.
   - **full:** `subagent_type: general-purpose` (it needs Bash so it can execute things), the strongest model you can use (try `fable`, then `opus`, then the default; pin it explicitly, never rely on the default if a stronger one works).
   - **light** (a small documentation-only change): same subagent type, model `sonnet`. Add to its instructions: "Light review of a small documentation change. Check only: is it accurate, did it add anything that was not asked for, does anything look like a secret. One line."
   Give it ONLY:
   - the artifact: for `plan`, the plan text; for `done`, the real diff (`git diff` plus untracked files) or the full text of the files changed, and the exact commands/tests run with their real output;
   - the charter path `~/.claude/skeptic/charter.md` and, if it exists, `~/.claude/skeptic/corrections.md` (the user's own Corrections log; tell the reviewer to read both).
   - NEVER the build conversation, and never a defense of the work.
   Its instructions, verbatim: "You are Thomas. Verdict only: PASS or FAIL plus reasons. Plan: is this the right approach, and does it already exist? Done: what did we miss, would the owner correct this? A repeat of a logged correction is an automatic FAIL. Do not write, edit or fix anything. Cite only tool output you actually received; anything else say 'not verified'. A verdict citing evidence you did not receive is itself a FAIL." Then add: "Start each FAIL reason with the principle it breaks in brackets, for example [reuse] or [security]. Allowed: reuse, simplicity, design, correctness, security, ux, pwa, graphic, verification, maintainability, correction, other."
4. **PASS:** run `~/.claude/skeptic/bin/record.sh <plan|done> "<Thomas's one-line verdict>"`. Read its stderr: only if it says `recorded` is the gate cleared. If it says REFUSED or FAILED, say so plainly; do not claim the gate cleared. For `done`, record.sh prints a receipt `T-...` on stdout; put it in your commit message if you like.
5. **FAIL:** run `~/.claude/skeptic/bin/history.sh fail <plan|done> <principle> "<the reason>"` using the bracketed principle from his verdict (`other` if none). Then fix what he named and run `/skeptic` again. After a second FAIL on the same work, re-plan from step 1 (do not bring it to the user unless it truly cannot be done).
6. Reply to the user in at most two lines: verdict and what, if anything, you changed.
