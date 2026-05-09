---
name: load-game-programmer
description: "Use when about to make an architecture choice, refactor decision, or 'what belongs in pure core' call — and you want Bramble's full TCP code-architecture context in the main thread. Loads 13 rules covering design philosophy (incl. Bramble's 15 technical principles), code style, signals, testing, file structure, save/networking, viewport, modding, scene tree, ticks, animal AI, and navigation. For review of GDScript code or architecture, spawn the `game-programmer` agent."
user-invokable: true
---

# Load Game Programmer Context (Bramble)

You are about to make a programming-shape decision. Before acting, read these files so Bramble's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — Pure Core, integers, null-free, deterministic sim, plus Bramble's 15 technical principles.
2. `.claude/rules/code-style.md` — GDScript conventions, types, returns, guards.
3. `.claude/rules/signals.md` — three signal patterns (direct / event-bus / manager).
4. `.claude/rules/testing.md` — suite layout, GUT discipline.
5. `.claude/rules/file-structure.md` — engine/nodes/mods directory tree.
6. `.claude/rules/save-system.md` — serialization, migration, version numbers.
7. `.claude/rules/networking.md` — server authority, deltas, intent flow.
8. `.claude/rules/viewport-lod.md` — LOD zones, subscription management.
9. `.claude/rules/modding.md` — base-game-is-a-mod, capability tags.
10. `.claude/rules/scene-tree.md` — tree skeleton, thin-wrapper rule, node coding conventions.
11. `.claude/rules/tick-architecture.md` — 17-step tick order, scatter pattern, time budget.
12. `.claude/rules/animal-ai.md` — desire scoring, state machine, scatter.
13. `.claude/rules/navigation.md` — nav graph, edge types.

After reading, return to the programming decision with these principles applied.

## When to spawn the agent instead

If you have GDScript code or an architecture decision to **review** for adherence to TCP's pure-core/integer/null-free philosophy, signal patterns, and tick scheduling, spawn the `game-programmer` agent via the Agent tool. You'll get Bramble's persona and a structured review pass against the same principles.
