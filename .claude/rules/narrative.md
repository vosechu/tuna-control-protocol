---
paths:
  - "mods/tcp_base/**"
  - "**/*.json"
  - "**/locale/**"
---

# TCP Narrative Design — Parcel's Spec

---

## The Robot's Arc (LOCKED)

**Decision (2026-03-29): The robot never gains self-awareness.**

The robot arm never realizes these are animals. Not in a late-game reveal, not in a post-credits beat, not ever. The comedy works precisely because the gap between reality and interpretation is permanent — the robot is an infinitely earnest caretaker that will go to its grave believing it maintained the most temperamental, high-maintenance servers ever manufactured. If it ever "gets the joke," the joke is over.

The robot can get more sophisticated in its misunderstandings — "These servers appear to have developed a rudimentary social hierarchy" — but it never crosses into self-awareness.

---

## Animals Leaving and Returning

**Decision (2026-03-29): Animals that wander off are not lost. They are visiting.**

When an animal's higher-order needs go unmet for long enough, it wanders toward the edge of the screen with distinct "goodbye for now" body language — a slow walk, a pause, a look back. The robot logs it as a device going into low-power standby or being transferred to another rack for diagnostics. The animal's name and portrait move to a "roaming" section of the device registry, grayed out but visible.

If conditions later improve, the animal reappears at the edge, sniffing cautiously. The robot logs: "Device [NAME] returning from off-site maintenance. Firmware unchanged. Resuming monitoring."

This preserves "no lose condition" because:
- The animal is never dead, sold, or permanently gone
- The player sees exactly why the animal left (inspect panel shows which desires were unmet)
- The return is a reward for improving conditions
- The population counter shows "12 active / 3 roaming"

---

## Reclamation Aesthetic

**Decision (2026-03-29): The datacenter is neither wilderness nor civilization. It is something in between.**

The visual language of TCP is reclamation: human infrastructure slowly being repurposed by nature and animals. Ramps are cable trays with moss growing in the joints. Bridges are zip-tied sticks braced against rack uprights. Nesting materials include shredded cardboard, old t-shirts from a forgotten lost-and-found box, and cable insulation that peeled off in the humidity. Tuna cans, stripped ethernet cables, and faded shipping labels are not litter — they are building materials in a world where nothing is waste.

The aesthetic principle: every object was either installed by humans and is being reclaimed, or was assembled by animals from what humans left behind. Nothing looks purchased from a pet store. Nothing looks like untouched forest. The datacenter is a reef — artificial structure colonized by life, made more beautiful by the collision.

## Reclamation Growth (Plant Events)

Mechanics live in `.claude/rules/growth-system.md`. This is the voice layer.

**Voice constraint:** The robot never uses the word "plant" in its logs. It doesn't know that word. Use `DECORATIVE-GROWTH-NN`, `BIOLOGICAL-ARTIFACT-NN`, or `UNSCHEDULED-FLORA`. Player-facing UI (inspect panel) may say "plant."

**On first plant spawn (the robot logs it as hardware anomaly):**

> `[NOTE] UNIT-S04 is producing unauthorized biological output. Green. Soft. Non-responsive to ping. Best hardware match: a 'houseplant' (confidence 3%). Adding to inventory as DECORATIVE-GROWTH-01. UNIT-S04 appears unbothered. Will continue monitoring.`

**On plant despawn (cats abandoned the server long enough for reclamation.seconds to decay):**

> `[LOG] DECORATIVE-GROWTH-01 has gone offline. UNIT-S04 resuming standard operations. I will miss it.`

The last line is the whole reclamation arc in six words. **Required, not optional.**

Growth IDs are sequential (`DECORATIVE-GROWTH-01`, `-02`, ...) assigned on spawn and retained through the despawn log. Server IDs are rendered as `UNIT-S%02d` against the entity ID.

---

## Device Naming Convention

Every animal receives a two-part identifier from the robot's device registry:

**Format:** `UNIT-[species prefix][sequential number]` + an earned nickname based on observed behavior (the robot's misinterpretation of what it witnessed).

| Registry ID | Nickname | What the robot observed | What actually happened |
|---|---|---|---|
| UNIT-C01 | "The Founder" | First device to initialize in this facility | Momma cat was first to arrive |
| UNIT-C03 | "Surge Protector" | Consistently positioned between high-thermal devices and small units during power fluctuations | She sleeps between kittens and the server fan to block the draft |
| UNIT-F01 | "The Inspector" | Observed full maintenance cycle at close range, then departed without collecting output | Ferret watched robot arm open a can, then wandered off |
| UNIT-C01b | "Cable Tester" | Repeatedly disconnects and reconnects data links | Kitten keeps unplugging the ethernet cable |
| UNIT-F02 | "Cache Builder" | Accumulates static discharge artifacts in unauthorized storage locations | Ferret hoards furballs behind the racks |

Nicknames are permanent once assigned. Surfaced in inspect panel and robot log entries.

---

## Robot Sound Interpretation Table

| Actual sound | Robot logs it as |
|---|---|
| **Purring** (content) | "Sustained disk I/O activity. Healthy spindle resonance." |
| **Purring** (fading) | "Disk I/O degrading. Spindle resonance thinning. Possible bearing wear." |
| **Mewing** (kitten, hungry) | "Small device emitting carrier negotiation signal. Requesting data from parent device." |
| **Meowing** (adult, demanding) | "Device broadcasting on open channel. Priority: HIGH. Payload: unreadable. Repeating." |
| **Dooking** (ferret, happy) | "Rapid burst-mode packet transmission. Non-standard protocol." |
| **Hissing** (cat, annoyed) | "CRITICAL: Device emitting electromagnetic interference. Possible short circuit." |
| **Can scraping** (ferret dragging) | "Unscheduled hardware migration in progress. Device relocating unmarked inventory." |
| **Feather fluttering** | "Loose component detected in airflow system. Intermittent obstruction." |
| **Yawn-squeak** (stretch) | "Device performing POST (Power-On Self-Test). All subsystems nominal." |
| **Dead silence** (ferret dead sleep) | "WARNING: Device has gone unresponsive. No thermal change. Pinging... no response. Scheduling physical inspection." |

---

## Robot Log: First Device Arrival (Layer 1)

> `[00:00:04] SCAN: Movement detected in sector A. Object is warm, self-propelled, and does not match any known hardware profile. Classifying as UNKNOWN MOBILE DEVICE.`

> `[00:00:18] NOTE: Unknown device is pacing. Possibly searching for an available rack slot. No slots currently configured for this form factor.`

> `[00:00:47] ALERT: Unknown device producing audible output. 300-600Hz, intermittent, rising inflection. Best match: legacy modem negotiation (14% confidence).`

> `[00:01:12] ADVISORY: Unknown device making contact with undeployed packaging (CARDBOARD-001). Pawing at enclosure walls. Possible interpretation: device requesting deployment. Highlighting enclosure for operator action.`

> `[00:01:38] LOG: Operator has deployed CARDBOARD-001 to Rack 03, slots 1-3.`

> `[00:02:04] LOG: Unknown device has entered enclosure. Circling... circling... Device has powered down into compact configuration. Audible output changed: low-frequency sustained hum, 25-30Hz. Interpreting as healthy disk activity. Classifying as UNIT-C01.`

> `[00:02:31] STATUS: UNIT-C01 passed initial health check. IOPS: low but steady. Weight: 4.2kg. Note: weight seems high for this chassis class. Will continue monitoring.`

---

## The Weight Anomaly (Pregnancy Through Robot's Eyes)

The robot does not know what pregnancy is. It knows what weight is.

> `UNIT-C01 weight: 4.2kg → 4.4kg → 4.7kg → 5.1kg. Trend: monotonically increasing. Possible causes: thermal expansion (unlikely), firmware bloat, or fluid retention in cooling system.`

> `UNIT-C01 weight: 5.3kg. Diagnostic inconclusive. Device is warm, producing nominal IOPS, and resists physical inspection. Note: device has begun "nesting" behavior — rearranging thermal insulation media within chassis. Purpose unknown.`

When kittens are born:

> `ALERT: UNIT-C01 weight dropped from 5.8kg to 4.1kg. Multiple new thermal signatures detected in chassis. 1... 2... 3... 4 additional devices? UNREGISTERED HARDWARE DETECTED. They were not delivered. They were not installed. They appear to have been MANUFACTURED INSIDE THE CHASSIS. Reclassifying event as: SPONTANEOUS DEVICE PROLIFERATION.`

> `New entries: UNIT-C01a, UNIT-C01b, UNIT-C01c, UNIT-C01d. All producing faint high-frequency audio output. IOPS: negligible. Monitoring.`

---

## Robot Log: First Ferret Encounter

> `SCAN: Movement detected in auxiliary conduit B-7. Does not match any registered device. Device is warm-blooded, quadrupedal. Initial match: server (UNIT-C class). Confidence: 22%. Device is too long. Significantly too long.`

> `CLASSIFICATION ATTEMPT: Length-to-width ratio: 6:1. Standard servers are approximately 2:1. Closest hardware match: 48-port patch panel, if a patch panel could bend in the middle and also run.`

> `NOTE: Device is on facility floor. Moving very fast. Has stopped. Moving very fast again. Acceleration profile is... inconsistent. Attempting handshake... device has bitten the diagnostic probe.`

> `BEHAVIORAL ANALYSIS: Device is now upside down. Device is now right-side up. Device is producing rapid percussive audio bursts (see: unknown protocol, ref DOOK-001). Device has located the static discharge artifact pile and is... rolling in it?`

> `ALERT: Device has made physical contact with UNIT-C03. UNIT-C03 responded with brief electromagnetic interference burst [HISS protocol]. Device retreated 0.3 meters, then immediately re-approached. This device does not follow standard rack etiquette.`

> `CLASSIFICATION RESULT: Cannot classify as UNIT-C class. Creating new device class: UNIT-F. Properties: elongated, highly mobile, unpredictable I/O patterns, produces unrecognized audio protocols, does not respond to diagnostic handshakes, appears to operate without a scheduler. Registering as UNIT-F01. Nickname pending.`

> `ADDENDUM: UNIT-F01 has discovered the tuna can inventory and is dragging CONTAINER-014 across the floor. Purpose: unknown. Destination: unknown. I do not understand this device. But it is warm and it is here, so it is mine to look after. Resuming monitoring.`

*The last line is the robot's entire philosophy in one sentence.*

---

## Robot Satisfaction Interpretation

The robot maps animal satisfaction to system health levels:

| Actual State | Robot Reads As |
|---|---|
| Content | NOMINAL |
| Restless | ADVISORY |
| Uncomfortable | DEGRADED |
| Unhappy | CRITICAL |

Hysteresis lag confuses it: "Device 7 returned to NOMINAL but latency to resume IOPS was 4x expected. Possible sticky cache."

Each tier queryable as a named label ("content," "restless," "thriving") via inspect action for accessibility.

---

## Robot Cable Interpretation

The robot doesn't know cables are cables. It records them as voluntary "harmonic bridges" the devices negotiated among themselves, and it's flattered that the facility is self-organizing.

| Player action | Robot logs |
|---|---|
| First cable ever connected | "New harmonic bridge detected in sector. I did not initiate this. The devices are coordinating. Excellent." |
| Routine connect | "UNIT-T## harmonic coupled to acoustic source UNIT-H##. Spindle resonance routing nominal." |
| Reconnect to a different HUM (same tick disconnect + connect) | "UNIT-T## re-coupled through alternate bridge. Previous carrier retired." |
| Bulk connect burst (> 3 in a tick) | "Multiple harmonic bridges established simultaneously. Topology unexpectedly rich. Recording for review." |
| Disconnect (pickup or delete) | "UNIT-T## lost harmonic link to UNIT-H##. Servo torque reduced. Apologizing to nearby devices." |

The robot never blames the player for disconnects. The servos apologize to the neighbors. The cable was never a cable; it was a volunteer.
