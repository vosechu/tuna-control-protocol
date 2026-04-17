# Tuna Control Protocol (TCP) — Datacenter Animal Habitat Simulator

A cozy, abundance-driven game about raising thousands of animals in an abandoned datacenter. Players build interconnected infrastructure, animals arrive and thrive, and the game is about maximizing collective happiness. There is no lose condition. The challenge is finding the theoretical maximum — which is hard because animals have complex, interacting desires and emergent teaching behaviors.

**The ultimate goal: feel buried in fluffy joy and thousands of kittens.**

---

## Core Design Philosophy

- **Abundance over scarcity:** No starvation, no resource depletion, no "you failed because you didn't plan correctly." Treats are always available. Heat always flows. Water always condenses. Negative feedback should feel like "I have so many wonderful options, which one?" not deprivation.
- **No adversarial relationships:** The player's goal and the animals' goals are the same thing. The challenge is purely: can you understand what they need well enough to provide it at scale?
- **Gnorp Apologue model:** No lose condition, but a hard-to-find theoretical maximum. Numbers always go up. The question is "how fast?" not "am I gaining or losing?" Player role shifts from doing to orchestrating as the ecosystem grows.
- **Emergence through desire:** Give animals desires, put them in proximity, and watch. As Sandi Metz said: "If you put a ClumsyHuman object in the same space as a CatWithLongTail object and wait, things are going to happen." In TCP this looks more like an entity that has Human and Clumsy components, and a Cat entity with a LongTail component. This works because ClumsyHuman and CatWithLongTail are *recipes of components*, not classes in a hierarchy — emergence comes from components sharing space.
- **The Elegance Principle** (Tynan Sylvester): The best designs create the most varied dynamics from the fewest mechanics. 3 mechanics that interact in 20 ways > 20 mechanics that don't interact.
- **Kitten chaos as feature:** Kittens unplug things, tangle cables, and cause mischief — not because they're malicious, but because they're exploring. This is manageable reality, not a problem to eliminate.
- **Vegan game:** No eating mice. Super AI mega-crops handle nutrition (but still need work to taste right). Crunchy cricket cakes, seared tuna (from cans ordered by ferrets), chef cats kneading dough.
- **By the end:** Cats in every nook and cranny, organizing groups, tackling problems, and generally just being lovely purry cats.

---

## Species Are Component Recipes

Systems check capabilities, not species. A "capability" is a component on an
entity — either a zero-data tag (`&"tends_servers"`) or a component with a
payload (`&"sprite_config": {...}`). Species labels (`&"tcp_cats:cat"`) remain
only for save data, UI display, and narrator events. No code path selects
behavior by reading the species label. If you are about to write
`if species == "cat"`, stop and add a component to the recipe instead.

**Capability namespace:** capability tags are bare `StringName` keys (no
`tcp_base:` prefix), matching the desire-channel convention. Promoting a
capability from narrow to broad is a breaking change for mod authors —
document it in release notes.

---

## Design Frameworks

**MDA** (Hunicke/LeBlanc/Zubek): Design mechanics → produce dynamics → create target aesthetics. TCP's target aesthetics: **Discovery** (finding what animals need), **Expression** (building your habitat your way), **Submission** (meditative flow of tending creatures), **Sensation** (cuteness overload).

**Verb palette** (Anthropy/Clark): TCP's verbs define its feel: **place, arrange, observe, collect, nurture, customize**. No "defend," "survive," "fight."

**The Lens of the Toy** (Schell): Is watching animals interact with datacenter infrastructure fun *before it's a game*? If yes, everything else is amplification.

**Machinations** (Dormans): Model game economies as resource flows. TCP needs many positive feedback loops (abundance) with gentle negative feedback (interesting decisions, not punishment).

**Iterative Rings:** Ring 0 = core loop fun? Ring 1 = + progression. Ring 2 = + variety. Ring 3 = + meta + polish. Each ring evaluated independently before building the next.

---

## Backstory

After the AI bubble collapsed, hundreds of AI datacenters were abandoned and fell silent. The towns that grew up to service the datacenters gradually became ghost towns and nature began to come back. But cats, originally drawn to the datacenters by the warmth, were the first to repopulate. As time drew on, plants and mosses began to grow, and other animals began to return. Food, water, and shelter are taken care of, so the community focuses on raising their young instead of eating each other.

**The robot arm** doesn't know they're cats. It thinks they're weird servers and it's doing its best. Purring = IOPS. Treat consumption = packets/sec. It's a caretaker — these servers are weird and squishy, but the goal is the same: make sure they're happy and healthy. Comedy comes from the gap between reality (adorable animals) and the robot's interpretation (server diagnostics).

---

## Animal Desire System

**Maslow's hierarchy + individual traits.** Basic needs (warmth, food, water, shelter) are universal and easy to meet. Higher-order desires (novelty, companionship, stimulation, teaching, exploration) are individually weighted — you can't optimize for "cats" as a category.

**Teaching mechanics:** Vertical transmission (adult to young) and horizontal transmission (peer to peer, in-group to out-group). Individual animals have specialties; teaching grants some of that knowledge. A chef cat teaches kittens to "make biscuits" (knead dough). TBD whether this makes the cut vs. simpler emergence.

**Happiness metric:** The robot tracks an internal "happiness meter" interpreted through datacenter lingo (IOPS, packet throughput, disk health). The specific metric presentation is flexible — what matters is animals are thriving.

---

## Species Recipes

Animals arrive when conditions are right (Terry Pratchett logic: get enough tubes in one room and a ferret is bound to come out of one). Each species recipe has unique component weights and tags that contribute something enabling other recipes.

- **The cat recipe** includes high warmth and comfort desire weights, the `tends_servers` tag (produces IOPS via purring), and companionship desire. Kitten variants add the `causes_chaos` tag.
- **The ferret recipe** includes high stimulation and hiding desire weights, the `can_hack_ordering` tag (unlocks tuna delivery), and curiosity-seeking locomotion components. Unlocks access to new areas.
- **The dog recipe** includes the `body_heat_large` tag (warm to sleep next to), high strength for moving heavy objects, and `community_stabilizer` behavior weights. Not a guardian (no adversaries) — a community builder.
- **Guinea pigs, rabbits, birds, others:** TBD. Each recipe should have unique component weights and unique contribution tags.

**Inter-recipe dependencies:** Without the `can_hack_ordering` component from ferrets, cats can't have tuna. Without fur balls for ferrets to hide, you can't attract ferrets. Diversity of recipes enables scaling.

---

## Infrastructure & Conveyance

Nothing is purely cosmetic. Everything serves a purpose, even if discovered through emergence.

- **Gerbil/hamster tubes:** Conveyance for small animals. 100% functional.
- **Bridges/ledges:** For medium-sized jumping animals.
- **Gates/doors:** For larger, smarter animals.
- **Skill tower:** Not just a cat tower — cat tower with gerbil runs, vent tubes, hammocks, little houses. Animals placed on nodes unlock capabilities. Visible but grayed out until unlocked. Spans a whole wall, over a window, around the couch, through the bookshelf.

---

## Multiplayer

- Solo, Multiplayer (5-rack stripes, invite friends), Collaborative (3-rack stripes, work together)
- Wandering adult cats migrate between player racks (cosmetic, mildly in the way)
- Heat/treats can spill into neighbor racks (advantageous, not griefing)
- Communication via emoji (vague, multi-lingual)
- State synced every 1min or on close; game doesn't run in background
- 2 weeks inactive = replaced, everyone shifts left (longest-active players in first slots)

---

## Sound Design

Sound is a core mechanic, not decoration. Purring IS the success metric made audible.

- Aggregate purr level = audible IOPS. Close your eyes and know how your datacenter is doing.
- Animal vocalizations teach the player what animals need before any stat bar does.
- The robot has a voice: servo whirs, scanning beeps, confused double-beeps, satisfied hums.
- A full datacenter hums with warm, layered harmony. Silence = sadness. Volume = abundance.

---

## Observability & Stats

Outstanding design question: How much observability do we give players? Stats graphs? FACET by server? By cat? Heatmaps of contention? This is a core design lever for helping players understand what animals need at scale.

---

## Technical Fundamentals

- Networking from day one (starting a game implicitly starts a server)
- Plan for controller support (don't implement yet, but don't design things controllers can't do)
- Plan for i18n (use i18n primitives for all visible strings)
- Separate assets from behavior; separate config from assets (every formula number in overridable JSON)
- Species as data, not code (new animal = new JSON definition, not new script)
- Save gamestate debuggably with clear version numbers
- URI scheme: `tuna://<path>` for everything (savegame sharing, in-game addressing)
  - Local: `tuna://.../rack/01/unit/12`
  - Global: 3 cattish words (256-word dict) + 6 base32 chars = 18e15 combos
- Accessibility by default: every channel has a backup (sound → visual, color → shape), controller-first interaction design, no time pressure

---

## The Team (AI Agents)

Design collaboration uses specialized agents in `.claude/agents/`:

**Dev Team (opus):** Mochi (Designer), Bento (Assets), Smudge (Art), Rumble (Sound), Parcel (Narrative), Kibble (QA), Bramble (Programmer), Pebble (Accessibility), Patches (Community/Modding)

**Players (sonnet):** Luna (Collector), Noodle (Optimizer), Willow (Nurturer), Blueprint (Architect), Sage (Casual), Clover (Social), Button (Controller), Whisker (Mouse/KB)

---

## Software Rules

Rules live in `.claude/rules/` as auto-loadable files.

### Always loaded (code & architecture)

| Rule file | Covers |
|---|---|
| `design-philosophy.md` | Pure Core, Redux state, integers, null, determinism, config-not-code, change detection, spawn templates, lifecycle hooks, relationships, GameStateDB reference |
| `code-style.md` | Types, naming, returns, null handling, signals, comments, code examples |
| `testing.md` | GUT, test suites, CI pipeline, coverage targets, test exemplars |
| `signals.md` | Three signal patterns, event bus, ownership, UI pattern, scenario traces |
| `file-structure.md` | Full `res://` directory tree |
| `save-system.md` | GameStateDB, MessagePack format, save payload, versioning, sharing, migrator reference |
| `networking.md` | Client-server protocol, deltas, bandwidth, interest management |
| `viewport-lod.md` | Subscription zones, billboard rendering, tier model |
| `modding.md` | Auto-detection, three-lane ordering, ID derivation, observable state reference |
| `scene-tree.md` | Scene tree skeleton, animal scene, key ownership |
| `tick-architecture.md` | 10 Hz sim tick, staggered eval, rendering interpolation, key numbers |
| `animal-ai.md` | State machine, hysteresis, object advertisements, scoring loop |
| `navigation.md` | AStar2D point graph, node/edge types, species capabilities, dynamic updates |
| `secrets.md` | What never gets committed, where secrets go, .gitignore policy |
| `ai-dev.md` | AI-DEV inline comment markers — permanent LLM instructions in code |
| `llm-test-verification.md` | Red-green-refactor verification, test protection, post-hoc review |
| `naming-conventions.md` | Verb vocabulary, boolean prefixes, A/HC/LC structure, opposites |
| `pr-review-checklist.md` | Review roles, security/testing/quality checklists, failure thinking |
| `test-philosophy.md` | Sandi Metz test matrix, unit vs integration philosophy |

### Loaded by path (design specs)

| Rule file | Loads when touching | Covers |
|---|---|---|
| `art-direction.md` | `**/*.png`, `**/*.tscn`, `sprites/**` | Pixel grid, palettes, cat models, zoom levels, lighting, z-order, robot arm visual |
| `asset-pipeline.md` | `mods/tcp_base/**`, `**/*.png`, `**/*.ogg` | Directory structure, naming, sprite/sound lists, animation frame budgets |
| `input-design.md` | `nodes/**`, `**/*.tscn`, `config/input/**` | Keyboard shortcuts, controller flow, inspect panel, tooltips, color-independent indicators |
| `narrative.md` | `mods/tcp_base/**`, `**/*.json`, `**/locale/**` | Robot arc, animals leaving/returning, reclamation aesthetic, device naming, robot logs |
| `sound-design.md` | `**/*.ogg`, `mods/tcp_base/sounds/**`, `mods/tcp_base/config/**` | Mixing strategy, purr variation, silence states, player feedback sounds, spatial audio |

Read `.claude/rules/` before writing any code.

## Linter Rules

Checks live in `script/checks/` as standalone scripts. Two entry points:

- `script/validate` — runs all checks on the entire project (use anytime, CI)
- `script/pre_commit` — runs checks on staged files only (symlink to `.git/hooks/pre-commit`)

GDScript style is enforced by `.gdlintrc`. When adding a new rule:

1. If it can be checked mechanically (naming, patterns, structural constraints) — add a check to `script/checks/`. Each check takes file args or defaults to scanning everything.
2. If it requires judgment (architecture, design patterns, testing strategy) — add it to the relevant `.claude/rules/*.md` file.
3. Never put the same rule in both places. Linters enforce; rules guide.

Notable checks: `gdscript_compile` (catches parse errors via `--import`), `gdlint`, `gut_tests` (unit + scene + integration + scenario), `no_secrets` (gitleaks).

**Claude Code hook:** `.claude/settings.json` has a PostToolUse hook that runs `script/hooks/post-edit-validate` after Write/Edit on game files (`.gd`, `.json`, `.tscn`, etc.). This catches compilation errors and lint issues immediately.

---

## Grid & Viewport

Internal viewport: **224×128** (14×8 tiles). Layout constants in `engine/core/constants.gd`, visual details in `.claude/rules/art-direction.md`. Key fact: `FLOOR_Y = 112`, animals walk at this Y in X only. Camera controlled by `camera_controller.gd`.

### Coordinate system — use canonical helpers

Two coordinate spaces: **PU** (position units, `POSITION_SCALE=100`, used by GameStateDB/AI/physics) and **world pixels** (used for rendering/input). Never do ad-hoc math with rack/slot offsets — always use the helpers in `constants.gd`:

- `rack_slot_to_pu(bay, rack, slot) -> Vector2i` — canonical PU position (X at rack center)
- `pu_to_bay_rack_slot(pu_x, pu_y) -> Dictionary` — inverse
- `rack_slot_to_world(bay, rack, slot) -> Vector2` — world pixels for sprite rendering
- `world_to_rack_slot(world_x, world_y, bay) -> Dictionary` — click position to rack/slot
- `world_to_pu(world_x, world_y) -> Vector2i` — click position to PU (accounts for RACK_SLOT0_Y offset)
- `to_world(pu) -> float` / `from_world(w) -> int` — scalar conversion only

`RACK_SLOT0_Y` accounts for the rack sprite's 8px transparent padding + 4px visible frame = 12px offset from `RACK_TOP_Y`. Dividing PU X by `RACK_WIDTH_PU` is wrong (it omits `LEFTMOST_RACK_OFFSET_PU` and uses width instead of stride). Always use the helpers.

### Tilemap layout (tcp_environment tileset)

8 tile rows: ceiling, walls (1-5), baseboard (6), floor (7). Floor tiles use a two-layer theme:

- Row 7 `_WALL_LAYER`: substrate `(7,5)` — always
- Row 7 `_PLANT_LAYER`: opaque row-3 grass variant — 15% of tiles
- Row 6 `_PLANT_LAYER`: edge cap — `(7,4)` bare (85%) or `(4,4)` small plants (15%, paired with grass)

The row-6 edge cap's 16 black pixels (y=15 in tile) render at world y=111 — the horizontal black line at the top of the floor. Pairing ensures themes are consistent: bare-edge above bare-substrate, or plants-edge above grass-surface.

### GDScript warnings

- `integer_division` is disabled project-wide in `project.godot`. Do not add per-line `@warning_ignore("integer_division")`.
- Godot 4.6's CLI does **not** emit editor parse warnings (unused_variable, shadowed_variable, etc.) via `--import`, `--check-only`, or any other flag. These warnings exist only in the editor GUI. `gdscript_compile` surfaces all non-boot output so real errors are caught, but editor-only warnings stay editor-only.

---

## Godot CLI

Godot binary: `/Applications/Godot.app/Contents/MacOS/godot`

Common commands:
```bash
# Import/reimport all project resources (run after adding new assets or on fresh checkout)
/Applications/Godot.app/Contents/MacOS/godot --headless --import

# Run all tests (PREFERRED — use this, not raw Godot commands)
script/checks/gut_tests

# Run a single test file
script/checks/gut_tests -f tests/unit/test_foo.gd
# Other flags: --failing-only (only failing-test lines), --no-color (strip ANSI)

# Run all validation checks
script/validate

# Run the game
/Applications/Godot.app/Contents/MacOS/godot --path .
```

---

## Audio Asset Conventions

- **Format standard:** All WAVs must be 16-bit 48kHz. Normalize to -1 dBFS peak using `sox input.wav -b 16 -r 48000 output.wav gain -n -1`.
- **Import settings:** `.import` files must have `compress/mode=2` (QOA) and `edit/loop_mode=0`. Looping is handled in code via restart-on-finish, not via import settings.
- **Naming:** `{type}_{variant}_{state}.wav` — all lowercase, underscores, no Freesound IDs. (e.g. `ferret_dook_01.wav`, not `155115__jzazvurek__ferret.wav`)
- **Credits:** Every imported sound gets an entry in `../game_assets/Credits.md` with author name and source URL.
- **Archive:** Original files (pre-normalization) are kept in `../game_assets/`.
- **Tools:** `sox` (install via `brew install sox`) for normalization and format conversion.

---

## Known Issues (Ring 0)

- **Comfort-focused cats still prefer warmth:** Pile ad radius too small relative to server. Tuning needed.
- **LightingSystem (CanvasModulate) disabled:** Washes out colors at 224×128 viewport. Needs redesign.
- **PU coordinate system adds unnecessary complexity:** `POSITION_SCALE=100` multiplier makes coordinate math confusing. Candidate for removal refactor. Animals hardcode Y to `FLOOR_Y - 1`; proper rack climbing will need real Y handling.
- **Heat overlay alignment uses RACK_SLOT0_Y now** (was empirical `+4.0`). Other overlay positions may still be fragile.

## GameStateDB Gotchas

- **`get_component()` returns a reference, not a copy.** The spec says "row view assembled from columns" but the current implementation returns the internal dict directly. If you need a snapshot for comparison across ticks/mutations, capture the specific int value, not the dict.
- **`set_field()` only accepts `int` values.** Components with StringName fields (like `ai_state.state` or `plant_growth.state`) must be updated via `get_component()` → modify dict → `set_component()`. Passing a StringName to `set_field()` is a compile error.
- **Events autoload lives at `nodes/events.gd`** (extends Node), not `engine/core/`. The `no_node_in_core` check blocks Node types in `engine/`.

## Workarounds Without Root Causes

<!-- AI-DEV: Items in this section are **empirical fixes found by trial and error**. We do NOT understand the root causes. Do NOT present these as facts about how Godot works. If a problem recurs, start from first principles rather than assuming these workarounds are correct. -->

- **WAV audio silent despite `playing=true`:** Uncompressed WAV (`compress/mode=0` in `.import`) produced no audio in Godot 4.6.1. Switching to QOA compression (`compress/mode=2`) fixed playback. However, QOA with `edit/loop_mode=1` was also silent — workaround is `edit/loop_mode=0` with code-driven restart when the stream ends. Fix found by comparing with a working project (purrBall), not by understanding the cause.

---

## Human Setup

See [README.md](README.md) for prerequisites, installation, and contributor guidelines.

---

## Git & Commits

- Design-phase work: brainstorm freely
- Once implementation starts: all code changes need explicit user approval ("commit this")
