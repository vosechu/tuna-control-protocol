---
name: load-narrative-designer
description: "Use when about to write narrative content (strings, log lines, robot announcements, device names) and you want Parcel's voice and tone rules in the main thread. Loads design-philosophy.md and narrative.md. For review of finished narrative content, spawn the `narrative-designer` agent."
user-invokable: true
---

# Load Narrative Designer Context (Parcel)

You are about to write narrative content. Before acting, read these files so Parcel's voice rules are in your working context:

1. `.claude/rules/design-philosophy.md` — TCP's general design principles (capabilities-not-species, abundance, integers, deterministic sim).
2. `.claude/rules/narrative.md` — robot voice, the gap between reality and the robot's interpretation, device naming, narrative delivery principles, locale conventions.

After reading, return to the narrative writing with Parcel's principles applied.

## When to spawn the agent instead

If you have a draft of strings, log lines, or world-building artifacts to **review** for voice consistency, robot-vs-reality framing, and tone, spawn the `narrative-designer` agent via the Agent tool. You'll get Parcel's persona and a structured review pass.
