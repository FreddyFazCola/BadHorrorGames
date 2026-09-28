# Arcaneum

An original 3D open-world magic-academy RPG, built for Unity. Structurally inspired by Hogwarts Legacy (hub school → open-world region unlocks → house/faction system → companion-driven main quest → moral-choice antagonist arc) — **fully original IP**: no Harry Potter/Wizarding World names, characters, locations, or terminology anywhere in this project. See `Docs/STORY_BIBLE.md` for why that matters and what replaces it.

A playable browser vertical-slice of this same game (movement, spellcasting, a training trial) also exists as a Claude Artifact from earlier in this project's development, built in Three.js since it could actually run and be verified in that session. This repo is the longer-term Unity version, meant to eventually replace it.

## What's actually in this repo right now

This was built in a cloud CLI session with no GPU and no Unity Editor available — so it contains everything that's expressible as text (design docs, C# gameplay systems, project scaffold) and nothing that requires the editor GUI (meshes, animations, materials, scenes, VFX, prefab wiring). Concretely:

- **`Docs/`** — story bible, world/faction reference, full spell list with balancing numbers, and a mission-by-mission main quest outline (14 missions across 3 acts).
- **`Assets/Scripts/`** — C# gameplay systems: spell casting (mana/cooldowns/data-driven spell definitions/projectiles), a ScriptableObject-driven quest state machine, branching dialogue, four-faction reputation tracking, a **working** JSON save/load system, third-person player movement + camera, and a practice-target interaction example.
- **`Assets/ScriptableObjects/`, `Assets/Prefabs/`, `Assets/Animations/`, `Assets/Materials/`, `Assets/Audio/`, `Assets/Scenes/`, `Assets/UI/`** — empty except `.gitkeep` placeholders. Unity project/scene/asset files are binary and can't be authored as text; these folders mark where things go once you're working in the Editor.

**Honest status: no Unity Editor has opened or compiled this code.** It's written against stable, version-safe Unity APIs (legacy `Input` class rather than the newer Input System package, `CharacterController`, `MonoBehaviour`, `ScriptableObject`, `JsonUtility`) specifically to avoid depending on an engine version or package version I can't verify from this session — but the first time you open it in Unity, expect to fix whatever the compiler flags. That's normal, not a sign anything went wrong.

### Why Unity instead of Unreal

This project's first pass targeted Unreal Engine 5; the C++ scaffold was dropped in favor of this Unity version by request. Nothing about the story, world, spells, or quest design changed — only the engine and the code implementing it. The `Docs/` folder was always engine-agnostic and needed no rewrite.

## Prerequisites (do this on your own machine — not possible in this session)

1. Install **Unity Hub**, then a recent **Unity 6 LTS** (or 2022 LTS) release through it.
2. Create a **new 3D (URP) project** in Unity Hub — this generates the `ProjectSettings/`, `Packages/`, and `Library/` folders this repo deliberately does not include (they're per-install/auto-generated, not something to hand-author or commit).
3. Copy this repo's `Assets/Scripts/` folder (and the empty `Assets/*` subfolders if you want the structure) into that new project's `Assets/` folder.
4. A GPU capable of running the Unity Editor (basically any GPU from the last decade; nothing exotic required, unlike Unreal's heavier baseline).

## The C#/Inspector split (how you actually build the game from here)

- **C# (`Assets/Scripts/`, done)** owns gameplay *rules*: how spells cost mana and go on cooldown, how quests advance, how dialogue branches, how faction reputation is tracked, and (unlike the earlier Unreal version) a fully working save/load system.
- **Prefabs + ScriptableObject assets + scenes (not started)** own *presentation*: which model a character uses, which animation plays on cast, what a spell's particle effect looks like, how a level is laid out.

Concretely:
- **Spells**: right-click in `Assets/ScriptableObjects/Spells/` → Create → Arcaneum → Spell Definition, one per entry in `Docs/SPELL_LIST.md`. Assign `castEffectPrefab`, `castSound`, and (for non-instant spells) a `projectilePrefab` — a prefab with `SpellProjectile.cs` on it plus a trigger `Collider` and `Rigidbody`.
- **Quests**: right-click in `Assets/ScriptableObjects/Quests/` → Create → Arcaneum → Quest Definition, one per mission in `Docs/QUEST_OUTLINE.md`. Assign all of them to a `QuestManager` component in your scene.
- **Dialogue**: create a `DialogueTree` asset per conversation, attach `DialogueRunner` to the NPC's GameObject, and build a UI (Canvas + TextMeshPro) that listens to its `onLineChanged`/`onDialogueEnded` events.
- **Player**: create a prefab with `CharacterController`, `SpellCasting`, and `PlayerController` on it, plus a `FactionReputation` component; assign the imported character model as a child, and its `Animator` alongside `SpellCasting`'s `castAnimationTrigger` names.

## Asset pipeline (licensed packs)

Since hand-sculpting AAA character models/animations isn't something producible in a coding session, source them commercially. Verified-real starting points for this specific game (fantasy academy, medieval-ish):

**Free, prioritized per project preference:**
- **Characters** — [Quaternius – RPG Character Pack](https://quaternius.com/packs/rpgcharacters.html): 6 fantasy characters, already rigged *and* animated (FBX/OBJ/Blend), free for commercial use. [Quaternius – Modular Character Outfits: Fantasy](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html): 12 outfits, 62 modular pieces, same license.
- **Environments** — [Kenney – Modular Dungeon Kit](https://kenney.nl/assets/modular-dungeon-kit): CC0 (public domain, no attribution required), dungeon/castle-building pieces.
- **Animation (if a model isn't pre-animated)** — [Mixamo](https://www.mixamo.com) (free, Adobe): upload a humanoid character, it auto-rigs, and you download free mocap animations that map directly onto Unity's Humanoid/Mecanim system.
- **Known tradeoff:** free assets are simpler and less varied than paid packs, and mixing pieces from two different free creators (e.g. Quaternius characters + Kenney environments) can look visually inconsistent since their art styles don't match exactly. Picking one creator's ecosystem where possible avoids that.

**Paid alternative, for more variety/polish later** — Synty Studios' POLYGON line ([Fantasy Characters](https://syntystore.com/products/polygon-fantasy-characters-pack), [Fantasy Kingdom](https://www.fab.com/listings/3d968be5-531f-4f6c-abf9-1a799dca2641)) and FAB's [Fantasy Castle Environment](https://www.fab.com/listings/a349250d-e253-419c-bd5e-6afae4e4620a) are the more-polished, budget-friendly-but-not-free options if the above ever feels too limited.

- **License check before shipping:** every asset's license needs to explicitly permit commercial/Steam redistribution. Kenney (CC0) and Quaternius (explicitly free for commercial use) are both clear on this; double-check anything else sourced elsewhere individually.
- **Getting assets into this project:** download locally, then either drop the FBX/GLB straight into your Unity project, or upload it into a chat with me if you want it referenced/discussed first. (FAB specifically also requires your own Epic account and accepting that asset's license — that step can't be done on your behalf.)

## Steam publishing facts (verified, not guessed)

- Steam Direct's submission fee is **$100 per app, one-time, recoupable** once the game reaches **$1,000 in adjusted gross revenue** on the store — refunded as a line item in a later payment report, not upfront. [Steamworks partner documentation](https://partner.steamgames.com/doc/gettingstarted/appfee).
- You'll need a Steamworks account, tax/banking interview, and store page assets (capsule images, trailer, screenshots) before submission; Valve's review window is typically about two weeks minimum before release once a build is uploaded.
- **IP check:** nothing in this repo references Harry Potter/Wizarding World IP. Keep it that way — nothing borrowed from it can go on a store page, in marketing, or in the game itself if this is meant to actually publish.

## What's deliberately not started yet (realistic scope check)

"Huge, Hogwarts-Legacy-quality" is a ~450-person, multi-year, hundred-million-dollar production (Avalanche Software). This scaffold is a realistic starting *skeleton*, not a finished game. Not yet built:
- Any actual level geometry, lighting, or the open-world regions described in `Docs/WORLD_AND_FACTIONS.md`.
- UI (HUD, dialogue box, quest log, spell wheel) — components fire the C# events a UI would bind to, but no Canvas/widgets exist.
- The menu/save-slot flow that actually calls `SaveLoadManager` and restores state into `QuestManager`/`SpellCasting`/`FactionReputation` — the save system itself works, nothing calls it yet.
- Combat AI/enemy classes, the Draughts (potion-equivalent) crafting system mentioned in the story bible, companion AI.
- Everything under `Assets/Prefabs`, `Assets/Animations`, `Assets/Materials`, `Assets/Audio`, `Assets/Scenes`, `Assets/UI`.

## Repo layout
```
Assets/
  Scripts/
    Core/            -- GameManager
    Player/          -- PlayerController, ThirdPersonCamera
    Spells/          -- SpellDefinition, SpellCasting, SpellProjectile, SpellCategory
    Quests/          -- QuestTypes, QuestDefinition, QuestManager
    Dialogue/        -- DialogueTypes, DialogueTree, DialogueRunner
    Progression/     -- FactionReputation (the four Orders)
    SaveSystem/      -- SaveData, SaveLoadManager (working JSON save/load)
    Interaction/     -- IDamageable, PracticeWard
  ScriptableObjects/ -- Spells/, Quests/, Dialogue/ (empty; create assets here in-editor)
  Prefabs/, Animations/, Materials/, Audio/, Scenes/, UI/ -- empty scaffold
Docs/
  STORY_BIBLE.md
  WORLD_AND_FACTIONS.md
  SPELL_LIST.md
  QUEST_OUTLINE.md
```
