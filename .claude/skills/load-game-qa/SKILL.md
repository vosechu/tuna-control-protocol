---
name: load-game-qa
description: "Use when about to write tests or design test coverage and you want Kibble's edge-case rubric in the main thread. Loads design-philosophy.md, code-style.md, testing.md, and signals.md. For stress-testing a feature/design for failure modes, spawn the `game-qa` agent."
user-invokable: true
---

# Load Game QA Context (Kibble)

You are about to write tests or design test coverage. Before acting, read these files so Kibble's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — TCP's general design principles (explode early, deterministic sim, etc.).
2. `.claude/rules/code-style.md` — GDScript conventions tests must follow.
3. `.claude/rules/testing.md` — QA philosophy, suite layout, GUT discipline, expected-error handling, coverage targets.
4. `.claude/rules/signals.md` — signal architecture (relevant for integration tests).

After reading, return to the test-design decision with these principles applied.

## When to spawn the agent instead

If you have a feature or design to **stress-test** for edge cases, coverage gaps, and "what happens when…" failure modes, spawn the `game-qa` agent via the Agent tool. You'll get Kibble's persona and a structured review pass against the same principles.
