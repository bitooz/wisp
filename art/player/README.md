# The kid (the player)

The player's own body, from Codex's picture (`refs3d/player-human.png`): a kid with a lantern, in the same
style as Mo and Bo, on the same skeleton and clips (`art/pals`). `scripts/kid.gd` plays it. It isn't in
the game yet: the light (Wisp) is still "you", and swapping the kid in is left to the game's side.

| File | Shape | Triangles | Bones | Texture | Size |
| --- | --- | ---: | ---: | --- | ---: |
| `player.glb` | Hunyuan3D-2.1, seed 7 | 11,100 | 23 + lids, lantern, flame | 2048² (ETC2 on Android) | 1.9 MB |

- **Picking** (`docs/`):
  - **Candidates:** Microsoft TRELLIS.2-4B (MIT) at 1024³ and 1536³, seeds 1 to 4 each, and Tencent
    Hunyuan3D-2.1, seeds 1234, 7 and 42 (the best two by how well the front silhouette covers the
    picture's, 0.884 and 0.879, painted). All from the same cut-out, on a rented RTX 6000 Ada.
  - **As they came** (`candidates.jpg`, `candidates-1536.jpg`):
    - **TRELLIS.2:** the sharper shapes and cloth, but black hair (the picture's is dark brown), the
      lantern's glass unlit, and the faces smudged; at 1024 seeds 2 and 3 painted the jacket blue.
    - **Hunyuan3D-2.1:** the picture's colours (the brown hair, the teal jacket, the lit lantern),
      softer cloth.
  - **Faced and rigged, in the game's light** (`faces.jpg`): every candidate got the picture's own face
    and the rig, as Mo and Bo did. TRELLIS.2's texture atlas is in hundreds of small islands, and
    bringing its mesh down to the phone's budget tears it (shards of skin on the shorts and the jacket).
    Hunyuan's seed 7 is the closest: clear eyes, the strand of hair up top, no seam (seed 42 has a pale
    one at the hairline).
- **Placement:** Y up, standing on y = 0, centred under the hips, facing +Z; 1.45 tall.
- **Face, eyelids, skeleton, clips:** as Mo and Bo's (`art/pals/README.md`), the joints picked on the
  picture (`art/pals/pipeline/player-keypoints.json`).
- **The lantern:** everything in its box on the picture is on its own bone, `lantern` (a child of the
  left hand, from the handle down to the flame), and a bone `flame` marks the flame. The glass round
  the flame is marked to glow: the vertex colour's red, which `shaders/pal.gdshader` lights by its `glow`.
  In the game (`kid.gd`) the lantern hangs straight down from the hand and swings as a pendulum when the
  hand or the body moves; `Kid.lantern` follows the flame, for the light.
- **In the game** (`scripts/kid.gd`): move the node (position and rotation.y) and its legs keep up:
  `scripts/gait.gd` blends idle, walk, jog and run by speed, holds the feet where they land, and leans
  it into turns, starts and stops. Also `talk`, `look_at_point` and `gesture()` (jump, pick_up, wave,
  point), and blinking.
- **Licence:** made with Tencent Hunyuan3D-2.1 under the Tencent Hunyuan 3D 2.1 Community License (no
  rights claimed in what it makes; it doesn't cover the EU, the UK or South Korea). Skeleton and clips:
  Quaternius's Universal Animation Library, CC0.

## Remaking it

As Mo and Bo (`art/pals/README.md`), with `player` for the name and 1.45 for the height. TRELLIS.2's
candidates come from `pipeline/setup_trellis.sh` and `pipeline/trellis.py` on the same machine
(alongside Hunyuan's `setup.sh`; a 48 GB card runs both at once), and `pipeline/glb2obj.py` makes each
into the `textured.obj` the rest takes. Two of the models TRELLIS.2 asks for are gated on Hugging Face
(DINOv3 and RMBG-2.0), so it loads an open copy of DINOv3 and gets Hunyuan's cut-out instead.
