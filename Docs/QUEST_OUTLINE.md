# Arcaneum — Main Quest Outline

14 main missions across 3 acts + epilogue. Each mission lists its core beat and the new system/spell it introduces (deliberate one-new-thing-per-mission pacing).

## Act 1 — Arrival & Awakening
1. **"Late Admission"** — Player arrives mid-term after a violent, unexplained magical episode. Meets Provost Marrow, Instructor Brackwater. Tutorial movement + first Cantrip (Lumen Spark).
2. **"The Trial of Four"** — Sorting sequence into an Order. Meets Fenn Oakstave. Unlocks Order common room.
3. **"A Free Day in Thistlewick"** — Open-world intro to the town; first Binding + Warding spells taught in a dueling-class framing.
4. **"What Fenn Is"** — Fenn's Kindred secret is revealed to the player in confidence. First Ashbound contact: a cryptic warning left for the player, not a fight. Larkmoor Fens unlocks. Tier 2 spells begin.

## Act 2 — The Widening Rift
5. **"The Ledger of Names"** — Investigate Academy records for the original Sundering-adjacent incident 30 years back; first real clue that Marrow was present.
6. **"Ashworth Hospitality"** — Visit Corvin's family estate in the Ashcombe Highlands (unlocks the region); learn the Ashworths broker Kindred wand-licenses. Corvin escalates from rival to active saboteur.
7. **Order Loyalty Quest (choice of 1 of 4, others available as side content -- see "Order Loyalty Questlines" below)** — resolves an Order-specific local problem; recruits that Order's companion.
8. **"Brackwater's Ash"** — Instructor Brackwater's Ashbound past is exposed; player chooses whether to report him or keep his secret (affects a late-game reinforcement option).
9. **"The Concord's Ask"** — Major Kindred-subplot branch point: side with Concord's legal path, tacitly back Ashworth's status quo, or start quietly arming a middle path. Sets flags used in the epilogue.

## Act 3 — The Second Sundering
10. **"What Mother Cael Wants"** — First direct confrontation with Mother Cael; she makes her case to the player directly rather than attacking. Tier 4 spells unlock.
11. **"Into the Drowned Vale"** — Traversal-heavy mission using Deep Sight/Galewalk together; Drowned Vale unlocks as an open region.
12. **"Corvin's Choice"** — Corvin's arc resolves: redemption (he helps at the climax) or betrayal (he becomes a final-act miniboss), determined by cumulative player choices in missions 6, 8, 9.
13. **"The Second Sundering"** — Mother Cael's ritual begins at the Vale's heart; large set-piece combat, Tier 5 Deep Weave spells used narratively for the first time.
14. **"What Magic Owes"** — Final confrontation and player's binary-plus-nuance choice: stop Cael by force, or offer her the reform-path the Concord asked for in mission 9 (only available if that flag was set). Multiple epilogue slides based on Order reputation + Kindred flags + Corvin's fate.

## Side content threads (non-linear, available across Act 2–3)

### Order Loyalty Questlines
One per Order; the player does one as part of the mission 7 main-quest beat and can complete the other three as side content afterward. Each recruits that Order's companion on completion.

- **Order of Ember — "The Forge-Tower Wager"**: a reckless underclassman duel ring has been running unsupervised in the west forge-tower, and someone's about to get hurt. Report it to Instructor Brackwater and shut it down (Ember respects the courage of stepping in), or take it over and referee it properly (Ember respects owning the risk instead of hiding from it) — both resolve it, the difference is what Isra Vance thinks of you afterward. Recruits **Isra Vance**.
- **Order of Deep — "The Tidecaller's Ledger"**: an upperclassman has been quietly hand-copying pages from the restricted archive wing -- the same wing tied to mission 5's Sundering-incident records. Turn them in, or hear them out and help them finish copying before they're caught. A small-scale rehearsal of the same secrecy-vs-transparency question mission 5 raises about Provost Marrow herself.
- **Order of Root — "Roots That Hold"**: a blight is killing a greenhouse plot Bren Calder has spent a year cultivating for the Draughts (potion-equivalent) program. Track the cause -- neglect, sabotage, or something that crossed over from the Larkmoor Fens -- and fix it. Recruits **Bren Calder**.
- **Order of Gale — "Wind and Rank"**: Gale's internal academic-ranking competition has turned into quiet sabotage between two rivals, one of them an Ashworth cousin. Expose the cheating (costs the cheater their rank, wins you a reputation for fairness) or use what you learn as leverage instead (wins favor with the ambitious, costs you trust with everyone else). Foreshadows the choice the player faces with Corvin himself in Act 3.

### Other side content
- ~40 Sundering Shard collectibles feeding the world-history log.
- Thistlewick shop/vendor quest hooks (lightweight, flavor-only).

## Implementation note
All of the above is authored as **data**, not hardcoded flow: `Assets/Scripts/Quests/QuestDefinition.cs` defines each quest as a ScriptableObject holding a list of `QuestStage` entries, and `QuestManager` drives runtime state from those assets. Adding/editing missions means creating/editing a Quest Definition asset in the Unity Editor, not a C# change.
