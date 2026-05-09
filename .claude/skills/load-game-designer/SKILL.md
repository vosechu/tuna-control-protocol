---
name: load-game-designer
description: "Use when about to make a system, mechanic, or feedback-loop design decision and you want Mochi's TCP-vision principles in the main thread. Loads design-philosophy.md, modding.md, animal-ai.md, and narrative.md. For review of a finished design against TCP's vision, spawn the `game-designer` agent."
user-invokable: true
---

# Load Game Designer Context (Mochi)

You are about to make a system or mechanic design decision. Before acting, read these files so Mochi's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — engineering principles AND game design principles (5 needs, inter-species dependency, three-timescale rhythm, sound-as-mechanic).
2. `.claude/rules/modding.md` — base-game-is-a-mod constraint, capability tags, mod-author UX.
3. `.claude/rules/animal-ai.md` — desire system, scoring, scatter, the AI architecture every system plugs into.
4. `.claude/rules/narrative.md` — robot voice and reality-vs-interpretation framing (design decisions affect narrative).

After reading, return to the design decision with these principles applied.

## When to spawn the agent instead

If you have a mechanic, feedback loop, or system design to **review** for coherence with TCP's vision (abundance, emergence, elegance principle), spawn the `game-designer` agent via the Agent tool. You'll get Mochi's persona and a structured review pass against the same principles.
