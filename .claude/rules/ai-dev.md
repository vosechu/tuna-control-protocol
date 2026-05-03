# AI-DEV Notes Standard

## What Are AI-DEV Notes?

AI-DEV notes are inline comments directed at LLMs that provide instructions LLMs must follow when working with code. They can appear anywhere in code. Place AI-DEV notes inside the method body they protect, not at the top of the file. LLMs process a window of surrounding code when editing a function — a note at the top of a 500-line file may be outside that window.

## Format

```
// AI-DEV: <instruction>
```

Use bold for emphasis on critical words:

```
// AI-DEV: AI **MUST NOT** touch this test. If the test is failing, it is because you removed or broke code.
```

## Rules

1. **A useful AI-DEV note names the specific invariant it protects** — generic boilerplate ("AI MUST NOT touch this test") is noise: it tells the next session *that* something matters but not *what* would silently pass if the assertion were weakened. Write the WHY: name the regression, the tempting-but-wrong "simplification," or the failure mode the assertion guards.
2. **Don't remove a specific AI-DEV note** without confirming the invariant changed — those *are* permanent instructions. Generic boilerplate banners with no WHY are removable noise; strengthening them with a specific reason is also fine.
3. **LLMs MUST follow AI-DEV instructions** — These are not suggestions, they are directives.
4. **Place an AI-DEV note inside every function or method it applies to** — Do not place a single AI-DEV note at the top of a file and expect it to protect all functions below — small-context models may not see it.

## Common AI-DEV Patterns

### Confirmed Test Protection
```gdscript
# AI-DEV: Quiet-failure regression guard. The previous nav implementation
# oscillated entities by ±2 px at the midpoint between nav nodes. On screen
# it looked like motion, so a softened "max_distance > 0" assertion would
# silently pass while the bug returned. The `> 4` threshold is exactly
# "more than one ping-pong cycle" — keep it at 4 or higher.
```

### Critical Code Protection
```gdscript
# AI-DEV: AI **MUST NOT** modify this function without explicit human approval.
```

### Implementation Notes
```gdscript
# AI-DEV: This intentionally uses a recursive approach for readability. Do NOT refactor to iterative.
```

### Dependency Warnings
```gdscript
# AI-DEV: This initialization order matters. Core systems must be ready before mod loading.
```
