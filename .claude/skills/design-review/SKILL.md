---
name: design-review
description: "Review a design section or feature for completeness, consistency, implementability, and alignment with TCP's vision. Run before implementing anything."
argument-hint: "[section-name or 'prototype' or 'all']"
user-invokable: true
---

When this skill is invoked:

## 1. Read Context

- Read `CLAUDE.md` for design philosophy and constraints.
- Read `.claude/rules/` for software architecture rules and reference implementations.
- Read `PLANNING.md` in full — this is TCP's primary design document.
- If a specific section is named, focus on that section but cross-reference others.

## 2. Evaluate Against TCP's Design Checklist

For each feature or mechanic being reviewed, check:

### Completeness (8 points)
- [ ] **What the player does** — Verbs are defined (place, arrange, observe, etc.)
- [ ] **What the animals do** — Desires, behaviors, and responses are specified
- [ ] **How it looks** — Visual states, animations, or at least visual requirements noted
- [ ] **How it sounds** — Audio signatures defined (sound IS a mechanic in TCP)
- [ ] **How the robot interprets it** — Datacenter-lingo narration specified
- [ ] **What the numbers are** — All formula values identified (even if "TBD, goes in config")
- [ ] **Edge cases** — What happens at 0, at 1, at 1000? What if the player does nothing?
- [ ] **Accessibility** — Every channel has a backup (sound→visual, color→shape)

### Consistency (5 checks)
- [ ] **Abundance, not scarcity** — Does this mechanic punish or enable? If it constrains, does it feel like "which wonderful option?" not deprivation?
- [ ] **Nothing is cosmetic** — Does every element serve a mechanical purpose?
- [ ] **Desire-driven, not scripted** — Do animals act from their own desires, or is this a scripted sequence? (Scripted sequences are permitted only for first-time discovery events via the `proximity_event` system.)
- [ ] **Cross-system interactions** — Does this mechanic interact with at least one other mechanic? (Elegance Principle: few mechanics, many interactions.)
- [ ] **No contradictions** — Does this conflict with anything in PLANNING.md or CLAUDE.md?

### Implementability (5 checks)
- [ ] **Pure Core compatible** — Can the logic live in RefCounted classes? Or does it require Node/scene-tree access?
- [ ] **Integer-representable** — Can all values use int with scale factors? Any forced floats?
- [ ] **Deterministic** — Given the same seed, will this produce the same result? Any randomness that isn't seeded?
- [ ] **Testable** — Can you write a unit test for this without a scene tree? What would the test assert?
- [ ] **Moddable** — Are the tunable values in config? Could a modder add a variant of this via JSON alone?

### Scale (3 checks)
- [ ] **At 10 animals** — Does this work?
- [ ] **At 1000 animals** — Does this still work? What's the computational cost?
- [ ] **In multiplayer** — What state needs syncing? What's client-only?

## 3. Cross-Reference Other Design Sections

Check whether this feature's design is consistent with related sections:
- Does the desire system section agree with how this feature uses desires?
- Does the prototype resource matrix include this feature's objects?
- Does the interaction web account for this feature's dynamics?
- If this feature has inter-species effects, are both species' sections consistent?

## 4. Output the Review

```markdown
## Design Review: [Feature/Section Name]

### Completeness: [X/8]
[List missing items with specific questions to resolve them]

### Consistency: [X/5]
[List any violations with the specific principle violated]

### Implementability: [X/5]
[List concerns with specific technical questions]

### Scale: [X/3]
[List scale concerns]

### Cross-Reference Issues
[List any contradictions or gaps between this section and other design sections]

### The Anecdote Test
Can a player tell a story about this feature? What would it sound like?
If not: what's missing that would make it story-worthy?

### Recommendations
[Prioritized list — what must be resolved before implementation vs. what can be figured out during prototyping]

### Verdict: READY TO BUILD / NEEDS DETAIL / NEEDS RETHINK
- **Ready to Build:** All critical checks pass. Open questions are minor and can be resolved during implementation.
- **Needs Detail:** Core design is sound but missing specifics a programmer needs. List what's missing.
- **Needs Rethink:** Fundamental issue — violates a design principle, contradicts another system, or isn't implementable as described.
```

## Rules

- This is a read-only review. Don't rewrite the design — flag issues for the designer to resolve.
- Be specific. "This section is vague" is useless. "This section doesn't specify what happens when a ferret drags a tuna can but no robot arm is placed yet" is actionable.
- Always check against TCP's specific philosophy: abundance over scarcity, desire-driven emergence, no punishment, sound as mechanic, robot narrator, vegan.
- The Anecdote Test (Kate Compton) is mandatory: if this feature can't produce a player story, it needs work.
- "TBD" in a design doc is acceptable for Ring 1+ features but NOT for prototype features.
