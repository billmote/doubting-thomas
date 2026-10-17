# Doubting Thomas

A fresh-context skeptic for Claude Code. Thomas reviews at three moments: before a plan, when the same error repeats, and before done. He gives a verdict (PASS or FAIL plus reasons) and never edits anything. Hooks make sure he is asked.

## The work loop

```mermaid
flowchart TD
    A([Session starts]) --> B[Charter + your corrections loaded]
    B --> C{First edit?}
    C -->|no plan PASS yet| D[Plan gate BLOCKS the edit]
    D --> E["/skeptic plan"]
    E --> F[Fresh Thomas reviews the plan]
    F -->|FAIL| G[Fix the plan] --> E
    F -->|PASS| H[Plan marker recorded]
    C -->|plan PASS on file| H
    H --> I[Work: each successful edit bumps the edit counter]
    I --> J{Same error twice?}
    J -->|yes| K[One-time note: step back, re-plan] --> K2["/skeptic plan"] --> K3[Fresh Thomas reviews the new approach] --> I
    J -->|no| L{Try to stop}
    L -->|edits since last done PASS| M[Done gate BLOCKS the stop]
    M --> N["/skeptic done"]
    N --> O[Fresh Thomas reviews the diff and test output]
    O -->|FAIL| P[Fix what he named] --> I
    O -->|PASS| Q[Done marker bound to the edit count]
    Q --> R([Session ends])
    Q -.->|edit again| I
```

1. **Plan gate.** The first file edit of a session is blocked until `/skeptic plan` records a PASS.
2. **Same-error checkpoint.** The second time the same error appears, Claude gets one note telling it to step back and run `/skeptic plan` with a new plan, so Thomas reviews the approach again. The hook only nudges; the review itself is Claude running the command. Never blocks.
3. **Done gate.** A session that edited files cannot stop until `/skeptic done` records a PASS for the current edit count. Edit again after a PASS and it needs a new one.

`/skeptic` spawns a fresh subagent that sees only the artifact, the charter and the corrections log. Not the build conversation.

### Who talks to whom

```mermaid
sequenceDiagram
    participant U as You
    participant A as Claude (main agent)
    participant H as Hooks
    participant S as State files
    participant W as Work subagent (builder, explorer)
    participant T as Thomas (fresh subagent)
    A->>H: first Edit/Write
    H->>S: plan marker?
    S-->>H: none
    H-->>A: DENY, run /skeptic plan
    A->>T: plan + charter + your corrections (nothing else)
    T-->>A: PASS or FAIL + reasons
    A->>S: record.sh plan (writes, reads back)
    A->>H: Edit/Write again
    H-->>A: allow
    loop each successful edit
        H->>S: edit counter + 1
    end
    opt same error twice
        H-->>A: one note: step back, run /skeptic plan
        A->>T: NEW plan + charter + your corrections
        T-->>A: PASS or FAIL + reasons
        A->>S: record.sh plan
    end
    A->>W: delegate a task
    W->>H: Edit/Write
    H-->>W: allow (subagents skip the plan gate)
    H->>S: edit counter + 1 (still counted)
    A->>H: try to stop
    H->>S: done marker covers current count?
    S-->>H: no
    H-->>A: BLOCK, run /skeptic done
    A->>T: diff + real test output + charter + corrections
    T-->>A: PASS or FAIL + reasons
    A->>S: record.sh done (bound to edit count)
    A->>U: short verdict
```

Work subagents are never blocked by the plan gate, but their edits still raise the counter, so the done gate still demands a review of everything they changed. (Hook code does not filter them out of the count; that they share the parent's session id is not verified live.)

Thomas is asked three times: at the first plan, when the same error repeats, and before done. Each time it is Claude running `/skeptic`, never a hook.

Hooks never ask Thomas anything. They only read state and say yes or no. Thomas never sees the build conversation.

## Install

**In Claude (Cowork / claude.ai):** download `dist/doubting-thomas.plugin` from this repo (https://github.com/billmote/doubting-thomas/raw/main/dist/doubting-thomas.plugin) and upload it as a plugin in your Claude settings. There is no `/plugin` command in Cowork sessions. Start a new session afterwards.

**In Claude Code (terminal):**

```
/plugin marketplace add https://github.com/billmote/doubting-thomas
/plugin install doubting-thomas@doubting-thomas
```

Restart the session. No plugin support? Use `bash scripts/install.sh` (merges hooks into `~/.claude/settings.json`, backs it up first; undo with `scripts/uninstall.sh`).

## Requirements

- Claude Code with hooks and plugins.
- `bash` plus standard Unix tools (`awk`, `sed`, `grep`, `cksum`, `date`, `find`, `cut`, `tr`, `head`, `cp`, `mv`, `mkdir`). Stock macOS (bash 3.2) and Linux are fine. No `jq`, `python3` or `git` needed by the hooks.
- Windows: use WSL or Git Bash.
- The reviewer model. `/skeptic` tries `fable`, then `opus`, then your default. Any model works, a stronger one reviews better.
- Python 3 only for `scripts/install.sh` and `scripts/uninstall.sh` (the settings merge).

## Make it yours

Your corrections go in `~/.claude/skeptic/corrections.md` (create it). Newest first, dated, before and after. Thomas is given it every session and at every review, and updates never overwrite it. A repeat of a logged correction is an automatic FAIL.

## Honest limits

- Edits made from the shell (`sed -i`, heredocs, redirects) are not gated or counted. Only Edit, Write, MultiEdit and NotebookEdit.
- `--defer` records NO review. The marker is an honesty checkpoint, not a security control; the agent could call the helper directly.
- Every hook fails open. An unwritable state dir or missing session id lets the action through, so a bug never bricks a session.
- Subagents are never gated.
- Edits to Claude's own plan files (`*/.claude/plans/*`) are neither gated nor counted.
- Thomas's session context is capped (about 12 KB across charter and your corrections), so keep `corrections.md` short.

## Test

```
bash tests/test.sh
```
