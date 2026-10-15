# Arcaneum — Bestiary

Enemy archetypes tied directly to `Assets/Scripts/Interaction/EnemyController.cs`. Each row is a starting point for that component's public fields on a given prefab -- balancing numbers are a first pass, not final. All are original creatures/factions; none reference existing IP. The actual visuals suggested below (`Assets/Characters/KayKitSkeletons/`) are a real, CC0-licensed, generic "skeleton warrior" archetype -- a stand-in for the Ashbound look until there's custom art direction for them, not a final design choice.

## Ashbound militants (see Docs/STORY_BIBLE.md for the faction)

| Archetype | Acts seen | maxHealth | attackDamage | chaseSpeed | attackRange | Suggested model | Notes |
|---|---|---|---|---|---|---|---|
| Ashbound Initiate | 1–2, Larkmoor Fens | 50 | 10 | 4 | 1.6 | `Skeleton_Warrior.fbx` + `Skeleton_Shield_Small_A.fbx` | Baseline melee grunt; matches `EnemyController`'s default field values exactly, so an unmodified prefab is already a valid Initiate. |
| Ashbound Warden | 2, Ashcombe Highlands | 110 | 18 | 3 | 2.0 | `Skeleton_Warrior.fbx` + `Skeleton_Shield_Large_A.fbx` + `Skeleton_Axe.fbx` | Slower, tougher; guards Ashbound waystations. Two or three per encounter, not swarms. |
| Ashbound Adept | 2–3 | 40 | — | 3.5 | 8 (matches chaseRange) | `Skeleton_Mage.fbx` + `Skeleton_Staff.fbx` | Ranged variant: rather than melee `attackDamage`, swap `DoAttack()` to call `SpellCasting.TryCastSpell` with a Binding spell instead of `IDamageable.ApplyDamage` directly -- not yet implemented, noted here as the intended extension point. |
| Ashbound Scout | side encounters | 30 | 6 | 5 | 1.4 | `Skeleton_Rogue.fbx` + `Skeleton_Blade.fbx` | Fast, low-health skirmisher; good for the "first Ashbound contact" beat in mission 4 since it can flee rather than fight if scripted to disengage below a health threshold (not yet implemented in `EnemyController`). |

## Drowned Vale hazards (Act 3 only)

| Archetype | maxHealth | attackDamage | Notes |
|---|---|---|---|
| Sundering-touched Fauna | 70 | 14 | Ordinary Tidereach wildlife warped by 300 years of proximity to the sealed Deep Weave (Docs/STORY_BIBLE.md). Not evil, not Ashbound -- environmental danger, framed in dialogue/flavor text as tragic rather than hostile-by-choice. |

## Design notes
- No enemy uses `NavMeshAgent`; `EnemyController` moves via direct Transform translation so encounters work without a baked NavMesh. Swap to NavMeshAgent per-prefab once level geometry and baked NavMeshes exist, for proper obstacle avoidance.
- `PlayerHealth.maxHealth` defaults to 100 -- against an Initiate's 10 damage per hit (1.5s cooldown), that's a forgiving ~10 hits before death, appropriate for an early-game encounter; revisit once Warding spells (damage mitigation) are balanced against this.
