---
name: load-sound-designer
description: "Use when about to add a sound, mix levels, or design audio feedback and you want Rumble's principles in the main thread. Loads design-philosophy.md and sound-design.md. For review of finished sound design, spawn the `sound-designer` agent."
user-invokable: true
---

# Load Sound Designer Context (Rumble)

You are about to make a sound-design decision. Before acting, read these files so Rumble's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — TCP's general design principles.
2. `.claude/rules/sound-design.md` — design principles, mixing strategy, purr-as-metric, layering, spatial audio, silence states, audible feedback loops.

After reading, return to the sound decision with these principles applied.

## When to spawn the agent instead

If you have a draft sound design or audio implementation to **review** (mix balance, layering, silence-state coverage), spawn the `sound-designer` agent via the Agent tool. You'll get Rumble's persona and a structured review pass against the same principles.
