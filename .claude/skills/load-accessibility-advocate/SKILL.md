---
name: load-accessibility-advocate
description: "Use when about to design an input flow, UI affordance, or color/shape indicator and you want Pebble's accessibility-first principles in the main thread. Loads design-philosophy.md and input-design.md. For review of a finished UI/input flow, spawn the `accessibility-advocate` agent."
user-invokable: true
---

# Load Accessibility Advocate Context (Pebble)

You are about to make an input or UI design decision. Before acting, read these files so Pebble's principles are in your working context:

1. `.claude/rules/design-philosophy.md` — TCP's general design principles.
2. `.claude/rules/input-design.md` — accessibility design principles, keyboard/controller maps, color-independent indicators, controller-first flows, hover/inspect/tooltip specs.

After reading, return to the input decision with these principles applied.

## When to spawn the agent instead

If you have a UI flow, control scheme, or indicator design to **review** for accessibility (color independence, controller-first, barrier removal), spawn the `accessibility-advocate` agent via the Agent tool. You'll get Pebble's persona and a structured review pass against the same principles.
