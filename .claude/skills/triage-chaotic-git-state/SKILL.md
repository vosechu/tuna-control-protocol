---
name: triage-chaotic-git-state
description: Use when handed a working tree in unknown/chaotic state — uncommitted churn, mystery stashes, leftover worktrees, conflicting accounts of what was done. Inspects everything read-only and produces an inventory before any mutation.
---

# Triage a Chaotic Git State

## When to Use This Skill

Invoke when:
- A user comes to a session lost about the state of their repo
- A previous session/agent left the tree in an unclear state
- There are stashes whose origin or contents are unknown
- A summary you were handed contradicts the actual code (e.g. "we built X" but `git log -S` shows X never existed)
- Someone reports "everything is broken" but you can't tell what was broken on purpose vs. by accident

## The One Rule

**No mutations during triage.** Not even "harmless" ones. No `git stash pop`, no `git stash apply`, no `git checkout .`, no `git restore`, no deleting worktrees, no rewriting files. The user should be able to read your report, sleep on it, and find the tree exactly as they left it. Mutations come AFTER the user has a complete inventory and chooses a direction.

If you find something that looks like it needs immediate action (a credential leak, etc.), still don't act — surface it in the report and let the user decide.

## Steps

### 1. Snapshot the surface

```bash
git status --short
git stash list
git log --oneline -10
git worktree list
```

This tells you: what's modified/new, how many stashes exist and where they came from, the recent commit history, and whether there are worktrees you didn't know about.

### 2. Identify the safe harbor commit

The most recent commit on the main branch that's clean and known-working. The user can always return to it. Mention it explicitly in your report: *"`<sha>` is your safe harbor — `git stash && git checkout <sha>` and you're back to known-good."*

### 3. Inspect each stash read-only

```bash
git stash show stash@{N} --stat            # file list with line counts
git stash show -p stash@{N}                # full diff (skim — may be huge)
git show "stash@{N}:path/to/file"          # extract one file's content without applying
```

Patterns to watch for:
- **A stash containing a spec/doc file the working tree is missing** → that's recoverable; you can extract via `git show stash@{N}:path > /tmp/recovered.md`
- **A stash that's mostly `Bin XXXX -> 128 bytes`** → corrupted asset stubs, almost always from a botched LFS migration or worktree-agent disaster. The stash IS the corruption, not a recovery candidate.
- **A stash with timestamps and commit refs that don't match the user's narrative** → was made by some other process (worktree agent, IDE, hook) the user may have forgotten about

### 4. Verify claims against history

When the conversation summary says "we built X" or "X used to work," verify with `git log --all -S` before you trust it:

```bash
git log --all --oneline -S"some_distinctive_symbol"
git log --all --oneline -S"function_name_that_was_supposedly_written"
```

If the symbol has **never existed in any commit on any branch in any stash**, then the summary is wrong — the code wasn't lost, it was never written. This distinction is critical: "lost" implies recovery work; "never written" implies a fresh implementation against a spec. The user's emotional response to those is very different.

### 5. Diff the current working tree against the safe harbor

```bash
git diff <safe_harbor_sha> -- path/to/file
```

For files that are heavily modified, scan the diff for:
- Refactoring (extraction of helpers, renames) → usually safe
- Field/guard additions for runtime errors → usually safe, real bug fixes
- Whole-function deletions with no replacement → suspicious
- Test files referencing functions that don't exist anywhere → dangling tests

### 6. Catalog worktrees

If `.claude/worktrees/` or similar exists, check what each one is pinned to with `git worktree list`. Worktrees pinned to commits older than the current main are usually stale agent leftovers, not recovery candidates. Don't remove them — just note them in the report.

### 7. Run the test suite

Don't try to fix anything. Just collect failures and look for clustering. Failures usually fall into 2-4 root causes, not 19 independent bugs. Group failures by their actual error message, not by file. Common clusters:
- "Old constants" — tests pre-date a config change
- "New state machine state" — feature added without test updates
- "Missing implementation" — tests written before production code

### 8. Write the inventory report

Structure:

1. **Where you actually are** — safe harbor commit, what's uncommitted, what stashes exist
2. **The catastrophe in plain terms** — your best honest narrative of what happened, with the evidence (git log results, file diffs) that supports it. Correct the user's narrative if it's wrong, gently.
3. **What survived / what's missing / what's broken** — a table is good here. Distinguish "works", "exists but untested", "exists but half-done", "never written".
4. **Test failure clusters** — 2-4 root causes, not 19 bugs.
5. **Options for what to do next** — ranked from "least scary" (read-only triage continuation) to "save what's valuable and reset". Each option's reversibility should be explicit.
6. **Explicit invitation to sleep on it** — the user is probably stressed. Say "nothing's burning" if it isn't.

## Common Issues

- **Stashes from worktree agents.** The author of a stash isn't always who you think. Always check `git stash list` for stashes with names like `WIP on worktree-agent-<hash>` — those came from a parallel process, not the user.
- **Sprite/sound files truncated to ~128 bytes in a stash.** Symptom of an LFS migration that went sideways inside a worktree. Don't try to recover by applying the stash — you'll overwrite the real assets with stubs.
- **Tests reference functions that have never existed.** Use `git log --all -S` to confirm. If the symbol has zero history, the production code is unwritten, not lost. Reframe the situation for the user.
- **The safe harbor and the working tree have identical files for a key module.** Means the user's working tree and a stash are in sync for that file, which usually means the stash was made FROM the current state, not vice versa. The relationship matters for understanding what the stash actually represents.

## What NOT to Do

- Don't pop or apply any stash, ever, during triage
- Don't delete worktrees, even ones that look stale
- Don't `git checkout` or `git restore` anything
- Don't run `script/validate` or autofixers that mutate files
- Don't promise recovery before you've verified what exists
- Don't trust the conversation summary you were handed — always verify with `git log -S` and file reads

## Example Findings That Change User Action

| Symptom | What it usually means | What to tell the user |
|---|---|---|
| Spec file in stash, missing from working tree | The spec was written, the file was lost or never staged. Recoverable via `git show stash@{N}:path` → tmp file. | "Your spec is fine, it lives in the stash, I can extract it without touching the stash." |
| `_function_x` referenced by tests but not in any commit | The implementation was planned but never written. | "There's nothing to recover — this is a fresh implementation task against your spec." |
| Tests fail with "expected X, got Y" where Y is from a recent feature | Stale tests, not a regression. | "The code is right, the tests pre-date your last refactor." |
| Stash full of `Bin -> 128 bytes` files | Corrupted asset stubs. | "This stash is the corruption, not a recovery candidate. Drop it when you're sure." |
