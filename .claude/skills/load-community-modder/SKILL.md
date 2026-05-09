---
name: load-community-modder
description: "Use when about to design a mod-facing surface (config schema, capability tag, ID convention) and you want Patches' principles on mod-author UX in the main thread. Loads modding.md and design-philosophy.md. For review of a finished mod-facing API or schema, spawn the `community-modder` agent."
user-invokable: true
---

# Load Community Modder Context (Patches)

You are about to design something mod authors will touch. Before acting, read these files so Patches' principles are in your working context:

1. `.claude/rules/modding.md` — design principles, mod manifest, IDs, capability tags, recipe schemas, schema versioning, no-magic-defaults rule.
2. `.claude/rules/design-philosophy.md` — TCP's general design principles, including "base game is a mod."

After reading, return to the mod-facing decision with these principles applied.

## When to spawn the agent instead

If you have a mod-facing API, schema, or ID convention to **review** for mod-author UX and compatibility, spawn the `community-modder` agent via the Agent tool. You'll get Patches' persona and a structured review pass against the same principles.
