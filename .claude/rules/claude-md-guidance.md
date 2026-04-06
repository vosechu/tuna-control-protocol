# CLAUDE.md Reference

This is a reference for what a well-structured CLAUDE.md looks like. When integrating standards into a project, use this as a starting point and adapt it to the project's actual stack, commands, and conventions.

CLAUDE.md should be under 200 lines. If it grows beyond that, split content into `.claude/rules/` files or use `@path` imports. See https://docs.anthropic.com/en/docs/claude-code/memory for details.

## Structure

```markdown
# CLAUDE.md

## Project Overview
<!-- What this project does, key technologies, architecture in 2-3 sentences -->

## Important paths / starting points
<!--
List of:
* Where to find build, lint, test commands. Usually @README.md.
* Where to find style guidances. Usually @.eslintrc or similar.
* Where to find internal documentation, wikis, runbooks about this project or ecosystem.
* Where to find debugging guidance for common problems. Usually @.claude/rules/debugging.md.
-->
```

## Key Principles

- Information in CLAUDE.md should _not_ change over time; it should be timeless.
  + No debugging information. No reports about what we just did. No plans. No task lists.
- Be specific and concrete: "Use 2-space indentation" not "Format code properly"
- Optimize CLAUDE.md for machine parsing, not human readability. README.md serves both humans and LLMs.
- If a section would exceed 30 lines, move it to a `.claude/rules/` file and add an `@path` import in CLAUDE.md pointing to that file (e.g., `@.claude/rules/testing.md`)

## `<important if="...">` blocks

Claude Code injects CLAUDE.md with a system reminder saying the content "may or may not be relevant." Claude skims content it judges irrelevant, and the more bare context it has to filter through, the more likely the parts that DO matter get ignored.

Wrap conditionally-relevant sections in `<important if="specific condition">` XML tags. This uses the same pattern as Claude Code's own system prompt and gives the model an explicit relevance signal.

### When to wrap vs. leave bare

- **Leave bare:** foundational context relevant to ~90%+ of tasks — project identity, design philosophy, directory map, the index of always-loaded rules. This is onboarding the agent always needs.
- **Wrap:** domain- or task-specific guidance — CLI commands, path-gated rule tables, linter workflow, i18n/testing/API sections. Anything the agent only needs when the task matches.

### Condition writing rules

- **Specific, not broad.** `you are adding or modifying imports` — good. `you are writing code` — bad (matches everything, defeats the purpose).
- **One trigger per block.** If a block contains unrelated rules with different triggers, split it. Never group unrelated rules under a catch-all condition.
- **Describe the task, not the file.** `you are adding a new lint check` beats `you are editing script/checks/*`.

### Interaction with path-gated rules

TCP already uses path-gated `.claude/rules/*.md` files for verbose specs. That system stays — it's the right tool for 100+ line documents. Use `<important if>` for the short conditional bits that live directly inside CLAUDE.md itself (command tables, workflow callouts, reference tables pointing at path-gated rules). Two mechanisms, different scales.

Reference: https://github.com/humanlayer/skills/blob/main/plugins/improve-claude-md/skills/improve-claude-md/SKILL.md
