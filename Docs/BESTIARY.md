# Arcaneum — Bestiary

Enemy archetypes tied directly to `Assets/Scripts/Interaction/EnemyController.cs`. Each row is a starting point for that component's public fields on a given prefab -- balancing numbers are a first pass, not final. All are original creatures/factions; none reference existing IP.

## Ashbound militants (see Docs/STORY_BIBLE.md for the faction)

| Archetype | Acts seen | maxHealth | attackDamage | chaseSpeed | attackRange | Notes |
|---|---|---|---|---|---|---|
| Ashbound Initiate | 1–2, Larkmoor Fens | 50 | 10 | 4 | 1.6 | Baseline melee grunt; matches `EnemyController`'s default field values exactly, so an unmodified prefab is already a valid Initiate. |
| Ashbound Warden | 2, Ashcombe Highlands | 110 | 18 | 3 | 2.0 | Slower, tougher; guards Ashbound waystations. Two or three per encounter, not swarms. |
| Ashbound Adept | 2–3 | 40 | — | 3.5 | 8 (matches chaseRange) | Ranged variant: rather than melee `attackDamage`, swap `DoAttack()` to call `SpellCasting.TryCastSpell` with a Binding spell instead of `IDamageable.ApplyDamage` directly -- not yet implemented, noted here as the intended extension point. |

## Drowned Vale hazards (Act 3 only)

| Archetype | maxHealth | attackDamage | Notes |
|---|---|---|---|
| Sundering-touched Fauna | 70 | 14 | Ordinary Tidereach wildlife warped by 300 years of proximity to the sealed Deep Weave (Docs/STORY_BIBLE.md). Not evil, not Ashbound -- environmental danger, framed in dialogue/flavor text as tragic rather than hostile-by-choice. |

## Design notes
- No enemy uses `NavMeshAgent`; `EnemyController` moves via direct Transform translation so encounters work without a baked NavMesh. Swap to NavMeshAgent per-prefab once level geometry and baked NavMeshes exist, for proper obstacle avoidance.
- `PlayerHealth.maxHealth` defaults to 100 -- against an Initiate's 10 damage per hit (1.5s cooldown), that's a forgiving ~10 hits before death, appropriate for an early-game encounter; revisit once Warding spells (damage mitigation) are balanced against this.
