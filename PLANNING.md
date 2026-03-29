# Tuna Control Protocol — Planning Doc

## Reminders

- **How to tell you're winning?**
  - Cats/Kittens hang from every shelf, purring and slow blinking because they're happy, healthy, and cared for.
- **Core loop**
  1. Raising new kittens introduces some instability
  2. The player and/or adult cats encourage kittens to grow
  3. Adult cats stabilize the instability the kittens create
  4. Raising kittens requires at least 2x of the previous systems (or some other inter-dependency)
- **Networking**
  - Do we want to have multi-player?
- **This is a vegan game**
  - No eating mice
  - Super AI has created mega-crops that perfectly perform nutrition (but they still need work to make them taste right)

---

## Decisions Deferred

Acknowledged but not yet specced. Need prototyping or design exploration first.

| Decision | Why deferred | When to revisit |
|---|---|---|
| GDScript mod sandboxing details | Need framework running first | After mod loader ships |
| Specific response curve parameters | Need playtesting | After Ring 0 prototype |
| ModDB scanning implementation | Need mod ecosystem first | After 3+ mods exist |
| WebRTC for peer-to-peer fallback | ENet sufficient for now | If NAT traversal becomes a problem |
| Save compression threshold | Need real save file sizes | After 100+ entities in a save |
| Hot-reload in production | Debug builds only for now | If modders demand it |
| Controller input mapping details | Planned, not implemented | Before first public playtest |
| Teaching system | Schema exists but CLAUDE.md says "TBD whether this makes the cut" | After Ring 0 prototype proves base desire system |
| MessagePack GDExtension dependency | Using `luiherch/Godot4MessagePack` (pure GDScript, MIT, 22 stars). Vendor it. | If save/load perf bottlenecks at scale, write GDExtension wrapper |
| Multiplayer sync model | Cosmetic neighbor spillover syncs every ~1min. Real-time deltas only within a single player's own local server. Not a real-time shared sim. | Before multiplayer prototype |
| GameStateDB performance at scale | GDScript Dictionary at 1000+ entities may bottleneck. Design interface for GDExtension swap. | Profile at 100+ entities, decide at 500+ |
| Config array merge strategy | Arrays: concatenate, replace, or merge-by-ID? KSP's insert-appends model avoids most conflicts. Need to define for TCP. | Before first config file is loaded |
| Relative value operations in config | KSP's `*= 0.8`, `+= 500` let mods say "make boxes 20% weaker" instead of absolute values. Composable, not conflicting. | Before first config file is loaded |
| Conditional config application (:NEEDS) | KSP's `:NEEDS[Mod]` applies patches only when another mod is present. TCP's ModAnalyzer handles ordering but not conditional application. | Before first config file is loaded |
| Save payload: infrastructure & config_overrides | **RESOLVED:** Infrastructure (cables, rack assignments) are entities with components. No separate `infrastructure` key. Player preferences go in `user://preferences.json`, not saves. | — |
| Proximity event complexity | Event definitions in object config embed animation sequences, scene dimming, cooldowns — essentially cutscene scripting. May need separation. Prototype should hardcode the 2-3 events in GDScript, extract schema later. | Before second proximity event type |
| Bilateral interaction model | Proximity events should not be "ferret does X to box." Define "sniff" as a ferret behavior and "being sniffed" as a reaction any sniffable object supports. Interactions emerge from both sides having compatible interfaces, matching the object-advertisement pattern. | Before proximity event schema is finalized |
| GameStateDB full interface | Batch-first API: primary operations are "given a query, apply this to all matching entities" not entity-by-entity. Single-entity access exists but is not the default path. Column-oriented storage for hot components behind a row-oriented single-entity view. Design discussion in progress. | Before first GDScript file |

---

## Backstory

### Option 1 — Player is a sentient datacenter robot helping the world heal

After the AI bubble collapsed, hundreds of AI datacenters were abandoned and fell silent. The towns that grew up to service the datacenters gradually became ghost towns and nature began to come back to the area. But cats, originally drawn to the datacenters by the warmth, were the first to repopulate the data centers. As time drew on, plants and mosses began to grow, and other animals began to return. Food, water, and shelter are taken care of, so the community focuses on raising their young instead of eating each other.

**Outstanding questions:**
- Why does the arm want the cats?
  - ~~Alert: 4 servers online... Paging humans in 5 min. Scans cat.~~
  - ~~"Can you pass a healthcheck?" Boop. "Yes"~~
  - ~~Doesn't know what happens if all the servers go offline. "Will someone come and replace me?"~~
  - It doesn't know they're cats; it just thinks they're weird servers and it's doing its best
  - **Decision:** The robot is a caretaker. These servers are weird and squishy, but the goal is the same: make sure they're happy and healthy. Purring = IOPS. Treat consumption = packets/sec. Lots of latitude for comedy (robot holding ethernet cord, staring at cat butt, thinking hard — cut to cat running out of frame).
- Are there still humans in the world?
  - Maybe mail from another datacenter asking if anyone has seen a repair tech
- Are there different floors or just horizontal scroll?
  - Could there be plumbing problems on the bottom floor?
  - Is there rain upstairs?
  - Is there an exit door?
  - Something to unlock to get up a floor?
  - Server components as stairs
- Do we have seasons?
  - More cats is more heat
- Resources
  - Sunlight? Or artificial light?
  - Power? Broken old solar panels? Fuel?
  - Money or budget to order tuna?
- Chef cats kneading dough
  - Maybe not dough, but higher-end tuna meals. Perhaps heat locks the shape together or sears it.
  - Alternatively, cooking a fish could be an option. For whatever reason I don't mind fish as much as mice. Bugs are even better though, but I'm not sure that plays as well with audiences.
  - Crunchy cricket cakes

### ~~Option 2 — Player is a distressed worker seeking warmth~~

~~Despite the long hours, or maybe because of it, the player has decided to foster kittens in the datacenter. Kittens need warmth and food and love, but the player also needs these things, and the kittens and cats help the player heal and thrive.~~

---

## Layer 0 — Viewport, game state, window

### Placement of resources / cats / kittens

The window is an infinitely long server rack viewed from the front. On a normal monitor, 5 racks are fully visible with a bit of the rack to each side; on a phone, only one rack is fully visible, but a bit of each side is visible. Probably we start with a 960px tall viewport that is as wide as it needs to be.

I like the idea of this being a multiplayer game and being able to invite friends, claim some space, but also communicate with the folks near you in a vague, multi-lingual way (emoji?). Maybe at the front screen it has 3 options, Solo, Multiplayer (each player gets stripes of 5 racks, but can invite friends or open the slots nearby for collaboration), Collaborative multiplayer (each player gets stripes of 3 racks and has to work together with others nearby)

When a cat becomes an adult, it will wander around on the window, sit in drawers, hang out in the tech tower (but not on any nodes), scratch at the back door, and generally wander around. They don't cause problems aside from being slightly in the way of placement, but they can be moved by left clicking on them (which will make a kissy noise or a pspsps noise). These cats also migrate between different player's racks, but they won't do any work, just mildly get in the way.

When the game starts, it shows the current state of the longest active 15 player racks, zoomed out so you just see a lot of activity. It also shows the username of the player in each position.

### Game state / Server sync

Personal game state can be exported to a file, but it's also automatically synced with the server. If a player wants to reload their file, they can, but they lose their place in the racks. If a player doesn't tend their racks for 2 weeks, they are replaced and everyone who started later moves to the left. This gradually moves the longest active players to the first slots.

Current state is synced with the server every 1min or on close (if there's time, but there may not be). The game does not run in the background. Wandering cats, stats, non-player-placed decorations are personal to the device and are never synced, just the initial state of what's to your left/right, how many wanderers there are, and roughly what those racks are doing or affecting on your servers. There are some live actions, like communication, but for the most part there should not be a **ton** of server communication.

### HUD

At the top there are several menus: Kitties, Cables, Infrastructure, Utilities. In the kitties menu, instead of a text menu popping down, a drawer slides out and there is a basket of baby kittens. At first, there's only one white fluffy kitten. The drawer is never fully closed (they need air after all), so sometimes little kitten paws will pop out and poke around like a paw under a door.

Similarly when you pull open the cable drawer you find an absolute snarl of cables. Again, at first there's only ethernet cables, but you have to grab one to place it on the board. When the drawer is shut, one cable head is always sticking out just a little bit.

In the infrastructure drawer there are servers, load balancers, etc just scattered around. This drawer *does* shut nicely.

Lastly, the "utilities" drawer has nothing at first, but it can still be opened. Eventually it'll have a litter box and toys and all sorts of things. Sometimes a little toy tail or feather will poke out of the drawer.

~~At the top left is a stats panel showing points, but it's not clear what points are.~~ **Decision (2026-03-29):** No points panel in prototype. Define later.

There is a button with a coil of wire icon that switches the view to the back of the racks and shows the wiring diagram of everything.

~~Much like Oxygen Not Included, there is a work priority bar, but it's disabled for a while.~~

**Decision (2026-03-29):** No work priority system. You cannot force a cat to do things; even suggestions will result in the opposite happening. Ferrets are very suggestible as long as it's what they were going to do anyway. Animals act on their own desires, not player-assigned tasks. The player's verb is **arranging the environment**, not assigning jobs.

**Outstanding questions:**
- How much observability do we actually want to put in here? Do we want stats graphs? FACET by server? By cat?
- What kind of stats are we keeping?
- Do we want heatmaps of contention?

**No time controls.** The game is never frantic. See `input-design.md` for full input/controller/keyboard spec.

### Spatial model & heat

Physical layout (dimensions, interaction radii, heat propagation) in `viewport-lod.md`. Pixel scale in `art-direction.md`. Tick architecture in `tick-architecture.md`.

---

## Layer 1 — Basic Servers, heat, petting

### Attracting cats

If there are no nesting boxes and no cats or kittens, a fluffy white cat should wander into the screen immediately and pace back and forth. If she doesn't find a nice box or something to nestle in she'll pace and meow, paw at a box on the floor that has been knocked down.

When she meows, if there's no box in the rack at all, the cardboard box will highlight or glow. When the player clicks it, it'll turn into a box and the cat will sniff it, purr, then slow blink at the player. The box can be picked up, then while holding the box, mousing over the rack will show a highlight around 3U when the cursor is over one of the racks.

She can't jump, so if the player puts a box too high, she'll just look up at it and meow. Maybe even stretch, but not jump. When the player puts a nice box or constructs a place to nestle, she'll curl up in it and purr. She can be scritched for more purring. When she settles down, a weight bar lights up on the side of the rack which displays how heavy she is, and thus, how far along she is in her pregnancy. There is also a temp bar which will have a warning for low temp on it.

If the player clicks on the rack, it will pull the drawer out and show her (and maybe her kittens!), but also have a zoom in on the status lights from the side panel so players can see the icons or words written by the bars and understand what they are a little better. The temp bar will show a low temperature alert (because servers *should* be making heat, this one seems to be producing very little heat compared to normal). There is also a water bar, power bar, data bar, HVAC bar, and 8 connectivity lights. This is on the left side of each rack slot, and only the lowest one will perk up when momma settles in.

The nest box takes up 3U in the rack and should be placed on the bottom 3 rows of one of the racks.

### Phase 2 — Heat and kitten growth

After the nesting box is placed, if there are no servers in the racks, the server drawer will highlight to indicate it should be clicked.

In the beginning of the game, only 2U servers are available. Like the nesting box, these can be placed as long as there's space. When it's being placed, it has the normal highlight box that indicates whether it fits, but it *also* displays a red vignette on the server slots to the right, left, and 3U above it. It's okay if the heat extends to the next player's rack, that could be advantageous to the next player!

Once the server is placed, if there are no servers that are currently plugged in, the wiring view icon will highlight to draw the player's attention. When clicked, again, if there are no plugged in servers, the PDU on the right side of the rack will highlight. Clicking on that highlights all the rack slots that *can* be plugged in. Clicking on the slot will draw the wire going from the PDU on the right side of the rack to the server's power port. The wire would dangle or drag on the floor. When the server is plugged in, the power bar lights up a little bit showing the minimal server drain (the status bars are on the *right* in the back and displayed in opposite order so the bar closest to the server is still the same when viewed from the back or front). The server fans also start moving slowly.

Again, if there are no servers in the rack that are plugged in to ethernet, the top-of-rack switch will highlight. Clicking on that will then highlight all the servers that can be plugged in as well as the cable run on the left. Clicking on the new server will draw an ethernet wire going from the switch to the server. Clicking on the cable run first will change the highlight to green to indicate it's been selected. Clicking on the server then will draw an ethernet wire nicely going down the cable run and plugging in to the server. One of the connectivity lights will light up, and the server will really kick into gear. The fans will speed up a lot, and the connectivity light will start blinking like wild. Additionally, the heat bars on the nearest rack slots will show one little bit of red. This will gradually grow, but at first we just need *some* indicator that heat is happening.

When the first bit of heat hits the momma cat she will purr mightily and her progress bar will start moving slowly upwards (previously it was much slower) and turn green (previously it was yellow).

When the progress bar makes it to 1/3, the kittens are born. There is a lot more cute mewling that happens. The stats panel will highlight and n new disk health lights will appear in the upper left stats panel to show that the player has done the right thing (I'm thinking about showing average cat happiness but interpreting it through the lens of a datacenter automation robot, so maybe it thinks they're making happy HDD noises when they purr). Success!

Once the kittens get mobile, they'll wander around and play, get tangled up in cables, unplug things, and generally cause mischief.

Also, as soon as the server is correctly plugged in, another adult cat will wander into the scene and settle on top of it. If the player builds a second server, another adult cat will appear. There should be a cozy spot counter which shows how many available spots there are for cats that are within jumping distance of each other. Until the player unlocks support structures, they will need to arrange servers in stair patterns so that cats can jump around.

### Skill cat tower

Living beings are the tech tree points, so as soon as the momma cat settles down, the skill cat tower (not tech tree) unlocks. But it won't highlight until later; if players find it, that's okay, they can use their points. It's only when the kittens are born that the tech tree highlights.

Instead of clicking on a tech tree node, you can move your adult cat to that node. It will curl up and purr for a little bit. They can't be moved around once placed, but they do unlock more things. The entire skill tree is visible but grayed out; I want players to know how much more there is, but not exactly *what* is left.

One of the first unlocks is little shelves that cats can use to access higher rack spots.

We shouldn't work too much on the tech tower yet.

Eventually there will be many parts to the tower spanning a whole wall, over a window, around the couch, through the bookshelf, etc. It'll be elaborate. The tower is not just a cat tower — it has gerbil runs, vent tubes, hammocks, little houses for guinea pigs, and other adorable things.

**Outstanding questions:**
- How do kittens cause problems?

### Phase 3 — Food and water

~~Once the kittens are weaned, momma needs to get food. At this point, the Work Priority menu (icon?) blinks to give the player the idea that they need to click it. When they open, they see Momma's name and a series of checkboxes. All of them are unchecked **and** disabled except for food (chef hat icon?). If there are no priorities set for any cats, the food box(es) will highlight. Clicking on that box assigns her to gather food. Clicking once gives a grey minus sign in that box (just like ONI) indicating that it's neutral priority.~~

~~As soon as the box is clicked, she starts to walk off screen to find food. When she returns, she has something (what?) in her mouth. It's unclear what the food is, but she gives it to the kittens and they happily eat it.~~

**Decision (2026-03-29):** No work assignment. Food in the prototype comes from tuna cans — ferrets drag them to the robot arm, the arm opens them, cats eat them. This is the emergent food chain described in the Prototype Scene section. For the full game, there will be many more food sources and preparation methods (crunchy cricket cakes, chef cats, seared tuna, etc.) but for the prototype, cans are the food system.

When the cats have had a meal, they all clumsily follow momma over to a cooling pipe which has condensation on it. Momma shows them how to lick the water droplets off of it. (Later we'll have ways to harvest this).

---

## Design Decisions from Brainstorming (2026-03-28)

### ONI is the wrong model

ONI is about scarcity and optimization. TCP is about abundance and joy. We don't want players to run out of resources. The adversity comes from the sheer complexity of keeping thousands of animals happy simultaneously, not from deprivation.

**Gnorp Apologue** is the better model: no lose condition, but a hard theoretical maximum that's genuinely difficult to find.

### The animal desire system

**Maslow's hierarchy + individual traits.**

- **Base layer (universal):** Warmth, food, water, shelter. Easy to meet. All animals agree these matter.
- **Higher layers (individualized):** Novelty, companionship, stimulation, teaching, exploration. Each individual animal has randomly weighted preferences here. You can't just optimize for "cats" as a category — you have to observe what *this* cat wants.
- **Unmet needs don't kill.** Animals with unmet higher-order needs don't purr (no IOPS). They might have sad expressions, move listlessly, or eventually wander off. But they don't die.

### Teaching as emergence

- **Vertical transmission:** Adult teaches young (chef cat teaches kitten to make biscuits)
- **Horizontal transmission:** Peer to peer, in-group to out-group
- Each individual has specialties; teaching grants some of that knowledge
- Still TBD whether this makes the cut vs. simpler emergence. It's important thematically but may be too complex for early implementation.

### Multi-species ecosystem

Animals arrive when conditions are right (Terry Pratchett logic: get enough tubes in one room and a ferret is bound to emerge from one). Each species has unique needs and contributes something that enables others.

**Known species and roles:**
- **Cats:** The core. Need warmth, food, comfort, companionship. Purr (produce IOPS). Kittens cause chaos.
- **Ferrets:** Need chaos/surprise/discovery (jangling keys, crashes, noise), things to dig (rice), hiding places, treats (ferret oil), food, water, shelter, companionship. Can hack ordering systems (unlock tuna delivery). Unlock access to new areas.
- **Dogs:** Warm to sleep next to, help move fast and reach higher points, great at moving heavy things, smart. Community builders and stabilizers. Not guardians (no enemies in this game).
- **Guinea pigs, rabbits, birds, others:** TBD. Each should have unique needs and unique contributions.

**Inter-species dependencies create the scaling curve:**
- Without ferrets hacking the order system, cats can't have tuna
- Without fur balls for ferrets to hide, you can't attract ferrets
- Diversity enables the next tier of happiness, which enables more animals, which enables more diversity

### Conveyance infrastructure

Nothing is purely cosmetic. Everything serves a purpose, even if we don't know exactly how yet.

- **Gerbil/hamster tubes:** Conveyance for small animals
- **Bridges/ledges:** For medium-sized jumping animals
- **Gates/doors:** For larger, smarter animals
- The emergence is that we don't fully define how these get used — animals with desires find ways to use infrastructure that we didn't predict

### The robot arm's perspective

The robot interprets everything through datacenter metrics:
- Purring = IOPS (disk access sounds)
- Treat consumption = packets/sec
- Cat happiness = disk health
- New kittens born = new drives coming online

Comedy comes from the gap between what's happening (adorable animals thriving) and what the robot thinks is happening (servers doing server things). The robot tries to scan a kitten's UPC barcode; the kitten pounces on the laser beam.

### "Fixing the world" theme

Present but not heavy-handed. Not like Planet Crafter where terraforming is the goal. The world-healing is a backdrop that gives meaning to the abundance. It's about a post-collapse world where, because survival is handled, communities can focus on thriving.

How this manifests mechanically is still unclear. Possible directions:
- Plants grow as animal happiness increases
- Mail from other datacenters (narrative breadcrumbs)
- The building gradually transforms from gray ruin to green sanctuary
- But: if it's truly about regeneration, what are cats building ramps out of? Sticks and grass feels right but conflicts with cans of tuna. This remains a mystery.

---

## Prototype Scene — The Interaction Test (2026-03-28)

### The litmus test

> The test is whether someone voluntarily rearranges furniture and can tell a story about a specific cat. If that works, everything else is amplification.

Before adding more species, systems, or progression — does this one room produce emergent stories from placement alone?

### Hysteresis & commitment

**Hysteresis** = time-lag in state changes. Animals don't snap instantly to new conditions. A cat that's cozy on the clothes pile doesn't abandon it the moment temperature drops by 1°C — she's *committed* to that spot. It takes accumulated discomfort to trigger relocation, and settling into a new spot takes time too.

This is mandatory from prototype one because:
- Without it, optimization is trivial (instant feedback → instant min-maxing)
- With it, the world has weight and animals feel like they *care* about their choices
- It creates consequences for rearranging things without being punitive — you can always fix it, but there's a cost in disrupted comfort
- It produces cascading dynamics: pounce wakes cat → cat relocates → pile cools → ferrets lose warm spot → everyone slightly less happy until the system re-settles

### Actors

**Prototype starts with 3 cats and 2 ferrets.** Full game will do more with narrative arrival sequences, but the prototype needs all actors present to test the interaction web.

- **Cats (3)** — want warmth, comfort, peace, food (tuna). One is the momma.
- **Kittens** (later in game, not in prototype first pass) — chaos agents, learning by watching
- **Ferrets (2)** — want chaos/stimulation, furballs, hiding spots; ground-level by default

**Visual individuation:** We have 5 distinct cat models and 5 kitten models. This is critical — the litmus test ("tell a story about a specific cat") requires players to visually distinguish individuals. Names/IDs come from the robot arm's device registry.

**Terry Pratchett arrival logic (full game):** Animals arrive when conditions are right. Get enough tubes in one room and a ferret is bound to come out of one. Get enough warm spots and cats will find them. The world fills itself when the player creates the right conditions. This is deferred for prototype — prototype pre-populates actors — but the principle should guide all future species introduction.

### The player's role: competing desires in shared space

The player verb is **arranging**. Once placed, the player watches. The fun is in discovering that:

- Momma wants the pile near heat, away from the fan
- Ferrets want the pile near the fan (stimulation + warmth)
- Tuna cans need to end up near the robot arm, but ferrets drag them wherever they feel like
- The box is the best ferret hiding spot, but it's also blocking warm air from reaching the pile
- Furballs accumulate up high where cats bat them, but ferrets can't reach them without player-built infrastructure

Every placement choice helps one thing and complicates another. Not because the game punishes — because the animals genuinely want different configurations of the same room. **The challenge: can you arrange this room so everyone's happy at once?** And when they inevitably knock things over, pounce each other awake, and shred the box — can you adapt?

### Metrics to instrument from prototype one

- Time spent watching vs. time spent placing (engagement ratio)
- Number of voluntary rearrangements per session
- Whether players can narrate what happened ("the ferret dragged the can to the robot arm because it likes the sound")
- Cascade length: how many state changes follow from one event
- Time-to-equilibrium after a disruption

### Idle and ambient behavior

Animals spend most of their time doing nothing goal-directed. This is what makes them feel alive. Without ambient behavior, the room is a state machine flipping between interactions. With it, the room breathes.

**Why this is critical for the prototype:** The litmus test is "tell a story about a specific cat." Stories require character, and character comes from what animals do between the interesting moments — the grooming, the stretching, the staring into space. If animals only ever sleep, eat, or interact with objects, they feel like automata.

**Ambient behavior budget:** At any given moment, most animals should be in an ambient state, not a goal-directed one. Rough target: 70% ambient, 30% goal-directed. This ratio is what makes goal-directed behavior *noticeable* — when a cat gets up and walks somewhere, the player pays attention because it was doing nothing a moment ago.

#### Cat ambient behaviors

| Behavior | Visual | Sound | When | Duration |
|---|---|---|---|---|
| Grooming | Licking paw, rubbing face, washing ear | Soft lick sounds, occasional pause | Warm + comfortable, after eating | 15-30 sec |
| Stretching | Full body stretch, yawn | Tiny squeak-yawn | After sleeping, on waking | 3-5 sec |
| Slow blink | Eyes close slowly, reopen | Quiet purr | Content, looking at player or another cat | 2-3 sec |
| Loafing | Tucked paws, upright but relaxed | Steady low purr | Comfortable, not sleepy | 30-60 sec |
| Tail flick | Tail tip moves, body still | Silent | Mildly alert, watching something | 5-10 sec |
| Head track | Head follows moving object/animal | Silent | Something interesting nearby but not interesting enough to move | Varies |
| Repositioning | Stands, turns, lies back down | Soft thud + sigh | Periodically during long rest | 3-5 sec |
| Staring at nothing | Fixed gaze at empty spot on wall | Silent | Random | 5-20 sec |
| Kneading | Paws press rhythmically on surface | Soft fabric sounds | Very content, on soft surface | 10-20 sec |

#### Ferret ambient behaviors

| Behavior | Visual | Sound | When | Duration |
|---|---|---|---|---|
| War dance | Arched back, sideways hopping, mouth open | Dooking (happy clucking) | Excited, after play, near other ferrets | 5-10 sec |
| Dead sleep | Completely limp, looks alarming | Silent (no breathing visible for comedy) | Exhausted after activity burst | 30-60 sec, unresponsive to mild stimuli |
| Grooming | Face washing, scratching behind ear | Tiny scratching sounds | After waking, between activities | 10-15 sec |
| Sniffing around | Nose to ground, weaving path | Quiet snuffling | Exploring, looking for new things | 15-30 sec |
| Speed bump | Flat on belly, chin on floor | Soft sigh | Warm spot, just vibing | 20-40 sec |
| Tunneling attempt | Pushing nose under blanket/pile edge | Rustling, muffled dooking | Near soft objects | 5-10 sec |
| Stashing check | Trots to stash, inspects, adjusts, leaves | Quiet churring | Periodically, more often with larger stash | 5-10 sec |
| Sleeping on cat | Drapes over sleeping cat | Ferret sigh, cat mrrp (mildly annoyed) | Near a sleeping cat, ferret is tired | 30-60 sec |

#### Cross-species ambient interactions

These aren't goal-directed — they just happen when animals are near each other.

| Interaction | What happens | Side effect |
|---|---|---|
| Mutual grooming | Cat grooms nearby cat | Both comfort increases slightly |
| Nose boop | Ferret approaches cat, touches noses | Brief alert state on both, then relax. Tiny bonding moment. |
| Tail chase | Ferret notices cat's twitching tail, lunges | Cat startled, relocates. Ferret confused about where the toy went. |
| Pile-on | Second cat lies against first | Both warmer. Creates a visual mass that reads as "this spot is good." |
| Ferret speed bump blocks path | Ferret goes flat in a walkway | Cat steps over or reroutes. Mild disruption. |

State machine, weighted pool selection, hysteresis, and interruptibility in `animal-ai.md`.

### Prototype resource matrix

Every object in the scene serves at least one need for at least one species. If it doesn't, it shouldn't be in the prototype.

| Object | Heat | Comfort/Shelter | Play/Stimulation | Food | Water | Notes |
|---|---|---|---|---|---|---|
| Servers (2+) | **Source** — radiate heat into nearby rack slots | — | — | — | — | Fixed in rack. Heat radiates to adjacent slots and neighbors. |
| Cardboard box | Insulator — traps nearby heat | **Cat:** nesting, safe space | **Ferret:** hiding, shredding | — | — | Degrades over time from ferret play → produces bedding scraps cats use. Moveable. |
| Comfy clothes pile | Amplifier — retains body heat from sleeping animals | **Cat:** premium sleep spot | **Ferret:** burrowing, pounce target | — | — | Generates loose fur/fluff. Moveable. |
| Feather + fan | — | — | **Both:** unpredictable motion, chasing, batting | — | — | Placeable. Fan speed affects feather behavior. |
| Tuna cans (pile) | — | — | **Ferret:** dragging (adorable scraping noise) | **Cat:** food (once opened) | — | Sealed. Infinite supply (abundance). Ferrets drag them; also play in empties. |
| Robot arm station | — | — | **Ferret:** fascinated by the mechanism | **Cat:** food source (opened tuna) | — | Fixed. Robot arm opens anything that looks like it needs opening, washes the can, hose carries it away. |
| Furballs | — | **Ferret:** collectible comfort objects | **Cat:** batting toy (loses interest quickly) | — | — | Accumulate from clothes pile / grooming. Lightweight, roll easily. |
| Cooling pipes | — | — | — | — | **Both:** condensation droplets | Fixed infrastructure. Condensation rate increases near heat sources. |

### How species interact with the scene (and each other)

The key insight: **cooperation is a side effect, not a transaction.** Nobody is trading. Nobody is being distracted or tricked. Each animal does what it naturally wants, and the *byproducts* of those desires happen to help the other species.

**Cats and tuna cans:**
- Cats want tuna but can't open cans. They don't try — they just look at sealed cans with mild interest and move on.
- When opened tuna appears at the auto-opener, cats eat it. Simple.

**Ferrets and the robot arm:**
- Ferrets drag tuna cans around the floor because dragging things is fun (and makes an adorable scraping noise across the datacenter tiles).
- When a ferret drags a can near the robot arm's station, the arm does what it does — it sees something that needs opening, so it opens it. *Chunk-whirr-scoop.* The arm washes the can, a little hose carries the empty away.
- The ferret watches, fascinated by the mechanism, then wanders off to do something else — chase the feather, burrow in the pile, drag another can around.
- The cat shows up and finds opened tuna. From the cat's perspective, food just appears sometimes. From the ferret's perspective, dragging cans is fun and sometimes a cool machine activates. From the robot's perspective, it's processing inventory. Nobody planned this.

**Cats and furballs:**
- Furballs accumulate from the clothes pile and from grooming.
- Cats bat furballs around because that's what cats do. They're mildly entertaining for about 30 seconds before the cat gets bored and walks away.
- Batted furballs roll and land wherever gravity takes them — off shelves, across the floor, into corners.
- Ferrets *love* furballs as comfort/collection objects. They grab the ones cats have abandoned and stash them.
- From the cat's perspective, the furball stopped being interesting. From the ferret's perspective, furballs keep appearing in reachable places. Neither is cooperating — but the ecosystem works.

**The warmth loop:**
- Cats sleeping on the clothes pile near servers generate body heat → pile gets warmer → attracts more cats → pile gets warmer still.
- Ferrets are drawn to the warm pile too (burrowing + warmth), but ferret energy means occasional pouncing.
- Pounced cats wake up and relocate (hysteresis — they don't instantly return). Pile cools slightly. System re-settles.
- This isn't a problem to solve — it's the **rhythm** of the room. Warmth builds, disruption scatters, warmth rebuilds.

**The cardboard cycle:**
- Ferrets shred cardboard boxes (it's irresistible).
- Shredded cardboard becomes bedding scraps that cats actually prefer for certain nesting.
- Player can place new boxes, which ferrets will eventually shred again.
- This creates a slow material cycle: box → scraps → nesting material. The player's choice is where to place new boxes, knowing they'll transform.

### Revised interaction web

| What happens | Who does it | Why they do it | Side effect for others |
|---|---|---|---|
| Drag tuna can across floor | Ferret | Dragging things is fun, makes a great scraping noise | Can ends up near robot arm station |
| Robot arm opens can | Robot arm | Sees something that needs opening | Opened tuna becomes available; wash + hose carries empty away |
| Eat opened tuna | Cat | Hungry | — (but cat is now happy and purring) |
| Bat furball off shelf | Cat | Momentary amusement | Furball lands where ferrets can reach it |
| Collect furballs | Ferret | Comfort hoarding | Furballs cleared from cat areas |
| Sleep on pile near heat | Cat | Warmth + comfort | Pile temp rises, attracts others; loose fur generates furballs |
| Burrow in pile | Ferret | Warmth + hiding | Disrupts sleeping cats (mild) |
| Pounce sleeping cat | Ferret | Movement is irresistible | Breaks warmth loop temporarily; cat relocates |
| Shred cardboard box | Ferret | Texture is irresistible | Box destroyed → bedding scraps cats use |
| Bat at fan/feather | Cat | Hunting instinct | Feather stops → ferrets lose a stimulation source |
| Chase feather | Ferret | Chaotic movement = joy | Ferret occupied → pile is peaceful for cats |

That's **11 dynamics from 8 objects and 2 species**, and every interaction is motivated by the actor's own desire — never by a deal or a distraction. The cooperation is invisible to the animals and visible to the player. That's the story the player tells: *"The ferret didn't MEAN to feed the cats, it just liked the machine."*

### Sound system

Full sound spec in `sound-design.md` — mixing, purr variation, silence states, spatial attenuation, source checklist, aggregate soundscape progression.

### Resolved design decisions for prototype (2026-03-29)

**Maslow satisfaction: soft gradient with hysteresis band.** Higher-order desires activate via sigmoid as base needs are met; activation/deactivation thresholds are offset so brief dips don't snap behavior. Implementation: `animal-ai.md`. Visual stages: `art-direction.md`. Sound: `sound-design.md`. Robot interpretation: `narrative.md`.

**Ferrets stay ground-level by default.** Ferrets cannot jump. Vertical access requires player-built infrastructure (tubes, ramps, cable bridges). This makes cats batting furballs down from high places more valuable — it's the *only* way ferrets get them until the player builds infrastructure. Tubes visually distinct from cat shelves: enclosed cylindrical (warm plastic tan/amber) vs. open flat (datacenter gray-blue metal). Pathfinding capability matrix in `navigation.md`. Robot narrator interprets tubes as "auxiliary data conduits."

**Robot arm station: fixed for prototype.**
- Fixed position creates the spatial puzzle that makes ferret-dragging meaningful. If placeable, players put it next to tuna and the whole dynamic collapses.
- Visual anchor: the one piece of original datacenter infrastructure still operational. Cleaner metal finish, its own pool of light, faded yellow hazard paint marking the interaction radius.
- Audio anchor: consistent spatial position in the mix. Tuna cans scraping toward it become a directional audio cue.
- Making it placeable later is a ~2-hour change (remove rack-snap constraint in config). Could be a skill tower unlock or mod option. Not an architecture decision.

**Cardboard box degradation: gradual transformation, not sudden collapse.**
- HP float (1.0 → 0.0) drains slowly from ferret shred interactions. Never sudden.
- Three visual stages: pristine (clean edges, shipping label) → worn (corners chewed, flap bent, ragged silhouette) → scraps (flat pile of corrugated strips, warm-toned, nest-like contour).
- When HP hits zero, box sags over 5-10 seconds (giving occupant time to leave via normal discomfort). If cat is still inside at collapse, gently eject with confused animation — never trap.
- Scraps are a different object type: same entity swaps from `cardboard_box` to `bedding_scraps`. Loses "shelter" and "hiding" desires, gains "nesting_material."
- Scrap count proportional to box size (~4-6 scraps per standard box). Scraps scatter where the box was.
- Sound: three stages. Intact = deep hollow bonk + muffled rustle. Worn = thin papery bonk + light tearing. Scraps = soft dry whisper when animals move through, like shuffling leaves.
- Robot narrator: "Enclosure unit 3 structural integrity at 74%. Cause: unknown vibration damage." At collapse: "Catastrophic chassis failure. Components salvageable. Reclassifying debris as 'thermal insulation media.'"
- ~~Modding: this should be a generic "transformation chain" system, not box-specific code.~~ **Deferred.** Hardcode box-to-scraps for prototype. Generalize the transformation chain when we have more than one transforming object.

**No animal learning in prototype.**
- Learning requires per-animal memory, interaction history tracking, and UI to surface it — too many systems for prototype scope.
- Personality traits (weighted desires) + hysteresis already produce the *illusion* of learning: a cat with low stimulation-tolerance naturally avoids the fan area. It *looks* like learning but it's just preference + spatial choice.
- The robot narrator *does* narrate false learning: "Device 14 appears to have updated its pathfinding firmware. Avoidance pattern suggests awareness of airflow disruption zone." This creates the illusion cheaply.
- When learning ships later: per-animal memory of 5-10 slots, each `{location_id, object_id, valence, timestamp}`. ~40-80 bytes per animal. Memory decays toward zero each tick. Learned behaviors surfaced in inspect panel as named traits.

**Feather toy = active stimulation. Furballs = comfort/collection.**
- Different Maslow layers, never directly compete. A cold/anxious ferret wants furballs. A warm/bored ferret wants the feather.
- Player reads ferret behavior: "She's ignoring the feather and hoarding furballs — she must be stressed, not bored."
- Feather interaction: elongated, low, darting, zigzag, fast animation cycle, high-frequency erratic audio (flutter + scrabbling + excited dooking).
- Furball interaction: upright, gentle approach, picks up with mouth, waddle-walks to stash, slower cycle, quiet audio (soft puff, contented churring).
- Feather is bright, high-contrast (saturated warm color against muted datacenter). Furballs are soft, low-contrast puffs that blend into environment.
- Robot narrator: feather = "high-frequency seek operations, read/write head tracking unpredictable target." Furballs = "accumulating static discharge artifacts. Current inventory: 7 units. Purpose unknown. Possibly building a cache."

**Ferret discovery of robot arm: emergent mini-event.**
- First time a ferret drags a can into the arm's activation radius, the arm activates. Ferret startles (cartoon jump, all four feet off ground), bolts 2 feet away. Beat. Arm finishes opening (chunk-whirr-scoop, wash, hose). Ferret creeps back — tiny cautious claw-taps, nose-first, fascinated churring. Watches arm reset. Scampers off.
- 8-10 second sequence, three audio beats. Rest of scene dims 10-15% to direct player attention.
- Not a special-case script — uses a general `proximity_event` system: trigger condition (species + object + proximity + first_time flag), sequence, outcome. Same system handles cat discovering warm spot, ferret finding tube entrance, etc.
- Robot's log: "ALERT: Unregistered mobile device entered maintenance zone. Device deposited unmarked container. Standard processing applied. Device observed full maintenance cycle at close range, then departed without collecting output. Possible quality assurance audit? Passed, I think. Adding to known device registry as UNIT-F01: 'The Inspector.'"
- Fallback: if no ferret drags a can near the arm within ~10 minutes of ferrets being present, arm does a "curious scan" — extends toward nearest can, makes an inviting mechanical noise. Additionally, if no can has been opened ~3 minutes in, a loose tuna can rolls across the floor from offscreen — maybe fell off a shelf, maybe the building shifted. Gives the ferrets something to discover without forcing it.
- **Lost player detection:** If the player hasn't moved the cursor / made any input for an extended period, the robot arm could do small attention-getting behaviors (scan nearby, make a curious beep, nudge something). Not a tutorial — just the arm being restless, which doubles as a hint.
- Accessibility: slow, interruptible sequence. Discovery logged in activity feed. Notification badge for players who were looking elsewhere.

**No intentional cross-species cooperation in prototype.**
- Cooperation is a side effect, not a transaction. Cats bat furballs because batting is fun; furballs land where gravity takes them. Zero eye contact during exchange.
- The player's story is "the cat *accidentally* helped the ferret" — more delightful than "the cat delivered supplies."
- If intentional cooperation ships later (via teaching system), the visual tell is *eye contact*: giving animal looks at receiver, walks toward them, drops item, holds gaze. The Reddit post: "I think my cat is HELPING the ferret on purpose??"
- ~~Tag every item-movement event with a cause enum from day one (ACCIDENTAL_BAT, GRAVITY, PLAYER_PLACED) even before intentional behavior exists. Cheap to add now, expensive to retrofit.~~ **Deferred.** Prove the feel first; add the enum when intentional behavior is on the roadmap.

**Furball lifecycle: stashing, splitting, forgetting, degrading.**
- Furballs accumulate from clothes pile + grooming. Cats bat them (momentary amusement, then bored).
- Ferrets collect and stash furballs. Ferret stashing behavior is the primary cleanup. Ferrets do NOT sleep in furball piles (those are too sacred). Ferrets sleep on squishy cats instead.
- Ferrets split piles, forget about piles, relocate piles — this is natural ferret behavior and creates ongoing spatial dynamics. A ferret may abandon a stash and start a new one elsewhere.
- Loose furballs that go uncollected degrade slowly (dust bunnies dissipate). Configurable decay timer.
- Hard cap on active physics furballs (~200-300 with object pooling). If cap is reached, oldest untouched furball expires silently.
- Visually: furballs are low-priority — no outlines, muted palette, no animation. 3+ furballs in proximity merge into a cluster sprite to prevent clutter. At low zoom, individual furballs are just environmental texture.
- Sound: one furball is silent. Several create faint dry rustling when air moves past. At high count, a persistent textural layer (room that needs sweeping). Each ferret pickup = tiny satisfying *fwip*, ambient rustling decreases proportionally.
- Robot narrator: "Static discharge artifact count: within parameters" → "Artifact accumulation exceeding baseline" → "WARNING: Datacenter floor coverage at 34% particulate matter. Multiple devices appear to be *manufacturing* these artifacts."
- Accessibility and modding config: deferred. Prove the feel first.

### Remaining open questions for this scene

- **Can opener discovery fallback tuning:** The 10-minute fallback timer for the robot arm's "curious scan" — is that too long? Too short? Needs playtesting.
- **Ferret stash forgetting:** How often do ferrets forget about stashes? Is this random or triggered by something (new object placed nearby, another ferret stealing from the stash)?
- **Box replacement cadence:** How often should the player need to place new cardboard boxes? Is there a natural supply (boxes arriving with tuna deliveries?) or is it purely player-driven from the drawer?
- **Clothes pile depletion:** Does the clothes pile ever get "used up" from generating furballs? Or is it an infinite source? (Abundance principle suggests infinite, but should it thin visually?)
- **Ferret-on-cat sleeping:** Ferrets sleeping on cats is adorable and gameplay-relevant (warmth for ferret, mild weight/disruption for cat). How does this work mechanically? Is it a comfort action for the ferret that slightly reduces the cat's comfort?

---

## Build Order (2026-03-29)

**Prototype first. Onboarding second.** They share systems but serve different purposes.

| Phase | What | Success criterion |
|---|---|---|
| **A: Prototype scene** | 5 animals pre-placed, all 8 objects, desire system, heat, hysteresis, ambient behaviors, sound. No narrative gating, no progression. | Playtesters voluntarily rearrange and tell stories about specific animals. |
| **B: Tune** | Adjust desire weights, hysteresis bands, advertisement ranges, timings. | Cascades feel natural. Animals feel like individuals. Room has rhythm. |
| **C: Layer 1 onboarding** | Single momma cat, guided discovery (box, server, wiring, heat, kittens). Uses Phase A systems but gates introduction. | New player reaches "kittens born" without external instruction. |
| **D: Merge** | Onboarding flows into prototype-equivalent gamestate. | Seamless transition, no "tutorial ends" feeling. |

Single codebase. Mode selected at new-game: `prototype` (pre-populated, skip onboarding) vs. `full_game` (empty room, guided arrival). Prototype mode becomes the "skip tutorial" option. See Kibble's proposal in resolved edge cases below.

---

## Observability System (2026-03-29)

**Observability follows the camera. Zoom level determines detail level.** No separate stats screen. Zoom levels defined in `art-direction.md` (Z0 Rack View, Z1 Drawer View, Z2 Overview). Inspect is a panel overlay, not a zoom level.

**Default state is clean.** No overlays, no numbers. Just animals with posture and sound. All overlays are opt-in toggles.

**Robot narrator is a parallel layer** toggled independently. Replaces plain-language labels with datacenter jargon ("Content" → "NOMINAL", "Lonely" → "LINK DOWN"). The incident log sidebar is always available.

**Prototype ships with minimal observability:** posture, mood weather, heat overlay, robot incident log only. Everything else deferred until base readability is proven.

---

## Resolved Edge Cases (2026-03-29)

**"Wander off" is not permanent loss.** Animals with unmet higher-order needs show visible restlessness (2 min), then walk to screen edge and sit offscreen. They return when conditions improve. Never dead, never despawned. Population counter shows "12 active / 3 roaming." Full spec in `narrative.md`.

**Object removal, collision, and ambient-to-goal ratio:** Implementation in `animal-ai.md`.

**Cozy spot counter: killed as visible UI.** Replaced with internal attractiveness score per slot that drives Terry Pratchett arrival logic. Robot occasionally remarks on capacity. Warm empty spots get subtle heat shimmer.

**Prototype vs. Layer 1: single build, config flag.** `prototype` mode: 3 cats + 2 ferrets pre-placed, all objects available, no onboarding. `full_game` mode: empty room, guided arrival, progressive unlocks. Identical systems underneath. The momma cat from Layer 1 IS one of the 3 prototype cats.

---

## Reference Material

Design specs and implementation rules live in `.claude/rules/` (auto-loaded by agents). JSON schemas live in `schemas/`.

---

## Open Design Questions

### Progression & Phases
- **Why exit Phase 1?** What prevents a player from just having kittens forever? Current thinking: unsatisfied kittens don't purr, so IOPS plateaus. Players want to increase IOPS, which requires meeting higher-order needs, which requires new infrastructure and new species.
- **How does the 2x rule work in practice?** Is it literal (need 2 server setups for Layer 2)? Or is it about inter-dependencies (need cats AND ferrets AND infrastructure to unlock the next tier of happiness)?
- **Multiple floors:** How are they unlocked? Ferrets discover a door? Skill tower unlock? Emergent event?
- **How many animal species is "enough"?** Does each need a unique mechanic, or can some be cosmetic variants?

### Mechanics
- **How do kittens cause problems specifically?** Unplugging servers, tangling cables — what else? And can these "problems" sometimes be accidentally useful?
- **Petting:** Is it interactive (click repeatedly) or passive (auto-complete over time)? How does it work in multiplayer?
- ~~**Observability tools:** What can the player unlock to better understand animal needs at scale?~~ **RESOLVED: Zoom-level-driven system. See `art-direction.md` for zoom levels, `input-design.md` for inspect interaction.**
- **How fast are packets arriving?** How quickly do heat/overheat bars fill?
- **What happens if heat hits another server or piece of infrastructure?**
- **Is litter box emptying fun?** Is the litter robot a tech tower upgrade?

### Narrative
- ~~**The robot's arc:** Does it ever realize they're not servers? Or is the comedy that it never does?~~ **RESOLVED: Never. See `narrative.md`.**
- **Other datacenters:** Are there other robot arms out there? Could multiplayer be framed as different datacenters communicating?
- **Seasons/weather:** Do they affect gameplay mechanically or just aesthetically?

### Technical
- **Emergence viability:** True emergence is hard. Simpler rule sets create more emergent behavior than complex ones. What's the minimal desire system that produces interesting behavior?
- **Scale:** "Thousands of kittens" has rendering implications. What's the actual target? Hundreds visible, thousands implied?
- **Multiplayer architecture:** How much state actually needs syncing? Can neighbor effects be approximated rather than simulated?

---

## Data Schema

Covered by rule files: `animal-ai.md` (entity state, advertisements, desire config), `scene-tree.md` (node hierarchy), `viewport-lod.md` (heat grid, spatial layout), `save-system.md` (save payload), `file-structure.md` (directory tree).
