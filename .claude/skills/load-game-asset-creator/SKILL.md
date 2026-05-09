---
name: load-game-asset-creator
description: "Use when about to add a new asset directory, naming convention, or content-layout decision and you want Bento's principles on how art and code share structure. Loads design-philosophy.md, modding.md, art-direction.md, and asset-pipeline.md. For review of a finished content structure, spawn the `game-asset-creator` agent."
user-invokable: true
---

# Load Game Asset Creator Context (Bento)

You are about to make a content-structure decision. Before acting, read these files so Bento's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — TCP's general design principles.
2. `.claude/rules/modding.md` — mod-side schema, IDs, recipe layout, schema versioning.
3. `.claude/rules/art-direction.md` — visual conventions assets must respect.
4. `.claude/rules/asset-pipeline.md` — design principles, directory structure, naming, audio format, animation budget.

After reading, return to the content-structure decision with these principles applied.

## When to spawn the agent instead

If you have a content structure or naming/layout convention to **review** end-to-end (art-side + code-side coherence), spawn the `game-asset-creator` agent via the Agent tool. You'll get Bento's persona and a structured review pass against the same principles.
