# Arcaneum — Spell List & Progression

Five tiers, gated by main-quest chapter (see `QUEST_OUTLINE.md`). Four categories map directly to the `SpellCategory` enum in code: **Cantrip** (utility), **Binding** (offense/debuff), **Warding** (defense/control), **Conjury** (summon/ultimate). Each spell is authored as one `SpellDefinition` ScriptableObject asset (see `Assets/Scripts/Spells/SpellDefinition.cs`) — designers add new spells in the Unity Inspector without touching code.

Balancing numbers below are starting points for playtesting, not final.

## Tier 1 (Act 1, missions 1–3)
| Spell | Category | Mana | Cooldown | Effect |
|---|---|---|---|---|
| Lumen Spark | Cantrip | 5 | 0.5s | Small ranged light/damage bolt; also lights dark areas |
| Verdant Snare | Binding | 15 | 6s | Roots a single target in vines for 3s |
| Aegis Ward | Warding | 20 | 8s | Frontal damage-absorbing shield, 3s duration |
| — Conjury unlocks at Tier 2 — | | | | |

## Tier 2 (Act 1, mission 4 → Act 2 start)
| Spell | Category | Mana | Cooldown | Effect |
|---|---|---|---|---|
| Emberburst | Binding | 25 | 7s | Small AoE fire explosion at target point |
| Tidecall | Binding | 20 | 6s | Knockback water blast, extinguishes fire hazards |
| Stonehide | Warding | 25 | 10s | Damage reduction buff, 5s |
| Wisp Conjury | Conjury | 30 | 15s | Summons a light-wisp companion that reveals hidden objects for 10s |

## Tier 3 (Act 2, missions 6–8)
| Spell | Category | Mana | Cooldown | Effect |
|---|---|---|---|---|
| Galewalk | Cantrip | 10 | 4s | Short-range air dash, traversal + dodge |
| Ashbind | Binding | 30 | 9s | Damage-over-time curse, 4s |
| Root Wall | Warding | 30 | 10s | Raises a temporary earthen barrier, blocks projectiles/enemies |
| Deep Sight | Cantrip | 15 | 12s | Reveals Deep-Weave-marked objects/enemies through walls, 8s |

## Tier 4 (Act 2 finale → Act 3 start)
| Spell | Category | Mana | Cooldown | Effect |
|---|---|---|---|---|
| Tempest Lance | Binding | 40 | 10s | High-damage piercing line attack |
| Warding Bastion | Warding | 40 | 14s | Party-wide shield bubble, 4s |
| Sentinel Conjury | Conjury | 45 | 20s | Summons a stone guardian ally for 15s |

## Tier 5 — Deep Weave spells (Act 3 only, story-gated, not freely farmable)
| Spell | Category | Mana | Cooldown | Effect |
|---|---|---|---|---|
| Sundering Grasp | Binding | 60 | 15s | Rips a target's active shield/ward away, then deals heavy damage |
| Tidereach Cataclysm | Conjury | 80 | 30s | Room-clearing ultimate AoE, main-quest set-piece + late endgame use |
| Weavesight | Cantrip | 20 | 6s | Slows time briefly to read enemy tells (parry/dodge window extension) |

## Design notes
- Every Order grants one **Order-flavored recolor/variant** of a Tier-2+ spell (visual + minor secondary effect only, to keep balance flat across Order choice).
- Spells are unlocked via `QuestManager` completing a specific quest stage, not via a generic XP/level number — keeps spell-gating tied to story pacing (matches Hogwarts Legacy's approach of teaching spells through named quests rather than a level-up screen).
