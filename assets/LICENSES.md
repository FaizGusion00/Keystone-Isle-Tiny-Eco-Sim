# Third-party & generated asset licenses

| Asset | Path | Source | License |
|---|---|---|---|
| Inter (variable) | `assets/fonts/Inter.ttf` | Google Fonts / rsms/inter | SIL Open Font License 1.1 (`assets/fonts/OFL-Inter.txt`) |
| Fraunces (variable) | `assets/fonts/Fraunces.ttf` | Google Fonts / undercasetype/Fraunces | SIL Open Font License 1.1 (`assets/fonts/OFL-Fraunces.txt`) |
| Lucide icons v1.64.0 (subset, recoloured white; `star-fill.svg` is Lucide `star` with a fill) | `assets/icons/*.svg` | https://lucide.dev (lucide-static) | ISC (`assets/icons/LICENSE.txt`) |
| Tree, building, crop, animal & FX sprites (atlas), cloud/raindrop textures | `assets/art/` | Original vector art (SVG source inside `tools/art/make_atlas.py`), rasterised and packed by that script (this repo) | CC0 1.0 (public domain dedication) |
| Terrain, water & sway shaders | `shaders/`, `scripts/world/world_view.gd` | Original (this repo), drawn procedurally at runtime | Same as project code |
| Sound effects & ambience/music loops | `assets/audio/` | Original, synthesized from scratch (no samples) by `tools/audio/make_audio.py` (this repo; numpy + ffmpeg/libvorbis) | CC0 1.0 |
| Game content data (mutators, species, codex, cosmetics, modes) | `data/*.json` | Original (this repo) | Same as project code |

All 199 files in `assets/icons/` were checked by name against lucide-static 1.64.0 on 2026-10-30
(`icon-nodes.json` plus its alias files such as `home`, `trash-2`, `circle-help`); `star-fill.svg` is the one
modified icon. `ContentDB.validate` makes sure every icon named in `data/*.json` exists here.
