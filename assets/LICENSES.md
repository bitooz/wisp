# Third-party assets

Everything here is free to use; each pack's own licence file sits beside it.

| Folder | What | Author | Licence | Source |
|---|---|---|---|---|
| `kenney_nature/` | Nature Kit 2.1: trees, bushes, flowers, grass tufts, rocks, stones, lily pads, logs, stump, mushrooms, reeds, hanging moss (only the models used) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/nature-kit |
| `kaykit_dungeon/` | Dungeon Remastered 1.0: floor tiles, walls, pillars, rubble, barrels, crates, keg, banners, candles, mounted torch, broken shield, texture atlas (only the models used) | Kay Lousberg (kaylousberg.com) | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 |
| `quaternius_nature/` | Stylized Nature MegaKit (free version): trees, pines, bushes, ferns, flowers, clover, grass tufts, mushrooms, pebbles, rocks; textures downscaled for phones. `impostors/` are our own renders of its trees (the far LOD) | Quaternius (quaternius.com) | CC0 1.0 | https://quaternius.itch.io/stylized-nature-megakit |
| `audio/kenney/` | Footsteps (grass, concrete), soft impacts, bell, clicks, door (from Impact Sounds, Interface Sounds, RPG Audio) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds, /interface-sounds, /rpg-audio |
| `audio/wisp/` | Ambient loops (wind, sea, birds, crickets, cave drone and drips) and the dash whoosh, synthesised by `tools/synth_audio.py` | Wisp | CC0 1.0 | this repo |
| `terrain/grass_*` | Grass 004, packed to Terrain3D's albedo+height / normal+roughness format | ambientCG | CC0 1.0 | https://ambientcg.com/view?id=Grass004 |
| `terrain/dirt_*` | Ground 054 (the path), packed | ambientCG | CC0 1.0 | https://ambientcg.com/view?id=Ground054 |
| `terrain/rock_*` | Rock 030, packed | ambientCG | CC0 1.0 | https://ambientcg.com/view?id=Rock030 |
| `terrain/sand_*` | Ground 033 (the beach), packed | ambientCG | CC0 1.0 | https://ambientcg.com/view?id=Ground033 |
| `../addons/terrain_3d/` | Terrain3D 1.0.2 (macOS and Android arm64 libraries only) | Tokisan Games and contributors | MIT (`addons/terrain_3d/LICENSE.txt`) | https://github.com/TokisanGames/Terrain3D |
| `../shaders/terrain.gdshader` | Terrain3D's lightweight shader with the game's sky-and-ground light added | Tokisan Games, modified | MIT | as above |
| `../fonts/Nunito.ttf` | Nunito variable font | The Nunito Project Authors | SIL OFL 1.1 | https://github.com/googlefonts/nunito |

Models keep their geometry; the game swaps their materials for its own lit shader in the mock's palette (`scripts/props.gd`).

## Voices

- Mo's and Bo's voices are public voice models on Fish Audio ("little girl" `085081f7c97c4c478f70f59bd8049f2a`
  and "boy" `d9ce1833c191476db346efb50aa20722`), used through Fish Audio's API from the Worker; nothing of
  them ships in the game. Lines the game has heard are cached on the device (`user://voice`).
- `tools/voice/*.wav` (test lines for the self-test, not used in play) were made with macOS `say` (Samantha).
