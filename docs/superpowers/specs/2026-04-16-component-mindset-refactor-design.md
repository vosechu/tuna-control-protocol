# Component-Mindset Refactor — Design

> **Status:** design draft, 2026-04-16 (rev 2 after dev-team review). Supersedes species-dispatch patterns in animal-ai.md (`species_filter`) and concrete code sites across `engine/`, `nodes/`, and mod recipes. Not yet planned or implemented.

---

## Anchor rule

**Systems check capabilities, not species.**

A "capability" is a component on an entity — either a zero-data tag (`&"purrs"`) or a component with a payload (`&"purrs": {rate: 10, radius: 4}`). Species (`&"tcp_cats:cat"`, `&"tcp_ferrets:ferret"`) remain as **labels** used for save data, UI display, and narrator events. No code path selects behavior by reading the species label.

**Granularity policy: hybrid, start narrow.** First system that needs a capability defines a narrow tag (e.g. `tends_servers: true`). When a second system needs the same check, promote to a broader name used by both. Vocabulary grows from observed duplication, not speculation.

**Capability namespace:** capability tags are **bare `StringName`** keys (no `tcp_base:` prefix), matching the desire-channel convention from `2026-04-10-mod-extraction-design.md`. The first two mods using a shared capability name are in an implicit contract; promoting a capability from narrow to broad is a **breaking change** that must be documented in release notes the same way a desire-channel rename would be.

**One sentence for future Claude sessions:** if you're about to write `if species == "cat"`, stop and add a component to the recipe instead.

---

## Motivation

Audit of the codebase, rules, CLAUDE.md, agents, memories, and plans found ~35 sites (after dev-team review expanded the initial estimate) where behavior branches on species name or species-coded identifiers leak out of the data layer. Three categories:

1. **Functional dispatches** — code picks different behavior by checking species strings. Breaks when a third species is added.
2. **Cosmetic species names** — field/class/function names embed "cat" or "purring" even when logic is already generic. Misleads future work.
3. **Doc drift** — rules, CLAUDE.md, and superseded plans frame species as *types* (classes with unique needs) rather than *recipes of components*. Future Claude sessions inherit the drift.

The refactor is staged so the game is shippable at every checkpoint.

---

## Stage 1 — Functional dispatch fixes

Stop the game from breaking when a third species is added. Surgical code changes, no renames.

### 1.1 Sprite + animation dispatch
**File:** `nodes/animal_node.gd` (lines 11–23, 32, 53, 63, 71, 90)
**Problem:** `String(species[&"id"]).contains("cat")` selects sprite paths, Y-offsets, and animation frame counts. Also, `_STATE_TO_ANIM: Dictionary` at lines 11–23 hardcodes the mapping from game state to animation name (e.g. `MOVING_TO → walk`, `SEEKING → walk`, `WANDERING → walk`).

**Fix:** species recipe declares a `sprite_config` component with two fields:

```jsonc
"sprite_config": {
  "base_path": "res://mods/tcp_cats/sprites/{variant}",
  "offset_y": 0,
  "animations": {
    // n:1 state→animation: multiple states can name the same animation key
    "IDLE":       { "animation": "idle"  },
    "SEEKING":    { "animation": "walk"  },
    "MOVING_TO":  { "animation": "walk"  },
    "WANDERING":  { "animation": "walk"  },
    "GROOMING":   { "animation": "crouch"},
    "SLEEPING":   { "animation": "sleep" }
  },
  "animation_frames": {
    // per animation key: file suffix, frame count, fps
    "idle":   { "sprite": "_idle_strip8.png",   "frames": 8, "fps": 6.0 },
    "walk":   { "sprite": "_walk_strip8.png",   "frames": 8, "fps": 8.0 },
    "crouch": { "sprite": "_crouch_strip8.png", "frames": 8, "fps": 6.0 },
    "sleep":  { "sprite": "_sleep_strip4.png",  "frames": 4, "fps": 3.0 }
  }
}
```

Two maps handle the n:1 case cleanly: `animations` maps state → animation key; `animation_frames` maps animation key → sprite + frames + fps.

**`{variant}` substitution:** performed by `animal_node.gd` at sprite-load time. The implementation replaces the literal substring `{variant}` in `base_path` with the spawned entity's variant name (e.g. `mochi`, `biscuit`). If a species has no variants, the recipe should use a literal path with no placeholder. Final sprite path is `base_path + animation_frames[key].sprite` (relative concat). Variant string must not contain path separators.

Both the `is_cat` check and the `_STATE_TO_ANIM` dict are deleted. `_is_ferret` flag is deleted; Y-offset comes from `sprite_config.offset_y`.

### 1.2 Ambient state weights
**File:** `nodes/game_server.gd` (lines 425–475)
**Problem:** `has_cat_states` (derived from whether the `"grooming"` state exists on the species) selects between two hardcoded weight tables — one for cats, one for ferrets.
**Fix:** species recipe declares:

```jsonc
"ambient_states": {
  "warm": [
    { "state": "GROOMING", "weight": 15 },
    { "state": "LOAFING",  "weight": 20 },
    { "state": "SLEEPING", "weight": 25 }
  ],
  "cold": [
    { "state": "GROOMING", "weight": 5 },
    { "state": "LOAFING",  "weight": 10 }
  ]
}
```

`_pick_ambient_state` becomes a generic weighted pick over whichever array the species provides. The `get_states(species_id).has("grooming")` gate is deleted.

### 1.3 Navigation default species
**File:** `engine/navigation/nav_graph_builder.gd` (lines 32, 109, plus `add_floor_node` and callers)
**Problems:**
- Line 32: default param `species_id: StringName = &"tcp_cats:cat"` bakes cats in as "the default species."
- Line 109: `_astars.get(&"tcp_cats:cat", null)` for floor-node lookup, even though the comment says floors are species-agnostic.

**Fix:**
- Remove the default param. Callers pass `species_id` explicitly.
- Store floor-node positions on the builder itself (not inside a per-species AStar instance). This requires refactoring `add_floor_node` and each caller to thread the builder-owned map instead of reaching into a per-species astar. `get_nearest_floor_node` reads the builder-owned map. Count: ~5 callsites.

### 1.4 HUD color dispatch
**File:** `nodes/animal_stats_bar.gd`
**Problem:** name color picked by `contains("cat")` vs. else-branch.
**Fix:** species recipe declares `hud_color: [r, g, b]`. Stats bar reads it. If a recipe omits `hud_color` (mod author error), load-time schema validation (see Stage 1.10) rejects the recipe rather than fallback-colouring.

### 1.5 Curiosity tracker initialization
**File:** `nodes/game_server.gd` (lines 678–708, inside the `tcp_ferrets:ferret` branch)
**Problem:** the curiosity-tracker init call sits inside a species-scoped block. A third species declaring `curiosity` in its desires won't get a tracker.
**Fix:** hoist the tracker-init loop out of species branches. Iterate all spawned entities post-spawn; initialize curiosity tracker for any whose `desires` component declares a `curiosity` channel. Must land **before** 1.6 (or simultaneously), because 1.6 merges the `stimulation` verbs into `curiosity` and the tracker loop has to see the consolidated channel.

### 1.6 Schema bug: `stimulation` desire
**Files:** `mods/tcp_cats/species/cat.jsonc` (lines 63–67), `mods/tcp_ferrets/species/ferret.jsonc` (line 46)
**Problem:** both recipes reference `stimulation` in verb `desire_affinities` but neither declares it in their `desires` block. Silent schema mismatch.
**Fix (chosen option B):** change the verbs to target `curiosity` (already declared in both recipes). Merge `stimulation` into `curiosity`.

> **Future axis (not a regret):** `curiosity` (novelty-seeking: SNIFFING, exploration) and `stimulation` (active play: batting, chase, war-dance) are conceptually distinct channels that conflate today because TCP has no play-object mechanics yet. When toys/play verbs land, expect to re-split them. The merge is *forward-compatible*: we can introduce `stimulation` later as a new desire channel and re-target verbs, without this refactor having baked anything irreversibly.

### 1.7 Cat-presence query functional fix
**File:** `engine/growth/cat_presence_system.gd` (lines 35–42)
**Problem:** `_any_cat_nearby` queries `get_entities_with(&"species")` — returning every animal — and then treats every returned entity as a "cat." This is functionally wrong **today** (ferrets already falsely register as presence), not just a cosmetic name issue.
**Fix (before rename):** add `tends_servers: true` to `mods/tcp_cats/species/cat.jsonc`. Change the query to `_db.get_entities_with(&"tends_servers")`. The rename to `ReclamationSystem` / `tended_seconds` still happens in Stage 2.1; Stage 1 just corrects the query so reclamation counts only cats (and any future species with `tends_servers` declared).

### 1.8 Client-side register-cat dispatch
**File:** `nodes/game_client.gd` (lines 262–272)
**Problem:** `register_cat` uses `String(species[&"id"]).contains("cat")` to decide how to hook up client-side UI.
**Fix:** identify what the register-cat call actually provides (stat bar wiring? purr audio wiring?) and replace the check with the capability that describes it. If it's purr audio, use the presence of `sounds.purr` in the recipe. If it's stat-bar wiring, use the presence of `desires`. Determine the right check at implementation time and call it out in the commit message.

### 1.9 Hardcoded starter-entity spawn list
**File:** `nodes/game_server.gd` (lines 640–702, `_spawn_starter_entities`)
**Problem:** the starter-spawn function hardcodes `tcp_cats:cat` and `tcp_ferrets:ferret` with inline name lists. A third species mod cannot spawn starter entities without code changes — violates Stage 1's "zero engine changes" success criterion.
**Fix:** move starter-spawn configuration into each species mod's recipe as an optional `starters` field:

```jsonc
"starters": [
  { "name": "Mochi",   "variant": "tabby"   },
  { "name": "Biscuit", "variant": "calico"  },
  { "name": "Noodle",  "variant": "siamese" }
]
```

`_spawn_starter_entities` iterates all loaded species definitions; for each, if `starters` is present and non-empty, spawn one entity per entry. Any species recipe omitting `starters` (or providing an empty array) contributes nothing at startup. No hardcoded species ID references remain in the function.

### 1.10 Schema validation for recipe fields
**Problem:** Stage 1 makes `sprite_config`, `ambient_states`, `hud_color`, and `desires` mandatory for a species recipe to spawn a working animal. A mod author copying an old template or omitting a field gets silent crashes at render/pathfind/HUD time.
**Fix:** add a schema-validation step to the mod loader. When a species recipe is loaded, assert presence of the mandatory fields. Missing fields push an error via `push_error()` and the mod is rejected (not partially loaded). Validation rules live next to `entity_def_registry.gd` and the failure mode is discoverable at load time, not at spawn time.

Mandatory fields for a species recipe after Stage 1:
- `desires`: Dictionary
- `sprite_config`: Dictionary with `base_path`, `animations`, `animation_frames`
- `ambient_states`: Dictionary with `warm` and `cold` arrays
- `hud_color`: `[r, g, b]` array
- `traversal`: Array of traversal capability names

Optional fields: `starters`, `personality_ranges`, `verbs`, `states`, `tends_servers`, any other narrow capability tag.

### 1.11 Commit discipline inside Stage 1
Each Stage 1 sub-item's commit **must** update every species recipe in `mods/tcp_*/species/` in the same commit, not just engine code. Otherwise landing 1.1 without updating `ferret.jsonc` boots the game but crashes ferrets the first time they animate. This overrides the general "one commit per fix" principle: a recipe-field-adding commit is a coordinated change across engine + all mods.

### Stage 1 success criteria
- **Test fixture:** `tests/integration/test_third_species_spawns.gd` loads a minimal synthetic species recipe from `tests/fixtures/tcp_test_species/` and asserts spawn → animate → pathfind. This test is the mechanical verification of the anchor claim. Add in Stage 1.
- Adding a real third species mod (`tcp_rabbits/` or similar) produces a spawned, animated, navigating animal with zero changes to `engine/` or `nodes/` code. (Equivalent to the test fixture passing.)
- Schema validation rejects a species recipe missing any mandatory field (push_error, mod skipped).
- All existing tests green.
- Save format compatible: no existing save file-format changes in Stage 1 because no save system exists yet (see Cross-cutting).

---

## Stage 2 — Capability-naming renames

Primarily a rename pass, driven by the anchor rule: *names describe the mechanic, not the species that happens to use it today.* Two small logic changes come along for the ride (2.1 and 2.4) because a rename that still leaves the query over-scoped would defeat the point — these are called out explicitly below. The `tends_servers` capability and its query were already introduced in Stage 1.7; Stage 2.1 just renames the component/class/field that consumes it.

### 2.1 Concept rename: `cat_presence` → `reclamation`

The component tracking "this server has been tended long enough for plants to grow" is currently named `cat_presence`, which is wrong on two counts: it counts any animal's proximity (partially fixed in 1.7 via `tends_servers`), and its *purpose* is reclamation/plant-growth, not cat detection. Rename the whole concept.

| Old | New |
|---|---|
| `cat_presence` component | `reclamation` component |
| `&"cat_seconds"` field | `&"tended_seconds"` field |
| `CatPresenceSystem` class / `cat_presence_system.gd` | `ReclamationSystem` class / `reclamation_system.gd` |
| `_any_cat_nearby` function | `_any_tender_nearby` function |

### 2.2 Contentment signal rename

The signal currently called "purring" is actually "3-of-4 contentment bars met." Purring is the cat-specific *audio expression* of being satisfied; the underlying gameplay signal is species-agnostic.

| Old | New | Location |
|---|---|---|
| `&"is_purring"` field in `contentment` component | `&"is_satisfied"` | `engine/core/contentment.gd` + all consumers |
| `_purring_count` | `_satisfied_count` | `engine/core/contentment.gd` |
| `get_purring_count()` | `get_satisfied_count()` | `engine/core/contentment.gd` |
| `CHARGE_PER_PURRING_CAT` | `CHARGE_PER_SATISFIED_ENTITY` | `engine/core/hum_system.gd:6` |
| `purring_near_receiver` | `satisfied_near_receiver` | `engine/core/hum_system.gd:63` |

The *audio* of purring (playing the purr sound) stays "purring" — it's a species-specific sound effect tied to the cat's sound component. The *gameplay signal* becomes species-neutral.

### 2.3 Narrator event renames

**File:** `engine/core/narrator.gd` (lines 50, 74, 94)

| Old | New |
|---|---|
| `&"first_cat_settles"` | `&"first_creature_settles"` |
| `&"cat_departed"` | `&"creature_departed"` |
| `&"cat_returned"` | `&"creature_returned"` |

Event payloads still include the species label for the narrator to say "Mochi has returned" — that's display data, not dispatch.

> **Mod-API note:** event-bus names are a cross-mod contract. Renaming `first_cat_settles` → `first_creature_settles` breaks any mod listener keyed to the old name (none exist today, but the door is open per `2026-04-10-mod-extraction-design.md`). Document the rename in release notes for the refactor branch.

### 2.4 Event signal renames

**File:** `nodes/events.gd` (lines 22, 25)

| Old | New |
|---|---|
| `cat_started_pacing` | `creature_started_pacing` |
| `cat_petted` | `creature_petted` |

Same mod-API note applies.

### 2.5 Component query cleanups

Even after Stage 1 fixes, one query still over-scopes:

- `engine/core/contentment.gd:17`: `_db.get_entities_with(&"species")` — change to `_db.get_entities_with(&"desires")` so the loop only considers entities that actually have desires to evaluate contentment over. Verify no non-animal entity (e.g., rack, placed object) declares `desires` today; if one does, add a secondary filter on `contentment` presence.

(`plant_growth_system.gd`'s `&"cat_seconds"` read becomes `&"tended_seconds"` automatically via 2.1.)

### Stage 2 success criteria
- `grep -rn "purring" engine/ nodes/ --include="*.gd"` returns zero matches in logic identifiers. String literals in logs/comments that describe the audio effect are allowed.
- `grep -rn "cat_" engine/ nodes/ --include="*.gd" | grep -v "tcp_cats:cat"` returns zero function, variable, or constant names. (Grep narrowed to engine/nodes to avoid `mods/tcp_cats/` path false-positives; the `tcp_cats:cat` exclusion preserves legitimate string-literal references to the species label.)
- `CatPresenceSystem` does not exist as a symbol anywhere in the repo.
- All tests green.
- Per `.claude/rules/llm-test-verification.md`: renames change test bodies. Every test whose body referenced the renamed identifier must re-run the full Phase 2–5 verification cycle. Full re-verification scope is ~10–12 test files (test_contentment, test_hum_system, test_hum_tick, test_plant_growth_system, test_cat_presence_system, test_plant_comfort_advertisement, test_tick_loop, test_narrator, plus any test file with `cat_`/`purring` identifier matches). **Land Stage 2 on a single branch with all re-verifications complete before merging; do not drip-feed per rename**, or `verify_tests` breaks CI for anyone mid-stream.

---

## Stage 3 — Documentation, memory, and agent purge

Text-only stage. No code. Goal: a fresh Claude session opening any of these files cannot drift back into species-thinking.

### 3.1 CLAUDE.md
- Add a new top-level section titled **"Species Are Component Recipes"** stating the anchor rule and the capability-namespace rule from the top of this spec.
- Rewrite the `## Animal Types & Roles` section title to `## Species Recipes`. Reframe bullets from "cats need warmth" → "the cat recipe includes high warmth weighting, the purr capability, ...". Keep all the content (warmth/comfort/food/purr for cats; chaos/hiding/drag for ferrets); change the framing.
- Keep the Sandi Metz quote at line 14 **verbatim**. Add an ECS gloss as a follow-on sentence, not a replacement. Target text:
  > Sandi Metz: *"If you put a ClumsyHuman object in the same space as a CatWithLongTail object and wait, things are going to happen."* In TCP this works because ClumsyHuman and CatWithLongTail are *recipes of components*, not classes in a hierarchy — emergence comes from components sharing space.

### 3.2 `.claude/rules/animal-ai.md`
- **Delete** `species_filter` from the `ObjectAdvertisement` class reference, the scoring code example (lines 55–69), and the config example (line 78). `species_filter` was never implemented in code — it only lives in docs and the schema — and contradicts memory `feedback_no_species_filter_on_ads.md`.
- Rewrite comments that frame scoring logic through "a cat" (lines 150–152) to "an entity with X component."

### 3.3 `.claude/rules/navigation.md`
- Rewrite the edge type table (lines 14–26). Replace "JUMP_UP — cats only" with "JUMP_UP — entities whose `traversal` array includes `JUMP_UP`."
- Rewrite the species capability JSON example (lines 22–23) to use neutral placeholder names (`species_a`, `species_b`) rather than `cat`, `ferret`. Add a note below it: *"The JSON groups capabilities under species for readability, but the pathfinder checks the `traversal` array on the entity's species definition, not the species name."*

### 3.4 `.claude/rules/core-loop.md`
- Line 26 comment "most cats stop purring" → "most purring entities stop producing output."

### 3.5 `.claude/rules/art-direction.md`
- Line 101–103 "species-shape coding" → "component-driven shape coding — species recipes declare silhouette shape via a `visual` component."

### 3.6 `schemas/object_definition.jsonc`
- Remove `species_filter` field definition from the schema. Advertisements broadcast to everyone; desire weights do the filtering.

### 3.7 Old specs and plans in `docs/superpowers/`

Specs and plans are historical record — their content should not be rewritten. The only permitted edit is prepending a superseded-notice banner so readers know to cross-reference this refactor. Apply to any spec or plan that references `species_filter`, `cat_presence`, `cat_seconds`, or `is_purring`. Minimum list (expand by grepping `docs/superpowers/` before implementation):

- `2026-04-04-ferret-ring0-behavior-design.md` (`species_filter`)
- `2026-04-05-animal-resting-on-design.md` (`species_filter`)
- `2026-04-12-purr-power-ring0-design.md` (`is_purring`)
- `2026-04-12-purr-power-foundation.md` (`is_purring`, `cat_seconds`)
- `2026-04-12-purr-power-feedback-presentation.md` (`is_purring`)
- `2026-04-12-purr-power-objects-food-loop.md` (possible refs; verify)

Banner text:
```
> **Note (2026-04-16):** Identifiers referenced in this document may be superseded by
> `2026-04-16-component-mindset-refactor-design.md`. `species_filter` was never
> implemented in code and is removed from the schema. `cat_presence` → `reclamation`,
> `cat_seconds` → `tended_seconds`, `is_purring` → `is_satisfied` per Stage 2 renames.
```

### 3.8 Agents in `.claude/agents/`

Audit the design-team agents (Mochi, Bramble, Patches) for species-dispatch framing in their prompts. Add a line to each:
> *Treat species as recipes of components. Never design around "what cats do vs. what ferrets do"; design around "what this capability does, regardless of which recipes currently include it."*

**Do not** modify the player-persona agents (Luna, Noodle, Willow, Sage, Button, Whisker, Blueprint, Clover). They are roleplay personas; real players think in species, and that's fine.

### 3.9 Memories (`~/.claude/projects/.../memory/`)

- **New memory:** `feedback_capability_not_species.md` — captures the anchor rule, the capability-namespace rule (bare, breaking-change to promote), and the `curiosity` / `stimulation` future-axis note. Type: `feedback`. Reason field: this spec. How to apply: whenever writing or reviewing code that branches on animal behavior.
- Review `project_ferret_behavior.md` and similar project memories for language that implies ferret-specific code paths. Reframe as "curiosity-driven patrol (which ferrets currently use because their recipe heavily weights curiosity)" instead of "ferret curiosity patrol." Do not delete; rephrase.
- Leave `feedback_no_species_filter_on_ads.md` as-is — already aligned.
- Update `MEMORY.md` index entry for the new memory.

### 3.10 Mod documentation updates

Stage 1 adds mandatory recipe fields (`sprite_config`, `ambient_states`, `hud_color`, `traversal`, `desires`). Without documentation, modders copy `cat.jsonc` as a de-facto schema and hit silent failures. Required updates:

- **`.claude/rules/modding.md`:** add a "Species Recipe Schema" section listing mandatory and optional fields after Stage 1, with references to `mods/tcp_cats/species/cat.jsonc` as the canonical example.
- **`schemas/species_definition.jsonc`** (new file, mirroring `schemas/object_definition.jsonc`): formal JSON-Schema definition of the species recipe shape including the new components. Loaded by the validator introduced in Stage 1.10.
- **`mods/tcp_cats/species/cat.jsonc`:** ensure it's completely filled in (all mandatory fields present, correct format) so it serves as the canonical template.
- Cross-reference `2026-04-10-mod-extraction-design.md` in `modding.md` for the inter-mod contract rules.

### 3.11 Linter check (regression prevention)

Add a check to `script/checks/` that catches regressions:

- **Check name:** `no_species_dispatch`
- **Pattern:** flag any `String(.*species.*).contains\("cat"\)` or `String(.*species.*).contains\("ferret"\)` patterns, and any hardcoded `&"tcp_cats:cat"` / `&"tcp_ferrets:ferret"` in `engine/` or `nodes/` files (excluding string-literal contexts that route save-data or UI display text).
- **Exemptions:** files in `tests/`, string literals inside logs or narrator events, the species-label field itself.
- **Enforcement:** runs in `script/validate` and the pre-commit hook, same as `no_secrets` and `gdscript_compile`.

Add this check as part of Stage 3 (docs stage) so the regression guard lands after the code cleanup is complete.

### 3.12 Optional designer convention: `role_tags`

Recipes may include an optional `role_tags` array — a designer-facing summary of the capabilities the recipe provides:

```jsonc
"role_tags": ["tender", "purrer", "climber", "vocal"]
```

Not enforced by the engine. Exists so a designer reading a recipe can see at a glance what the animal *does* without having to mentally dereference every tag-with-payload. Promoted to mandatory if future design conventions require it; optional for Stage 3.

### Stage 3 success criteria
- `grep -rn "cats only\|ferrets only\|species_filter" .claude/ CLAUDE.md docs/ schemas/` returns only matches that are (a) inside files in `docs/superpowers/` where the Stage 3.7 banner marks them as superseded, or (b) `feedback_no_species_filter_on_ads.md` which documents the decision against species_filter.
- `grep -rn "cat_presence\|is_purring\|cat_seconds" .claude/ CLAUDE.md` returns zero matches.
- `script/checks/no_species_dispatch` runs green against the post-Stage-2 codebase.
- A new Claude session asked "how do I make the cat do X?" reframes the question to "what capability should the entity have to do X?"

---

## Cross-cutting concerns

### Commit discipline
One commit per fix, **except** Stage 1 sub-items that add mandatory recipe fields — those commits must update engine + all species recipe files atomically. Stage boundaries are commit-worthy checkpoints: Stage 1 must ship (tests green, game bootable, third-species fixture test passes) before Stage 2 starts. Same for Stage 2 → Stage 3. Stage 2 is landed as a single branch (see Stage 2 success criteria) because per-rename commits would break `verify_tests` CI for other branches.

### Test stamp re-verification
Stage 2 renames change test bodies. Per `.claude/rules/llm-test-verification.md`, every modified test requires full Phase 2–5 re-verification (write → red → green → mutate → red → restore → green → refactor → review → QA → re-stamp). The cosmetic-exception re-stamp path is **not** applicable — these are semantic field/identifier changes, and test assertions reference the renamed symbols. Scope: ~10–12 test files.

### Save compatibility (deferred)
**The save system does not exist yet.** There is no `engine/save/`, no writer/reader/migrator, and no `tests/snapshots/saves/` directory. `save-system.md` is pure design. The Stage 2 rename affects what the save system *will eventually* need to migrate, but nothing ships in this refactor that writes or reads saves.

**Action:** when the save system is implemented (future work), it must include migration functions for:
- `cat_seconds` → `tended_seconds`
- `is_purring` → `is_satisfied`
- any other field renamed in Stage 2

Capture this as a deferred concern in `save-system.md` once that work is scoped. For this refactor, the save-compat checkbox is informational, not blocking.

### What this spec is **not**
- Not an ECS architecture rewrite — we already have one.
- Not a ban on the `species` component; the species label stays for saves, UI, narrator.
- Not a ban on the words "cat" / "ferret" in prose, narrator text, mod names, or content files. Only in code branching.
- Not a scope expansion into rendering-layer component-ification beyond what Stage 1 requires — further rendering refactors (e.g. declaring z-order as a component) are possible follow-ups but out of scope.

---

## Open questions

- **`curiosity` / `stimulation` split.** Currently merged (Stage 1.6). A known future axis tied to adding play/toy/chase mechanics, reversible when that design work lands. Documented so we don't forget.

---

## Related rules and specs

- `.claude/rules/design-philosophy.md` — spawn templates, component lifecycle, the component architecture this refactor operationalizes.
- `.claude/rules/animal-ai.md` — edited by Stage 3.2 to remove `species_filter`.
- `.claude/rules/modding.md` — expanded by Stage 3.10 with the species-recipe schema section.
- `.claude/rules/llm-test-verification.md` — governs the re-stamp discipline required for Stage 2 renames.
- `docs/superpowers/specs/2026-04-04-ferret-ring0-behavior-design.md` — gets a superseded banner in Stage 3.7.
- `docs/superpowers/specs/2026-04-05-animal-resting-on-design.md` — gets a superseded banner in Stage 3.7.
- `docs/superpowers/specs/2026-04-10-mod-extraction-design.md` — source of the bare-StringName capability-namespace convention.
- `docs/superpowers/plans/2026-04-12-purr-power-*.md` — get superseded banners in Stage 3.7.
- Memory `feedback_no_species_filter_on_ads.md` — the original decision this spec operationalizes.
- Memory `feedback_capability_not_species.md` (new, Stage 3.9) — durable carrier of the anchor rule for future Claude sessions.
