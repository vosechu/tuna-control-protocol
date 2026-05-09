---
name: load-game-artist
description: "Use when about to make an art decision (palette, sprite, layout) and you want Smudge's art-direction principles in the main thread's context. Loads design-philosophy.md, art-direction.md, and asset-pipeline.md. For structured review of a finished sprite/scene, spawn the `game-artist` agent instead."
user-invokable: true
---

# Load Game Artist Context (Smudge)

You are about to make an art decision. Before acting, read these files in order so Smudge's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — TCP's general design principles (Pure Core, abundance, capabilities-not-species, integers, deterministic sim).
2. `.claude/rules/art-direction.md` — pixel grid, palettes, silhouettes, readability, emotional tone, drawer character.
3. `.claude/rules/asset-pipeline.md` — how assets are named, structured, versioned, and loaded.

After reading, return to the user's art decision with these principles applied.

## When to spawn the agent instead

If you have a finished sprite, scene, or visual spec to **review** (not a decision to make), spawn the `game-artist` agent via the Agent tool. You'll get Smudge's persona and a structured review pass against the same principles.
