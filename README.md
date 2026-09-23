# Arcaneum

An original 3D open-world magic-academy RPG, built for Unreal Engine 5. Structurally inspired by Hogwarts Legacy (hub school → open-world region unlocks → house/faction system → companion-driven main quest → moral-choice antagonist arc) — **fully original IP**: no Harry Potter/Wizarding World names, characters, locations, or terminology anywhere in this project. See `Docs/STORY_BIBLE.md` for why that matters and what replaces it.

## What's actually in this repo right now

This was built in a cloud CLI session with no GPU and no Unreal Editor available — so it contains everything that's expressible as text (design docs, C++ gameplay systems, project scaffold) and nothing that requires the editor GUI (meshes, animations, materials, levels, VFX). Concretely:

- **`Docs/`** — story bible, world/faction reference, full spell list with balancing numbers, and a mission-by-mission main quest outline (14 missions across 3 acts).
- **`Source/Arcaneum/`** — compilable-against-UE5.4-API C++ gameplay systems: spell casting (mana/cooldowns/data-driven spell definitions/projectiles), a data-table-driven quest state machine, branching dialogue, four-faction reputation tracking, a save-game payload struct, the player character (Enhanced Input-based movement/casting), and the game mode.
- **`Config/`** — minimal `DefaultEngine.ini`/`DefaultGame.ini` so the project opens with sane defaults.
- **`Content/`** — empty except for folder structure and `.gitkeep` placeholders. Binary Unreal assets (`.uasset`/`.umap`) can't be authored as text.
- **`Arcaneum.uproject`** — targets Unreal Engine 5.4.

**Honest status: this is an unopened, uncompiled project.** No UE5 instance has built this code or run it. It's written to match documented UE5.4 C++ conventions (verified against Epic's API patterns for Enhanced Input, `UPrimaryDataAsset`, `UGameInstanceSubsystem`, `FTableRowBase`, etc.), but the first thing to do locally is open it and fix whatever the compiler finds — treat that as expected, not a sign anything went wrong.

## Prerequisites (do this first, on your own machine)

1. Install **Unreal Engine 5.4+** via the Epic Games Launcher (or build from source via the [Unreal Engine GitHub](https://github.com/EpicGames/UnrealEngine) if you're enrolled in Epic's GitHub program).
2. Install **Visual Studio 2022** (Windows, with the "Game development with C++" workload) or **Xcode**/a configured toolchain (Mac/Linux) — required to compile the C++ module.
3. Free disk space: Epic's own hardware/software specification page recommends **~100GB free on an SSD** for a full engine + project setup (the editor binaries alone are ~30-50GB; the rest is derived data cache, intermediate build files, and project content) — this is why the project couldn't be built out in the cloud session that produced this code. [Epic's official spec page](https://dev.epicgames.com/documentation/en-us/unreal-engine/hardware-and-software-specifications-for-unreal-engine).
4. A GPU with DirectX 12 support and 6GB+ VRAM (Epic's recommended minimum).

## Opening the project

1. Right-click `Arcaneum.uproject` → **Generate Visual Studio project files** (Windows) or run `UnrealBuildTool` equivalently on Mac/Linux.
2. Open the generated `.sln`/workspace, or just double-click `Arcaneum.uproject` — UE5 will offer to build missing modules automatically the first time.
3. Expect compile errors on the first attempt. Nobody has compiled this against a real engine install yet; work through them class by class — the code was written against documented 5.4 APIs but small signature drift between engine point releases is normal and expected.

## The C++/Blueprint split (how you actually build the game from here)

Real UE5 productions split work this way, and this project assumes you will too:

- **C++ (`Source/Arcaneum/`, done)** owns gameplay *rules*: how spells cost mana and go on cooldown, how quests advance, how dialogue branches, how faction reputation is tracked, what gets saved.
- **Blueprints + assets (`Content/`, not started)** own *presentation*: which mesh a character uses, which animation plays when a spell is cast, what a spell's particle effect looks like, how a level is laid out.

Concretely, for each C++ base class you'll create a Blueprint child in `Content/Blueprints/` (e.g. `BP_ArcaneumCharacter` extends `AArcaneumCharacter`) and assign the asset-reference properties that are deliberately left blank in code:
- `AArcaneumCharacter`: skeletal mesh, `DefaultMappingContext` + the six `UInputAction` properties (create these as Input Action/Input Mapping Context assets via right-click → Input in the Content Browser — Enhanced Input assets are binary and can't be authored as text).
- `USpellDefinition` (create one data asset instance per spell in `Docs/SPELL_LIST.md`): `CastMontage`, `CastEffect` (Niagara system), `CastSound`, and for projectile spells, a `ASpellProjectileBase` Blueprint child with a mesh/trail assigned.
- `UDialogueComponent` / `UQuestManagerSubsystem`: create `DataTable` assets using row structs `FDialogueLine` and `FQuestDefinitionRow` respectively, and author the actual mission/conversation content from `Docs/QUEST_OUTLINE.md` into them.

## Asset pipeline (licensed packs — the decision already made for this project)

Since hand-sculpting AAA character models/animations isn't something producible in a coding session, source them commercially:
- **Animation:** [Mixamo](https://www.mixamo.com) (free, Adobe-owned) for rigged humanoid locomotion/combat/cast animations — the standard free starting point for indie UE5 projects.
- **Characters/environments:** [Fab](https://www.fab.com) (Epic's unified marketplace, formerly Unreal Marketplace + Sketchfab Store + Quixel), or [Synty Studios](https://syntystore.com)' POLYGON packs if you want a cohesive stylized-low-poly look — a popular, budget-realistic choice for solo/small-team Steam titles because it sidesteps the "mismatched asset flip" look that hurts a lot of asset-pack-built indie games.
- **License check before shipping:** every asset pack's EULA needs to explicitly permit commercial/Steam redistribution. Marketplace/Fab standard licenses generally do; double-check anything sourced elsewhere (itch.io, free model sites) individually.

## Steam publishing facts (verified, not guessed)

- Steam Direct's submission fee is **$100 per app, one-time, recoupable** once the game reaches **$1,000 in adjusted gross revenue** on the store — refunded as a line item in a later payment report, not upfront. [Steamworks partner documentation](https://partner.steamgames.com/doc/gettingstarted/appfee).
- You'll need a Steamworks account, tax/banking interview, and store page assets (capsule images, trailer, screenshots) before submission; Valve's review window is typically about two weeks minimum before release once a build is uploaded.
- **IP check:** nothing in this repo references Harry Potter/Wizarding World IP. Keep it that way — nothing borrowed from it can go on a store page, in marketing, or in the game itself if this is meant to actually publish.

## What's deliberately not started yet (realistic scope check)

"Huge, Hogwarts-Legacy-quality" is a ~450-person, multi-year, hundred-million-dollar production (Avalanche Software). This scaffold is a realistic starting *skeleton*, not a finished game. Not yet built, and each is a real chunk of work:
- Any actual level geometry, lighting, or the open-world regions described in `Docs/WORLD_AND_FACTIONS.md`.
- UMG UI (HUD, dialogue box, quest log, spell wheel) — components broadcast the delegates a UI would bind to, but no widgets exist.
- Save/load manager gluing `UArcaneumSaveGame` to the quest/spell/faction systems (the struct exists; nothing populates or reads it yet).
- Combat AI/enemy classes, the Draughts (potion-equivalent) crafting system mentioned in the story bible, companion AI.
- Everything in `Content/`.

## Repo layout
```
Arcaneum.uproject
Source/Arcaneum/
  Core/            -- ArcaneumGameMode
  Player/          -- ArcaneumCharacter (movement, Enhanced Input, spell-cast input)
  Spells/          -- SpellDefinition (data asset), SpellCastingComponent, SpellProjectileBase
  Quests/          -- QuestTypes, QuestManagerSubsystem
  Dialogue/        -- DialogueTypes, DialogueComponent
  Progression/     -- FactionReputationComponent (the four Orders)
  SaveSystem/      -- ArcaneumSaveGame
Config/            -- DefaultEngine.ini, DefaultGame.ini
Content/           -- empty scaffold, see Content/README_ContentFolder.md
Docs/
  STORY_BIBLE.md
  WORLD_AND_FACTIONS.md
  SPELL_LIST.md
  QUEST_OUTLINE.md
```
