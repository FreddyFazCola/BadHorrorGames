# Arcaneum — World & Factions Reference

## Geography
- **Aldreth** — the continent. Only referenced, never visited directly.
- **Caldenwyrd** — the playable region: highland coast, moorland, sea cliffs, one flooded ruin.
- **Wrynmoor** — the headland Highhollow Castle sits on.

### Open-world zones (unlock order matches main-quest progression, Hogwarts-Legacy-style gating)
1. **Highhollow Grounds** (hub, available from mission 1) — castle interior, courtyards, the four Order common rooms, greenhouses, dueling yard.
2. **Thistlewick** (unlocked act 1, mission 3) — market town: shops for spell components, apparel, a tavern used for side-quest hooks and companion banter scenes.
3. **Larkmoor Fens** (unlocked act 1, mission 4) — wetlands south of the Academy; home to the first Ashbound waystation and several Kindred settlements.
4. **Ashcombe Highlands** (unlocked act 2, mission 6) — mountainous, home to Corvin Ashworth's family estate and a disused Crown wand-licensing outpost (Kindred subplot hub).
5. **The Drowned Vale** (unlocked act 3, mission 11) — a sunken pre-Sundering ruin, reachable only by Deep Weave-empowered traversal; final act's primary location.

## Factions

### The Four Orders
Sorting happens narratively in mission 1 based on a short dialogue-driven "trial" (skill-check-free, personality-based, same spirit as the Sorting Hat but original mechanic: a trio of NPC proctors debate the player's choices in front of them). Order choice affects: common room access, one exclusive companion, one exclusive Order-flavored spell in each tier, and the Order loyalty questline.

- **Order of Ember** — fire, courage, impulsiveness. Notable NPCs: Instructor Brackwater (honorary), duelist rival Isra Vance.
- **Order of Deep** — water, wisdom, secrecy. Provost Marrow's Order. Strongest lore/investigation questline.
- **Order of Root** — earth, loyalty, stubbornness. Strongest herbology/crafting side content, ties into potion-equivalent "Draughts" system.
- **Order of Gale** — air, ambition, pride. Corvin Ashworth's Order. Strongest political/Kindred-licensing side content.

### Kindred Political Triangle
- **The Concord** (moderate reform) — quest-giver hub in Larkmoor Fens; rewards favor legal/social solutions.
- **The Ashbound** (militant) — antagonist faction; field bosses, hideouts, and Mother Cael's endgame plotline.
- **Crown Licensing Authority** — status-quo institution the player can reform, ignore, or help entrench, depending on choices in the Ashcombe Highlands arc.

## Companions (party/relationship system)
1. **Fenn Oakstave** (Kindred, disguised) — full main-quest-integrated companion arc.
2. **Isra Vance** (Order of Ember rival-turned-ally, combat-focused) — recruited via Ember loyalty questline ("The Forge-Tower Wager," see Docs/QUEST_OUTLINE.md). Personal quest, **"The Duelist's Debt"**: Isra's reputation for recklessness traces back to a duel that went wrong and cost someone their place at the Academy; she wants to make it right before Act 3, and asks the player to help track that person down in Thistlewick.
3. **Bren Calder** (Order of Root, crafting/Draughts specialist) — recruited via Root loyalty questline ("Roots That Hold"). Personal quest, **"What the Greenhouse Remembers"**: the blight from the Root loyalty quest wasn't natural -- it's the same strain of corruption described in the Drowned Vale, meaning it reached the greenhouse decades before the player ever sensed the Deep Weave. Bren wants to know how, and the answer ties back to Provost Marrow's generation. Mechanically, this is where the player first unlocks `DraughtRecipe`/`DraughtBrewingStation` (see `Assets/Scripts/Progression/`).
4. Two romanceable companions among the above, gated by dialogue choices across acts 1–2 (kept lightweight: a handful of flagged conversations, not a full relationship-meter system, to stay within realistic scope).

## Collectibles / world-building systems
- **Sundering Shards** — ~40 collectible lore fragments scattered across zones, each unlocking a short world-history log entry (mirrors HL's Field Guide Pages).
- **Beast Taming (stretch goal, not in initial scope)** — noted here as a possible post-launch/DLC-scale system; not part of the core build plan below.
