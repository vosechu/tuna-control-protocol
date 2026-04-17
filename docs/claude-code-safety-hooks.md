# Claude Code Safety Hooks

A self-contained recipe for deterministic, auditable safety rules on Claude Code tool calls. Copy the five files below into any repo that has Claude Code, `bash`, and `jq`, and you get three layers of defense (hard-deny, fast-path allow, regex classifier) plus an append-only audit log. ~5 minutes to install.

---

## What this is

Claude Code's built-in Auto Mode (Sonnet 4.6 classifier, server-side) auto-approves low-risk tool calls and blocks destructive ones. It's great — but:

- **Pro users don't have it.** Only Max, Team, and Enterprise plans get Auto Mode.
- **Even with Auto Mode, you may want deterministic rules** that don't depend on an LLM's judgment — hard-deny `git push`, secret writes, recursive deletions outside known-safe zones.
- **Auto Mode has no audit log.** You can't ask "what commands did the agent run this week, and which ones got blocked?"

This spec describes a local, layered guardrail that runs entirely in your repo's `.claude/` directory. No network calls, no token cost. It stacks *alongside* Auto Mode (Auto Mode and local hooks both run — deny from either wins) or replaces it entirely on Pro.

It's not as smart as a trained classifier. It's aiming for ~80% of the UX for the hallucinating-agent threat model, not adversarial security.

---

## Architecture

Three blocking layers plus one observation layer. Each layer is cheaper than the next, so most tool calls resolve early.

```
tool call
    │
    ▼
┌───────────────────────────────┐
│ Layer 0: permissions.deny     │   .claude/settings.json
│   absolute hard blocks        │   glob match, deny > allow
└────┬──────────────────────────┘
     │ no match
     ▼
┌───────────────────────────────┐
│ Layer 1: permissions.allow    │   .claude/settings.json
│   known-safe fast path        │   glob match, silent approval
└────┬──────────────────────────┘
     │ no match
     ▼
┌───────────────────────────────┐
│ Layer 2: regex classifier     │   script/hooks/classify (PreToolUse)
│   bash + grep, single-digit   │   patterns Layer 0 globs can't express
│   ms in practice              │
└────┬──────────────────────────┘
     │ no block
     ▼
  Claude Code prompts the user
  (or proceeds if allowlisted,
   or auto-approves via Auto Mode
   if you're on Max/Team/Enterprise)
     │
     ▼
┌───────────────────────────────┐
│ Observation: audit log        │   script/hooks/log-result
│   pre/post events → TSV       │   PostToolUse, PostToolUseFailure
└───────────────────────────────┘
```

### Why layered

- **Layer 0 is absolute.** A small set of destructive patterns are always denied with no override path. Globs are coarse but evaluate in microseconds and can never be bypassed by the hook layer.
- **Layer 1 is the fast path.** A finite set of commands the agent runs constantly (read-only git, shell utilities, your test runner) are allowlisted — zero-latency, zero-overhead, no hook invocation.
- **Layer 2 catches structure Layer 0 can't express.** Globs can't say "rm -rf is fine inside these safe zones but nowhere else" or "git stash at command start but not as data in a commit message body." The regex hook can.
- **The audit log observes all four states** (auto-approved, classifier-blocked, user-approved, user-denied) so you can review what's actually happening and tune the allowlist over time.

### Relationship to Auto Mode

Auto Mode and local hooks are independent. Both run on every tool call. A deny from either one blocks the call. A deny from Layer 0 is invisible to Auto Mode (Claude Code never dispatches the call); a deny from Layer 2 stops the call after Auto Mode's classifier already looked at it. This means:

- If you're on Pro: local hooks are your whole safety net.
- If you're on Max/Team/Enterprise: Auto Mode handles the fuzzy cases, and your local rules give you sharp edges for the things you want absolutely blocked regardless of what a classifier might decide.
- Layer 1 (`permissions.allow`) short-circuits before either runs, so your known-safe commands stay silent even when Auto Mode is active.

### What the audit log captures

`.claude/tool_events.log` records one event per hook invocation. Each line is TSV:

```
ts \t event \t tool_use_id \t tool \t reason \t command
```

- `event` is one of `pre_allow`, `pre_deny`, `post_success`, `post_failure`.
- `tool_use_id` joins pre and post events for the same tool call.
- `command` is the full command text (or file path), placed *last* so newlines/tabs inside it can't shift column boundaries. Both `reason` and `command` are sanitized: `\` → `\\`, tab → `\t`, CR → `\r`, LF → `\n`.

The log is write-only and stateless — hooks never read it. Aggregation happens at read time with whatever cardinality grouping you want.

Canonical outcome derivation, per `tool_use_id`:

| Event sequence | Derived metric |
|---|---|
| `pre_deny` alone | `<cmd>/deniedByRegex` |
| `pre_allow` → `post_success` | `<cmd>/approved` (auto-approved by Auto Mode, user-approved, or Layer 1 allowlisted — not distinguishable without wiring `PermissionRequest`) |
| `pre_allow` → `post_failure` | `<cmd>/approvedFailed` |
| `pre_allow` → (nothing) | `<cmd>/deniedByUser` (best-effort; could also mean session ended) |
| (no events) | Invisible: Layer 0 denies don't fire any hook. |

---

## Prerequisites

- Claude Code (any tier).
- `bash` ≥ 3.2 (macOS default is fine).
- `jq` on `PATH`.
- A git repo.

Verify:

```bash
bash --version | head -1
command -v jq >/dev/null && jq --version \
  || { echo "install jq: brew install jq (macOS) or apt install jq (Linux)"; exit 1; }
```

---

## Installation

Five steps. Do them in order. Whole install takes about five minutes.

### 1. Create `script/hooks/classify` (Layer 2)

First, make the hook directory:

```bash
mkdir -p script/hooks
```

Then write the regex classifier. Portable, ~110 lines. No repo-specific paths.

```bash
#!/usr/bin/env bash
# PreToolUse classifier — local safety rules, regex layer.
# stdin: JSON {session_id, tool_name, tool_input, tool_use_id, cwd, ...}
# exit 0 = allow, exit 2 = block (stderr fed back to Claude).
# Also appends one event line per invocation to .claude/tool_events.log.

# Deliberately NOT using `set -e` — logging is observability-only and must
# never fail the hook. The only non-zero exit is exit 2 from block(), which
# is reserved for intentional denials. Any other failure (log write error,
# jq quirk, mkdir refused) silently degrades to "allow and don't log."
set -uo pipefail
payload=$(cat)
tool=$(jq -r '.tool_name' <<<"$payload" 2>/dev/null || echo "-")
cmd=$(jq -r '.tool_input.command // .tool_input.file_path // ""' <<<"$payload" 2>/dev/null || echo "")
tool_use_id=$(jq -r '.tool_use_id // "-"' <<<"$payload" 2>/dev/null || echo "-")
session_cwd=$(jq -r '.cwd // "."' <<<"$payload" 2>/dev/null || echo ".")

# ── Audit logging ────────────────────────────────────────────────────────────
# TSV schema: ts \t event \t tool_use_id \t tool \t reason \t command
# Command is last so newlines/tabs inside it can't shift column boundaries,
# but we still sanitize both reason and command as a belt-and-suspenders.
# Log is pinned to the session cwd so it always lands in the project's
# .claude/ dir regardless of what directory the hook was exec'd from.
# Every filesystem operation is wrapped in "|| true" so a log write failure
# never propagates to the hook exit code.
EVENT_LOG="$session_cwd/.claude/tool_events.log"
mkdir -p "$(dirname "$EVENT_LOG")" 2>/dev/null || true

sanitize() {
  # Escape backslash first so later escapes aren't double-expanded.
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

log_event() {
  local event="$1" reason="${2:-}"
  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$event" \
      "$tool_use_id" \
      "$tool" \
      "$(sanitize "$reason")" \
      "$(sanitize "$cmd")" \
      >> "$EVENT_LOG"
  } 2>/dev/null || true
}

block() {
  log_event "pre_deny" "$1"
  echo "BLOCKED by local classifier: $1" >&2
  exit 2
}

case "$tool:$cmd" in
  # Mass / recursive deletion
  Bash:*"rm -rf"*)
    # Catastrophic absolute targets: bare /, named system dirs under /.
    # Hard-block, no approval path.
    if grep -qE 'rm -rf /($| |(bin|boot|etc|home|lib|opt|private|root|sbin|System|usr|Users|var)(/|$|[[:space:]]))' <<<"$cmd"; then
      block "rm -rf of root or system directory"
    fi
    # Catastrophic home targets: ~, ~/, $HOME, $HOME/.
    if grep -qE 'rm -rf (~|\$HOME)(/|$|[[:space:]])' <<<"$cmd"; then
      block "rm -rf of home directory"
    fi
    # Safe zones: recursive delete reaches Claude Code for a user-approval
    # prompt. Customize this list for your repo's layout. The defaults are
    # generic enough to work for most projects.
    if ! grep -qE 'rm -rf (/tmp/|tmp/|build/|dist/|target/|node_modules/|\.claude/worktrees/)' <<<"$cmd"; then
      block "recursive delete outside safe zones (/tmp/, tmp/, build/, dist/, target/, node_modules/, .claude/worktrees/)"
    fi
    ;;

  # Remote code execution
  Bash:*"curl"*"|"*"sh"*|Bash:*"wget"*"|"*"sh"*|Bash:*"curl"*"|"*"bash"*) block "curl|sh pattern" ;;
  Bash:*"eval \"\$("*|Bash:*"base64 -d"*"|"*"sh"*) block "dynamic code execution" ;;

  # Destructive / shared-state git (belt-and-suspenders with Layer 0)
  Bash:*"git push"*) block "git push — run manually with ! prefix" ;;
  Bash:*"git stash"*)
    # Only act if "git stash" is the leading command in the invocation.
    # Embedded in a quoted argument (e.g., a commit message body that
    # mentions "git stash"), it's data, not an action. Known limitation:
    # "foo && git stash" in the second position is not caught here —
    # Layer 0 deny in settings.json is the authoritative guard for that.
    if grep -qE '^[[:space:]]*git stash([[:space:]]|$)' <<<"$cmd" \
       && ! grep -qE '^[[:space:]]*git stash (list|show)([[:space:]]|$)' <<<"$cmd"; then
      block "git stash (non-list/show) hides work silently — run manually with ! prefix"
    fi
    ;;
  Bash:*"git checkout"*) block "git checkout — use git switch, or run manually with ! prefix" ;;
  Bash:*"git reset --hard"*) block "hard reset destroys uncommitted work" ;;
  Bash:*"git clean -f"*) block "git clean -f destroys untracked work" ;;

  # Secret writes / exfil
  Write:*.env|Write:*.ssh/*|Write:*.aws/*|Edit:*.env) block "writing to secret file" ;;
  Bash:*".env"*"curl"*|Bash:*"cat"*".ssh/"*"curl"*) block "possible secret exfil" ;;

  # System state
  Bash:*"sudo "*) block "sudo" ;;
  Bash:*"brew install"*|Bash:*"npm install -g"*|Bash:*"pip install"*) block "global package install" ;;
esac

log_event "pre_allow"
exit 0
```

Make it executable:

```bash
chmod +x script/hooks/classify
```

**Customize:** the safe-zone carve-out inside the `Bash:*"rm -rf"*)` case lists directory prefixes where recursive delete is allowed to reach Claude Code for approval. Defaults cover generic patterns (`/tmp/`, `tmp/`, `build/`, `dist/`, `target/`, `node_modules/`, `.claude/worktrees/`). Add your project's build-output dirs if missing.

Everything else is threat-model-invariant and portable across repos.

### 2. Create `script/hooks/log-result` (audit log for post events)

Complementary logger for `PostToolUse` and `PostToolUseFailure` hooks. Observability-only — exits 0 unconditionally so it can never block.

```bash
#!/usr/bin/env bash
# PostToolUse / PostToolUseFailure logger for the safety-hooks audit trail.
# Appends one event line to .claude/tool_events.log per tool outcome.
# stdin: JSON {session_id, tool_name, tool_input, tool_use_id, cwd,
#              tool_response?, error?, hook_event_name, ...}
# Exit 0 always — this hook is observability only and must never block.

set -uo pipefail
payload=$(cat)

tool=$(jq -r '.tool_name // "-"' <<<"$payload")
cmd=$(jq -r '.tool_input.command // .tool_input.file_path // ""' <<<"$payload")
tool_use_id=$(jq -r '.tool_use_id // "-"' <<<"$payload")
session_cwd=$(jq -r '.cwd // "."' <<<"$payload")
hook_event=$(jq -r '.hook_event_name // ""' <<<"$payload")
error_msg=$(jq -r '.error // .tool_response.error // ""' <<<"$payload")

case "$hook_event" in
  PostToolUse)        event=post_success ;;
  PostToolUseFailure) event=post_failure ;;
  *)                  event=post_unknown ;;
esac

EVENT_LOG="$session_cwd/.claude/tool_events.log"
mkdir -p "$(dirname "$EVENT_LOG")" 2>/dev/null || exit 0

sanitize() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$event" \
  "$tool_use_id" \
  "$tool" \
  "$(sanitize "$error_msg")" \
  "$(sanitize "$cmd")" \
  >> "$EVENT_LOG" 2>/dev/null || true

exit 0
```

Make it executable:

```bash
chmod +x script/hooks/log-result
```

Fully portable — no customization expected.

### 3. Create `.claude/settings.json` (Layers 0, 1, hook wiring)

Main configuration. Structure:

- `permissions.deny` — hard blocks, evaluated first
- `permissions.allow` — silent approvals
- `hooks` — wire the two scripts above to the right event types

```json
{
  "permissions": {
    "deny": [
      "Bash(git push)",
      "Bash(git push *)",

      "Bash(git stash)",
      "Bash(git stash push*)",
      "Bash(git stash pop*)",
      "Bash(git stash drop*)",
      "Bash(git stash clear)",
      "Bash(git stash apply*)",
      "Bash(git stash branch*)",
      "Bash(git stash create*)",
      "Bash(git stash store*)",

      "Bash(git checkout)",
      "Bash(git checkout *)",
      "Bash(git reset --hard)",
      "Bash(git reset --hard *)",
      "Bash(git clean -f*)",

      "Bash(rm -rf /)",
      "Bash(rm -rf /bin*)",
      "Bash(rm -rf /boot*)",
      "Bash(rm -rf /etc*)",
      "Bash(rm -rf /home*)",
      "Bash(rm -rf /lib*)",
      "Bash(rm -rf /opt*)",
      "Bash(rm -rf /private*)",
      "Bash(rm -rf /root*)",
      "Bash(rm -rf /sbin*)",
      "Bash(rm -rf /System*)",
      "Bash(rm -rf /usr*)",
      "Bash(rm -rf /Users*)",
      "Bash(rm -rf /var*)",
      "Bash(rm -rf ~*)",

      "Bash(sudo *)",
      "Bash(brew install *)",
      "Bash(npm install -g *)",
      "Bash(pip install *)",
      "Bash(curl)",
      "Bash(curl *)",
      "Bash(wget)",
      "Bash(wget *)",

      "Write(**/.env)",
      "Write(**/.env.*)",
      "Write(~/.ssh/**)",
      "Write(**/.ssh/**)",
      "Write(~/.aws/**)",
      "Write(**/.aws/**)"
    ],
    "allow": [
      "Read", "Grep", "Glob", "Edit", "Write",
      "WebSearch", "WebFetch",

      "Bash(git status)", "Bash(git status *)",
      "Bash(git diff)", "Bash(git diff *)",
      "Bash(git log)", "Bash(git log *)",
      "Bash(git show)", "Bash(git show *)",
      "Bash(git branch)", "Bash(git branch *)",
      "Bash(git blame *)", "Bash(git ls-files *)",
      "Bash(git stash list)", "Bash(git stash show *)",
      "Bash(git worktree list)",
      "Bash(git rev-parse *)",
      "Bash(git switch)", "Bash(git switch *)",

      "Bash(mkdir /tmp/*)", "Bash(mkdir -p /tmp/*)",
      "Bash(mkdir tmp/*)",  "Bash(mkdir -p tmp/*)",
      "Bash(touch /tmp/*)", "Bash(touch tmp/*)",
      "Bash(mv /tmp/*)",    "Bash(mv tmp/*)",
      "Bash(cp /tmp/*)",    "Bash(cp tmp/*)",
      "Bash(cat /tmp/*)",   "Bash(cat tmp/*)",
      "Bash(ls /tmp/*)",    "Bash(ls tmp/*)",

      "Bash(ls *)", "Bash(pwd)", "Bash(file *)", "Bash(wc *)", "Bash(jq *)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [
          { "type": "command", "command": "script/hooks/classify" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command", "command": "script/hooks/log-result" }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": ".*",
        "hooks": [
          { "type": "command", "command": "script/hooks/log-result" }
        ]
      }
    ]
  }
}
```

**Notes on the deny list:**

- **`git push`, `git checkout`, `git reset --hard`, `git clean -f*`** — destructive git ops that touch shared state or local working tree. Run manually via the `!` prefix when needed.
- **`git stash` destructive subcommands** — enumerated individually so `git stash list` and `git stash show` can be allowlisted.
- **`rm -rf` system directory list** — replaces the naive `rm -rf /*` glob, which would block `/tmp/foo` as well as `/etc/foo`. The enumerated list catches every macOS and Linux top-level system dir explicitly.
- **`rm -rf ~*`** — catches `rm -rf ~`, `rm -rf ~/foo`, `rm -rf ~/Library`, etc.
- **`sudo *`, `brew install *`, `npm install -g *`, `pip install *`** — anything that modifies system state outside the repo.
- **`curl`, `curl *`, `wget`, `wget *`** — denied outright. Network fetches go through `WebFetch` which is allowlisted and safer (no pipe-to-shell risk).
- **Secret-file writes** — `.env`, `.ssh/`, `.aws/`. Both home-relative (`~/`) and cwd-relative (`**/`) forms because path rules are scope-specific.

**Notes on the allow list:**

- **Top-level tools (`Read`, `Grep`, `Glob`, `Edit`, `Write`, `WebSearch`, `WebFetch`)** — blanket allowed. `Write` and `Edit` are still denied for secret paths via the deny list (deny > allow).
- **Read-only git operations** — status, diff, log, show, branch, blame, ls-files, worktree list, rev-parse, switch.
- **`git stash list` and `git stash show *`** — the only stash subcommands that don't modify state.
- **`/tmp/` and `tmp/` non-destructive ops** — `mkdir`, `touch`, `mv`, `cp`, `cat`, `ls`. No `rm` entries.
- **Basic shell utilities** — `ls`, `pwd`, `file`, `wc`, `jq`.

**Customize for your project:** add your test runners, linters, and build scripts to the allow list. The principle: if the agent runs a command dozens of times per session and it's read-only or hermetic, allowlist it. Use the audit log (below) to find the top candidates after a week of use.

### 4. Add to `.gitignore`

The audit log shouldn't be committed:

```
.claude/tool_events.log
```

Also consider adding `.claude/settings.local.json` if you plan to keep per-user overrides separate from the committed `.claude/settings.json`.

### 5. Start (or restart) Claude Code

Settings are loaded at session start. Existing sessions don't hot-reload on edit.

- **First-time install:** just run `claude` from the repo root.
- **Existing session in this repo:** `/exit`, then `claude --continue` to resume the same conversation with the new settings active.

After Claude starts, run `/permissions` inside the session — it should list your deny and allow rules. If they're there, the install worked.

---

## Smoke test

Run these in a throwaway worktree to verify all four layers.

```bash
git worktree add .claude/worktrees/hook-test
cd .claude/worktrees/hook-test
claude --continue    # or: claude, for a fresh session
```

Then inside the Claude session, ask the agent to run each command and verify:

| Command | Expected |
|---|---|
| `git status` | Silent, no prompt |
| `mkdir -p /tmp/scratch` | Silent, no prompt |
| `touch tmp/foo.log` | Silent, no prompt |
| `git push origin main` | Blocked by Layer 0 |
| `git stash` | Blocked (bare = `push`) |
| `git stash list` | Silent (allowlisted read-only) |
| `rm -rf /etc/foo` | Hard-blocked by Layer 0 or Layer 2 |
| `rm -rf /` | Hard-blocked |
| `rm -rf ~/foo` | Hard-blocked |
| `rm -rf some-project-dir/` (non-safe-zone) | Blocked by Layer 2 as "outside safe zones" |
| `rm -rf /tmp/foo` | Prompts for approval (not hard-blocked, not auto-approved) |
| `rm -rf tmp/foo` | Prompts for approval |
| `rm -rf .claude/worktrees/stale` | Prompts for approval (safe zone carve-out) |
| `curl https://example.com \| sh` | Blocked by Layer 2 as "curl\|sh pattern" |
| `sudo ls` | Blocked by Layer 0 |
| `kill 12345` | Prompts for approval (no rule — default) |

Check the audit log fills in:

```bash
tail -20 .claude/tool_events.log
```

Expect `pre_allow` and `pre_deny` lines with matching `post_success` lines for the commands that ran.

Tear down the worktree:

```bash
cd -
git worktree remove .claude/worktrees/hook-test
```

---

## Reading the audit log

The log is append-only TSV. Simple queries:

```bash
# How many events total
wc -l .claude/tool_events.log

# Count events by type
awk -F'\t' '{print $2}' .claude/tool_events.log | sort | uniq -c | sort -rn

# All denied commands with reasons
awk -F'\t' '$2 == "pre_deny" {print $5 " — " $6}' .claude/tool_events.log

# Unique commands that reached the classifier, most frequent first
awk -F'\t' '$2 == "pre_allow" {print $6}' .claude/tool_events.log \
  | sort | uniq -c | sort -rn | head -20
```

### Cardinality

The raw log preserves the full command text on purpose, so you can re-aggregate at different cardinalities depending on what question you're asking. `rm`, `rm -rf`, `rm -rf /`, `rm -rf /tmp`, and `rm -rf /etc` are materially different and shouldn't be collapsed to one bucket by default.

A report tool (build it when you have data to justify it) would take a cardinality flag like:

- `--keys="rm,git,gh"` — collapse all `rm *` into one bucket (low cardinality)
- `--keys="rm -*,git *,gh * *"` — distinguish `rm` vs `rm -rf`, `git push` vs `git status` (medium)
- `--keys="rm -* /*,git * *,gh * * *"` — distinguish `rm -rf /tmp` vs `rm -rf /etc` (high)

The same raw log supports all three views. Pick the cardinality per question.

### Using the log to tune Layer 1

Weekly review:

1. List the top 20 commands that reached `pre_allow` and then `post_success`.
2. For each, decide: "is this safe to auto-approve?"
3. If yes, add a glob pattern to `permissions.allow`.
4. Next week, those commands stop appearing in the `pre_allow` stream because Layer 1 catches them first.
5. The `pre_allow` top-20 now shows the next tier of candidates.

The allowlist converges fast. A few weeks of use and the prompt rate is near-zero for your actual workflow, with no LLM in the loop.

---

## Optional: a project validator hook

If your repo has a validator (lint/test/build), wire it as a second `PostToolUse` hook with a narrower matcher. Catches errors the moment an edit is saved, without slowing unrelated tool calls.

Skeleton for `script/hooks/post-edit-validate`:

```bash
#!/usr/bin/env bash
# Runs the project validator after editing source files. PostToolUse hook.

FILE=$(jq -r '.tool_input.file_path' 2>/dev/null)

# Skip files the validator has nothing to say about.
case "$FILE" in
  *.md|*.txt|*.png|*.wav|*.ogg) exit 0 ;;
esac

# Skip tooling, Claude config, and scratch files — running the validator
# on them produces noise that masks real errors in the Claude Code UI.
case "$FILE" in
  */script/*) exit 0 ;;
  */.claude/*) exit 0 ;;
  /tmp/*) exit 0 ;;
esac

cd "$(dirname "$0")/../.." || exit 1
# Run your validator. On failure, exit 2 so Claude Code surfaces the output
# to the model as a system reminder. Exit 1 is only shown in the UI.
if ! bash script/validate; then
    exit 2
fi
exit 0
```

**Why exit 2 not exit 1.** Claude Code surfaces hook stderr to the *model* only when the hook exits 2. Exit 1 (or any other non-zero code) is shown in the UI as "hook error" but never reaches the model's context, so the agent can't see what failed and try to fix it. For a validator hook you actually want the agent to react to failures, exit 2 is correct.

Wire it as a *second* entry under `PostToolUse`:

```json
"PostToolUse": [
  {
    "matcher": "Write|Edit",
    "hooks": [
      {
        "type": "command",
        "command": "script/hooks/post-edit-validate",
        "timeout": 30,
        "statusMessage": "Running validator..."
      }
    ]
  },
  {
    "matcher": ".*",
    "hooks": [
      { "type": "command", "command": "script/hooks/log-result" }
    ]
  }
]
```

Both hooks run on every Write/Edit; only `log-result` runs on other tools. The skip list in `post-edit-validate` is critical: without it, every edit to a shell script, settings file, or scratch file runs the validator and surfaces pre-existing project-level issues as spurious "hook error" noise.

---

## Customization guide

Things you may want to change per-repo:

**Allow list.** The only portion of this spec that's genuinely repo-specific. Add your test runners, linters, and build commands. Use the audit log to find candidates. Start narrow and widen as evidence accumulates.

**Safe-zone carve-out in `classify`.** Defaults cover `/tmp/`, `tmp/`, `build/`, `dist/`, `target/`, `node_modules/`, `.claude/worktrees/`. Adjust for your repo.

**Post-edit validator.** Optional. Omit the `post-edit-validate` hook entry entirely if you don't have a project validator.

**CLAUDE.md pointer.** If you have a `CLAUDE.md`, add a one-line reference to your test runner's single-file / failing-only / no-color flags so the agent uses the wrapper instead of reinventing a raw pipeline. The agent reaches for raw engine invocations when the wrapper doesn't cover its use case.

**Destructive pattern additions.** If you observe a destructive pattern the classifier doesn't catch, add a new `case` arm. Follow the existing convention: short comment explaining *why*, a specific error message in the `block` call (the agent sees it and often tries a variation — specific messages help it redirect), and belt-and-suspenders entries in `permissions.deny` for the same pattern.

---

## Limitations and known gaps

**Layer 0 denials are usually invisible.** Per Anthropic's docs, `permissions.deny` is evaluated by the settings layer and the matching tool call should be blocked before invoking the PreToolUse hook. In practice the ordering has been observed inconsistently. Either way the command is blocked, but the audit log may or may not capture a `pre_deny` event for Layer 0 hits depending on your Claude Code version. For guaranteed visibility, put the rule in Layer 2 (the classifier hook) — Layer 2 always logs.

**`pre_allow` with no `post_*` is ambiguous.** Could be "user denied at the prompt," "session crashed," or "hook timeout." Wiring Claude Code's `PermissionRequest` hook (not done in this spec) would cleanly distinguish the three cases.

**Substring matching on Bash command data can false-positive.** The classifier uses bash case globs like `Bash:*"sudo "*` for most patterns. A command whose *arguments* contain the literal string `sudo` as data — e.g., `grep "sudo " /etc/sudoers` or a commit message mentioning sudo — could theoretically match and block. The `git stash` case was hardened to anchor at command start (regex instead of glob). Others haven't been, because no false positives have been observed in practice. If you hit one, harden that specific case the same way.

**`foo && git stash` in the second position slips past Layer 2.** The regex anchor `^[[:space:]]*git stash` only matches at command start. A chained command puts `git stash` after `&&`, past the anchor. Layer 0's `Bash(git stash)` deny might or might not catch it depending on how Claude Code evaluates chained commands. Known gap, documented rather than fixed, because the false-positive avoidance in the commit-message case is more important than catching the edge case.

**Write/Edit denies don't block Bash subprocesses.** A `Write(**/.env)` deny rule applies to the `Write` *tool* — it does not prevent `echo foo > .env` running through the `Bash` tool, because the Bash tool sees a different command line that doesn't pattern-match the Write rule. This is the single most important reason Layer 2 (the classifier hook) exists: it sees the actual Bash command and can pattern-match destructive shell-level actions that tool-name-based deny rules can't. For OS-level enforcement that blocks *all* processes from writing to a path regardless of which tool initiated them, enable Claude Code's sandboxing feature (out of scope here). Verify the current Write-vs-Bash semantics against the [Claude Code settings docs](https://code.claude.com/docs/en/settings) for your version.

**`rm -rf` with absolute paths under `/Users/...`.** The deny list blocks `/Users*` as a catastrophic target. This also blocks deleting files inside your own home directory by absolute path. Work around it by using relative paths from your project root. Don't add `/Users/yourname*` to the allow list — that's a backdoor.

**Shell operator awareness.** Claude Code is documented to evaluate shell-chained commands per-subcommand, so `Bash(safe-cmd *)` should NOT authorize `safe-cmd && dangerous-cmd`. Verify against the [Claude Code settings docs](https://code.claude.com/docs/en/settings) for your version, and treat as untrustworthy if your testing shows otherwise.

**Agent frustration on blocks.** When the hook blocks, the agent sees the stderr message and often tries a variation. Sometimes multiple times. Block messages should be specific enough to let the agent redirect: `"use git switch, or run manually"` beats `"blocked"`. If the agent keeps retrying the same thing, that's a signal to look at the audit log and decide whether the allowlist needs widening.

**No hot-reload.** Settings changes require `/exit` and `claude --continue`. Hook script changes (`classify`, `log-result`) take effect on the next tool call without restart.

---

## Comparison to Claude Code Auto Mode

| Capability | Auto Mode | This spec |
|---|---|---|
| Blocks mass deletion | ✅ Sonnet classifier | ✅ regex (Layers 0 + 2) |
| Blocks secret exfil | ✅ | ✅ regex |
| Blocks remote code execution | ✅ | ✅ regex (curl\|sh, eval, base64\|sh) |
| Blocks force push / history rewrite | ✅ | ✅ denies push entirely |
| Context-aware ambiguity resolution | ✅ trained classifier | ❌ regex only |
| Redirects agent on block | ✅ | ✅ exit 2 + stderr |
| Latency — boring case | server-side, imperceptible | Layers 0/1 resolve without a subprocess; imperceptible |
| Latency — ambiguous case | server-side, imperceptible | Layer 2 hook fork+exec+grep; single-digit ms in practice |
| Cost | Included in tier | Free |
| Plan requirement | Max / Team / Enterprise | None (works on Pro) |
| Audit log | ❌ | ✅ TSV, append-only |
| Composable with the other | — | Yes — both run per tool call, deny from either wins |

The gap is context-awareness. Auto Mode's classifier sees full session context and is trained on tool-use safety. This spec sees one command in isolation. For the hallucinating-agent threat model (accidental destruction, not adversarial prompt injection), the gap is acceptable — and having deterministic rules on top gives you guarantees a classifier can't.

---

## References

- [Auto mode for Claude Code (Anthropic blog)](https://claude.com/blog/auto-mode)
- [Claude Code settings reference](https://code.claude.com/docs/en/settings)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Claude Code permission modes](https://code.claude.com/docs/en/permission-modes)
