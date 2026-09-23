# Content/ folder

This folder ships empty on purpose. Binary Unreal assets (`.uasset`/`.umap` — meshes, animations, materials, Blueprints, maps, Niagara systems) can't be authored as text, so they aren't produced by this coding session. The subfolders below are placeholders matching the intended content structure; populate them from the Unreal Editor once you have licensed asset packs imported (see the root `README.md` for the recommended pipeline: Mixamo for animation, Synty/Marketplace/Fab for models).

- `Characters/` — player + NPC skeletal meshes, materials, animation blueprints
- `Environments/` — modular kit meshes for Highhollow, Thistlewick, Larkmoor Fens, Ashcombe Highlands, Drowned Vale
- `VFX/` — Niagara systems for spell casts/impacts
- `Audio/` — cast/impact SFX, ambient, music
- `UI/` — UMG widget blueprints (dialogue box, quest log, spell wheel, HUD)
- `Maps/` — level files (`.umap`)
- `Blueprints/` — Blueprint subclasses of the C++ base classes in `Source/Arcaneum` (this is where you assign meshes, Input Actions, Anim Montages, and Niagara systems to the gameplay logic — see root README's "C++/Blueprint split" section)
