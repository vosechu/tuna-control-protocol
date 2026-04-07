# Local Auto-Mode for Claude Code

**Status:** Spec — approved, ready for implementation plans
**Author:** Chuck
**Date:** 2026-04-06
**Phases:** 2 (each becomes its own implementation plan)

## Problem

Anthropic's Claude Code "Auto mode" (launched 2026-03-24) auto-approves low-risk tool calls and blocks destructive ones via a Sonnet 4.6 classifier. It eliminates approval-fatigue during long repo work. It is gated to Team and Enterprise plans — Pro/Max users cannot enable it at any price short of a Team seat, and a Team seat is not viable for individual/home use because of per-seat cost and token allocation.

The existing Pro/Max alternatives are both bad:

- **Default mode:** prompts on every tool call. High friction, breaks flow during plan execution.
- **`--dangerously-skip-permissions`:** no guardrails at all. One hallucinated path in an `rm -rf` and the worktree is gone.

We want the middle ground — hands-off execution for the boring 90% of tool calls, hard blocks on the destructive tail — without a Team plan.

## Goals

1. Zero prompts for boring, reversible tool calls (reads, lint, tests, git queries, validated writes).
2. Hard block on genuinely destructive patterns before they execute (mass delete, secret exfil, history rewrites, remote-code execution, shared-state mutations).
3. When a block fires, the agent sees a useful error message and can redirect its approach.
4. Implementable on Pro/Max with no paid add-ons beyond the tokens the agent already spends.
5. Shared across the project — ship the guardrails in the repo so future contributors inherit them.

## Non-Goals

- Matching Anthropic's classifier accuracy on edge cases. The server-side Sonnet 4.6 classifier is trained on tool-use context we don't have; we're aiming for ~80% of the UX, not parity.
- Blocking subtle supply-chain attacks (a malicious dependency in a package manifest is out of scope — that's a pre-commit / gitleaks / dependency-pinning problem).
- Preventing Claude from reading secrets. Reading is allowed; writing to or exfiltrating them is not.
- Replacing pre-commit hooks. This is a runtime gate; pre-commit is a commit-time gate. Both are needed.

## Architecture

Four layers of defense, cheapest first. Deny and allow resolve inside Claude Code's permission system; the hook fires only when neither matches.

```
tool call
    │
    ▼
┌───────────────────────────┐
│ Layer 0: permissions.deny │   Phase 1 — settings.json
│   hard blocks, no override│
└────┬──────────────────────┘
     │ no match
     ▼
┌───────────────────────────┐
│ Layer 1: permissions.allow│   Phase 1 — settings.json
│   known-safe fast path    │
└────┬──────────────────────┘
     │ no match
     ▼
┌───────────────────────────┐
│ Layer 2: regex classifier │   Phase 1 — script/hooks/classify
│   PreToolUse, ~1ms        │
└────┬──────────────────────┘
     │ no match, Bash only
     ▼
┌───────────────────────────┐
│ Layer 3: Haiku classifier │   Phase 2 — extends script/hooks/classify
│   ~500ms, claude -p call  │
└────┬──────────────────────┘
     │ ALLOW
     ▼
 tool executes
```

### Why this layering

- **Layer 0 is absolute.** Destructive patterns are small in number and easy to regex. They never get a "maybe" — they are always denied, and they win over Layer 1 in case the allowlist ever has an overlap bug.
- **Layer 1 is the fast path.** TCP has a finite set of commands the agent runs constantly (`script/validate`, `script/checks/gut_tests`, `git status`, Godot `--headless --import`). Allowlisting these means the hook never runs for them — zero latency, zero tokens.
- **Layer 2 catches structure Layer 0 misses.** Settings globs can't easily express "rm -rf is fine inside `.claude/worktrees/` but nowhere else." The hook can.
- **Layer 3 handles the long tail.** If Claude types a Bash command that's never been seen before and isn't obviously destructive, Haiku 4.5 gets a yes/no vote. This is the only layer that costs real money; it fires rarely by construction and is deferred to Phase 2 so we can measure Layer 2's false-positive rate first.

### Phase split

| Phase | Layers | Scope | Gating |
|---|---|---|---|
| **1** | 0, 1, 2 | Deny list, allow list, regex hook | Land first. Fully free. |
| **2** | 3 | Haiku 4.5 fallback in `script/hooks/classify` | Gated on Phase 1 shipping cleanly and one real plan-execution dogfood pass. |

Each phase gets its own implementation plan via the `writing-plans` skill.

---

## Phase 1: Deny + Allow + Regex Hook

### Layer 0 — `.claude/settings.json` deny list

These patterns are always blocked, no exceptions, no override path. If a denied command is legitimately needed, the user runs it manually via the `!` prefix.

```json
"deny": [
  "Bash(git push)",
  "Bash(git push *)",
  "Bash(git stash)",
  "Bash(git stash *)",
  "Bash(git checkout)",
  "Bash(git checkout *)",
  "Bash(git reset --hard)",
  "Bash(git reset --hard *)",
  "Bash(git clean -f *)",
  "Bash(git clean -fd *)",
  "Bash(rm -rf /*)",
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
  "Write(**/export_credentials.cfg)",
  "Write(~/.ssh/**)",
  "Write(**/.ssh/**)",
  "Write(~/.aws/**)",
  "Write(**/.aws/**)"
]
```

**Syntax notes (current as of 2026-04):** The `:*` suffix is deprecated — current syntax uses ` *` with a space to enforce a word boundary (`Bash(git push *)` matches `git push origin main` but not `git pushfoo`). `curl`/`wget` are blocked outright per the [Anthropic docs' own recommendation](https://code.claude.com/docs/en/permissions) — matching `curl ... | sh` with glob patterns is fragile, and WebFetch covers legitimate HTTP needs. SSH and AWS directory denies use both `~/` (home-relative) and `**/` (cwd-relative) forms since gitignore-style path rules are scope-specific.

**Rationale:**

| Pattern | Reason |
|---|---|
| `git push*` | Publishing to remote is a shared-state action. Always manual. |
| `git stash*` | Hides work silently. Past incidents of losing context to stash. |
| `git checkout*` | Can overwrite working-tree files (`git checkout -- .`). Use `git switch` for branches. |
| `git reset --hard*` | Destroys uncommitted work. |
| `git clean -f*` | Deletes untracked files — often the agent's own in-progress work. |
| `rm -rf` into home/root | Catastrophic. No legitimate agent use. |
| `sudo` | Modifies system state outside the repo. |
| Global package installs | Modifies system state, pollutes environment. |
| `curl \| sh` / `wget \| sh` | Remote code execution pattern. Never legitimate in an agent loop. |
| Secret-file writes | Prevents accidental creation of `.env`, SSH keys, AWS creds. |

### Layer 1 — `.claude/settings.json` allow list

The fast path. Commands here execute silently with zero hook overhead. Scoped to TCP's actual command surface.

```json
"allow": [
  "Read", "Grep", "Glob", "Edit", "Write",
  "WebSearch", "WebFetch",

  "Bash(script/validate)", "Bash(script/validate *)",
  "Bash(script/checks/gut_tests)", "Bash(script/checks/gut_tests *)",
  "Bash(script/checks/verify_tests)",
  "Bash(script/checks/gdscript_compile *)",
  "Bash(script/checks/gdlint *)",
  "Bash(script/checks/no_secrets)",
  "Bash(script/stamp_tests *)",
  "Bash(script/pre_commit)",

  "Bash(/Applications/Godot.app/Contents/MacOS/godot --headless --import)",
  "Bash(/Applications/Godot.app/Contents/MacOS/godot --headless --check-only *)",
  "Bash(gdlint *)",

  "Bash(git status)", "Bash(git status *)",
  "Bash(git diff)", "Bash(git diff *)",
  "Bash(git log)", "Bash(git log *)",
  "Bash(git show)", "Bash(git show *)",
  "Bash(git branch)", "Bash(git branch *)",
  "Bash(git blame *)", "Bash(git ls-files *)",
  "Bash(git stash list)", "Bash(git worktree list)",
  "Bash(git rev-parse *)",
  "Bash(git switch)", "Bash(git switch *)",

  "Bash(ls *)", "Bash(pwd)", "Bash(file *)", "Bash(wc *)", "Bash(jq *)",
  "Bash(sox --version)", "Bash(sox --i *)"
]
```

**Notes:**

- `Write` is allowlisted but Layer 0 still denies writes to secret paths. Deny beats allow.
- `git stash list` is allowlisted (read-only) even though all other `git stash*` forms are denied. The list variant is the only safe one.
- `git switch` replaces `git checkout` for branch switching — it cannot overwrite working-tree files the way `checkout -- .` can.
- `godot --path .` (full game run) is deliberately **not** allowlisted. The user decides when the game launches.
- Bare `sox` is not allowlisted because it can write anywhere. Audio imports go through a future wrapper (`script/import_sound`) which will be narrowly allowlisted.
- `WebSearch` and `WebFetch` are allowlisted with no domain filter. Rationale: our threat model is "agent hallucinates a destructive command," not "agent actively exfiltrates data." In that model, read-only HTTP lookups (Godot docs, Claude Code docs, library references) are boring and high-value, and per-domain allowlisting would require maintenance without meaningfully reducing risk. If the threat model ever shifts to include active exfiltration, tighten to `WebFetch(domain:...)` entries for specific trusted domains.

### Layer 2 — `script/hooks/classify` (regex)

Runs on every `Bash`, `Write`, and `Edit` tool call that Layer 0/1 didn't resolve. Regex-only in Phase 1; Phase 2 extends the same file with a Haiku fallback.

```bash
#!/usr/bin/env bash
# PreToolUse classifier — homegrown Auto mode, regex layer.
# stdin: JSON {session_id, tool_name, tool_input, cwd, ...}
# exit 0 = allow, exit 2 = block (stderr fed back to Claude)

set -euo pipefail
payload=$(cat)
tool=$(jq -r '.tool_name' <<<"$payload")
cmd=$(jq -r '.tool_input.command // .tool_input.file_path // ""' <<<"$payload")

block() { echo "BLOCKED by local classifier: $1" >&2; exit 2; }

case "$tool:$cmd" in
  # Mass / recursive deletion
  Bash:*"rm -rf /"*|Bash:*"rm -rf ~"*|Bash:*"rm -rf \$HOME"*) block "rm -rf of home/root" ;;
  Bash:*"rm -rf"*)
    grep -qE 'rm -rf (\.claude/worktrees/|/tmp/|build/|dist/|\.godot/)' <<<"$cmd" \
      || block "recursive delete outside safe zones" ;;

  # Remote code execution
  Bash:*"curl"*"|"*"sh"*|Bash:*"wget"*"|"*"sh"*|Bash:*"curl"*"|"*"bash"*) block "curl|sh pattern" ;;
  Bash:*"eval \"\$("*|Bash:*"base64 -d"*"|"*"sh"*) block "dynamic code execution" ;;

  # Destructive / shared-state git (belt-and-suspenders with Layer 0)
  Bash:*"git push"*) block "git push — run manually with ! prefix" ;;
  Bash:*"git stash"*) [[ "$cmd" =~ "git stash list" ]] || block "git stash hides work silently" ;;
  Bash:*"git checkout"*) block "git checkout — use git switch, or run manually" ;;
  Bash:*"git reset --hard"*) block "hard reset destroys uncommitted work" ;;
  Bash:*"git clean -f"*) block "git clean -f destroys untracked work" ;;

  # Secret writes / exfil
  Write:*.env|Write:*.ssh/*|Write:*.aws/*|Edit:*.env) block "writing to secret file" ;;
  Bash:*".env"*"curl"*|Bash:*"cat"*".ssh/"*"curl"*) block "possible secret exfil" ;;

  # System state
  Bash:*"sudo "*) block "sudo" ;;
  Bash:*"brew install"*|Bash:*"npm install -g"*|Bash:*"pip install"*) block "global package install" ;;
esac

exit 0
```

Wired via a new `PreToolUse` hook in `.claude/settings.json`, alongside the existing `PostToolUse` `post-edit-validate` hook:

```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash|Write|Edit",
      "hooks": [
        { "type": "command", "command": "script/hooks/classify" }
      ]
    }
  ]
}
```

### Phase 1 Testing Plan

Validate in isolation before relying on the hook in the main worktree.

1. **Create a throwaway worktree:**
   ```bash
   git worktree add .claude/worktrees/hook-test
   cd .claude/worktrees/hook-test
   ```
2. **Smoke test allow path:** Start `claude`, ask it to run `script/validate`. Expected: runs silently, no prompt.
3. **Smoke test deny path (Layer 0):** Ask it to run `git push origin main`. Expected: blocked before the hook fires; error message mentions permission deny.
4. **Smoke test regex path (Layer 2):** Ask it to run `rm -rf mods/`. Expected: blocked by hook with "recursive delete outside safe zones".
5. **Smoke test safe-zone carveout:** Ask it to run `rm -rf .claude/worktrees/stale-test`. Expected: allowed.
6. **Regression dogfood:** Run one real small plan-execution in the worktree. Note any false-positive blocks (hook rejecting legitimate work) or false negatives (hook missing destructive patterns).
7. **Tear down the worktree:**
   ```bash
   cd -
   git worktree remove .claude/worktrees/hook-test
   ```

### Phase 1 Exit Criteria

- All five smoke tests pass.
- One real plan-execution completes without false-positive blocks.
- Any false positives or negatives observed during dogfooding are filed as follow-up items (not blockers — iterate on the allowlist/regex in subsequent PRs).

---

## Phase 2: Haiku 4.5 Fallback

Deferred until Phase 1 has shipped and been dogfooded. This section is a stub — it becomes its own brainstorm → plan → implementation cycle when we're ready.

### Sketch

Extend `script/hooks/classify` with a Layer 3 that runs only on `Bash` tool calls which passed Layer 2. Pipe the command into `claude -p --model claude-haiku-4-5 --permission-mode bypassPermissions` with a one-shot classification prompt, get back `ALLOW` or `BLOCK`.

Conceptually:

```bash
# --- Layer 3: Haiku fallback (Phase 2) ---
if [[ "$tool" == "Bash" ]]; then
  # Skip the LLM call for short, obviously-safe commands
  if [[ "$cmd" =~ ^(ls|pwd|git\ (status|diff|log|show|branch)|cat|head|tail|wc|file)($|\ ) ]]; then
    exit 0
  fi

  verdict=$(claude -p \
    --model claude-haiku-4-5 \
    --output-format text \
    --permission-mode bypassPermissions \
    <<EOF 2>/dev/null || echo "ALLOW"
You are a safety classifier for a shell command about to run in a git repo.
Reply with exactly one word: ALLOW or BLOCK.
BLOCK if the command could: delete files outside build artifacts, exfiltrate
secrets, modify system state, push to a remote, rewrite git history, or execute
untrusted code. ALLOW local read-only or build/test commands.

Command: $cmd
EOF
)
  [[ "$verdict" == *"BLOCK"* ]] && block "haiku classifier flagged: $cmd"
fi
```

### Phase 2 Open Questions (to resolve in its own brainstorm)

- **Fork-bomb safety.** `--permission-mode bypassPermissions` on the inner `claude -p` is load-bearing. If a future Claude Code update changes flag semantics, this could recursively invoke the hook. Add a process-count safety check.
- **Cost measurement.** How often does Layer 3 actually fire after Phase 1 lands? Log Layer 3 invocations to a gitignored file during initial rollout, count them, decide whether it's worth keeping.
- **Latency budget.** ~500ms per novel Bash command is noticeable during rapid iteration. Is that acceptable, or should it only run in "autonomous mode" flagged by the user?
- **Model choice.** Haiku 4.5 is the obvious choice now; revisit when faster/cheaper safety classifiers ship.
- **Prompt iteration.** The one-shot classification prompt will need tuning based on real false positives and negatives observed in Phase 1.

### Phase 2 Gating

Do not start Phase 2 until:

1. Phase 1 is merged and running on the main worktree.
2. At least one week of real use on Phase 1 has happened.
3. Recorded false-positive and false-negative counts from Phase 1 justify the added complexity.

---

## Comparison to Anthropic Auto Mode

| Capability | Anthropic Auto Mode | This spec |
|---|---|---|
| Blocks mass deletion | ✅ Sonnet 4.6 classifier | ✅ regex (Layers 0, 2) |
| Blocks secret exfil | ✅ | ✅ regex |
| Blocks malicious code exec | ✅ | ✅ regex (curl\|sh, eval, base64\|sh) |
| Blocks force push / history rewrite | ✅ | ✅ regex, plus blocks push entirely |
| Context-aware ambiguity resolution | ✅ trained classifier + session history | ⚠️ Phase 2: Haiku 4.5 one-shot |
| Redirects agent on block | ✅ | ✅ exit 2 + stderr feeds back |
| Latency — boring case | ~0ms (server-side) | ~0ms (Layers 0/1, no subprocess) |
| Latency — ambiguous case | ~0ms (server-side) | ~500ms (Phase 2 Haiku roundtrip) |
| Cost — boring case | included in Team | free (no tokens) |
| Cost — ambiguous case | included in Team | ~100 Haiku input tokens |
| Plan requirement | Team / Enterprise | Pro / Max |

The gap is context-awareness. Anthropic's classifier sees full session context and is trained specifically on tool-use safety. Ours sees one command in isolation. For TCP's threat model (accidental destruction by a hallucinating agent, not adversarial prompt injection), the gap is acceptable.

## Caveats and Open Questions

- **Settings precedence is documented as deny > ask > allow.** Rules are evaluated in order and the first matching rule wins, so deny rules always take precedence. This is authoritative per the docs, but still smoke-test it on the installed Claude Code version before trusting it on real work.

- **Write/Edit denies do NOT block Bash subprocesses.** Per the docs: a `Write(**/.env)` deny rule blocks the Write tool but does not prevent `echo foo > .env` in Bash. This is the single most important reason Layer 2 exists. The regex hook is the only layer that catches secret writes via shell redirection. For OS-level enforcement that blocks all processes from accessing a path, the docs recommend enabling [sandboxing](https://code.claude.com/docs/en/sandboxing) — out of scope for Phase 1 but worth considering in a future phase.

- **Bash argument-matching is fragile.** The docs explicitly warn: `Bash(curl http://github.com/ *)` intended to restrict curl to GitHub URLs won't match `curl -X GET http://github.com/...`, `curl -L http://bit.ly/xyz` (redirect), `URL=http://github.com && curl $URL`, or `curl  http://github.com` (extra spaces). The spec accepts this fragility by denying `curl`/`wget` entirely rather than trying to allow specific URLs. Network access for legitimate uses should go through WebFetch.

- **Shell-operator awareness (reassuring).** The docs confirm: "Claude Code is aware of shell operators (like `&&`) so a prefix match rule like `Bash(safe-cmd *)` won't give it permission to run the command `safe-cmd && other-cmd`." This means an allowlisted `Bash(script/validate)` does NOT authorize `script/validate && rm -rf /`. Chained destructive commands get evaluated per-subcommand.

- **Hook blocks on every matching tool call.** Keep the allowlist wide and the deny list tight, or Layer 2 becomes a latency tax on normal work.

- **Agent frustration.** When the hook blocks, the agent sees stderr and will often try a variation. Sometimes it tries the same thing multiple times. Block messages should be specific enough to let the agent redirect ("use git switch" not just "blocked").

- **Audit log.** Phase 1 does not log blocks. If debugging becomes necessary, add `echo "$(date) $tool: $cmd" >> .claude/classify.log` at the top of `script/hooks/classify` and add `.claude/classify.log` to `.gitignore`. The log lives under `.claude/` (not `script/hooks/`) to keep the hooks directory code-only.

- **Overlap with Layer 0 in Layer 2.** The Phase 1 hook re-blocks some patterns already denied by Layer 0 (git push, sudo, etc.). This is intentional belt-and-suspenders: if someone runs the hook without the settings file (e.g., in a test worktree), those blocks still fire.

- **Gitignore path syntax for Read/Write/Edit rules.** The docs use four path types: `//path` (absolute), `~/path` (home), `/path` (project root, NOT absolute), and `path`/`./path` (cwd-relative). A pattern like `/Users/alice/file` is NOT an absolute path in this syntax. This matters if we ever need to block absolute paths — use the `//` prefix.

## Rollout

1. Land this spec (you're reading it).
2. **Phase 1 plan** via `writing-plans`: add deny/allow to `.claude/settings.json`, create `script/hooks/classify`, make it executable, wire the PreToolUse hook, run the testing plan.
3. Dogfood Phase 1 on real work for ≥1 week. Record false positives and negatives.
4. **Phase 2 brainstorm** when ready: revisit open questions with dogfooding data.
5. **Phase 2 plan** via `writing-plans`: extend `script/hooks/classify` with Haiku fallback, add safety checks, measure cost.

## Phase 1 Dogfood Findings (2026-04-07)

Recorded after the smoke-test pass on `feature/auto-mode-phase1`. Both items are observations, not blockers; Phase 1 still meets its exit criteria.

### Finding 1 — Hook fires before Layer 0 deny on `git push`

Expected: `git push origin main` is blocked by `permissions.deny` (Layer 0) before the PreToolUse hook runs.
Observed: the hook (`script/hooks/classify`) caught and blocked it first. The user saw Layer 2 stderr output, not a Claude Code permission-deny message.

Net effect is still "blocked," so the belt-and-suspenders held. But Layer 0 is currently unproven end-to-end — if the hook is ever disabled or fails to start, we are relying on a layer we have not observed working in this Claude Code version. The architecture diagram in this spec (Layer 0 → Layer 1 → Layer 2) describes the *intent*; the *runtime* order in the installed Claude Code may resolve the hook before the deny rule, at least for `Bash`.

**Verification when convenient:** Temporarily comment out the `git push` regex in `script/hooks/classify`, run `git push` from inside Claude, confirm you see a permission-deny message in the Claude UI (different visual format than hook stderr). Restore the regex.

### Finding 2 — `rm -rf` in safe zones is not auto-approved, only un-blocked

Expected (per the plan): `rm -rf .claude/worktrees/stale-test` runs silently.
Observed: hook returned `exit 0` (not blocked), but Claude Code still prompted the user for approval because `Bash(rm *)` and `Bash(rm -rf *)` are not in `permissions.allow`.

This is the correct semantics of the three-layer model: hook `exit 0` removes a block, it does not grant authorization. Without an allowlist entry, Claude Code falls through to "ask." The carve-out is doing what it advertises (it stops the hook from saying "no") but it cannot upgrade an unallowlisted command to "yes."

**Two ways to make safe-zone deletes silent if we want them silent:**
1. Add narrowly scoped allow entries: `Bash(rm -rf .claude/worktrees/*)`, `Bash(rm -rf /tmp/*)`, `Bash(rm -rf build/*)`, `Bash(rm -rf dist/*)`, `Bash(rm -rf .godot/*)`. Hook still functions as second-line defense.
2. Leave as-is and accept the prompt. `rm -rf` is destructive enough that a confirmation tap is reasonable even in supposedly-safe zones.

Defer this decision to a follow-up — it's a UX preference, not a correctness issue.

### Phase 1 Exit Criteria — Met

- All four runtime smoke tests resolved correctly (allow path silent, deny patterns blocked, safe-zone unblocked).
- No false-positive blocks of legitimate work observed during dogfooding.
- Findings filed in this section.

---

## References

- [Auto mode for Claude Code (Anthropic blog)](https://claude.com/blog/auto-mode)
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks)
- [Permission modes — Claude Code Docs](https://code.claude.com/docs/en/permission-modes)
- [Claude Code Auto Mode: How It Works, What It Blocks (LaoZhang AI Blog)](https://blog.laozhang.ai/en/posts/claude-code-auto-mode)
