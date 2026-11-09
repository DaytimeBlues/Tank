# Asset provenance

5 November river pass: terrain colours and normals, bridge paint and tree silhouettes are locally authored procedural geometry and material data. The paired CPU studies are generated from project source. No external art or textures were imported. [River presentation and source notes](evidence/river-presentation-20261105/RESULT.md).

5 November roster addition: Palisade is original fictional Blender geometry with Panzer IV inspiration. [The Tank Museum's Panzer IV entry](https://tankmuseum.org/tank-nuts/tank-collection/panzer-iv/?country=all&era=all&tpage=3) is a reference for the built-up form and later long gun. No images, drawings, measurements, markings, textures or third-party meshes were imported. Editable model, GLB and deterministic generator: `docs/assets/original-tank/palisade/` and `tools/build-original-tank.py`. [Budget and provenance](evidence/palisade-20261105/RESULT.md).

| Asset | Origin | Licence/status |
| --- | --- | --- |
| Tank, range, targets, particles | Procedural geometry authored in public/game.mjs in this chat | Project source; no external model or textures |
| Shot sound | Web Audio oscillator authored in public/game.mjs | Project source; placeholder only |
| Kenney Impact Sounds | https://kenney.nl/assets/impact-sounds | Official page says CC0; candidate only, not imported |
| Three.js | npm three 0.186.1 | MIT; installed package LICENSE |
| Rapier compatibility bindings | npm @dimforge/rapier3d-compat 0.21.0 | Apache-2.0; installed package licence metadata |
| ws | npm ws 8.22.0 | MIT; installed package LICENSE |

Before asset import: record exact source URL, author, archive/file hashes, licence text, attribution requirements and modified output path. Use Blender-to-GLB for interactive meshes with separate moving parts. Keep licence evidence with shipped third-party assets.

Slice 2 adds seeded grass/mud CanvasTextures and simple rut geometry, authored locally in public/game.mjs. No downloaded image, model or additional dependency was imported.

Verified bounded local catalogue: [docs/assets/LOCAL-ASSET-CATALOGUE.md](docs/assets/LOCAL-ASSET-CATALOGUE.md). Installation, import testing and working-in-game are separate statuses.

Newbattlefield uses locally authored shared terrain/bridges/water/base markers and the same proceduraltank. Installed three0.186.1 examples/jsm/objects/Sky.js is served unchanged from node_modules under the installed MIT licence (see catalogue/hash). No third-party tank/terrain art or GodotGLB was copied/imported.

31 October bounded visual-model attempt: Pixor Tank (Frakassets/Pixor, https://pixor.art/library/vehicles/tank/; primary https://pixor.art/library/license/) has a verified CC0 1.0 library declaration, but its creator-linked GLB download returned403 Forbidden. NOT DOWNLOADED/IMPORTED; no asset file/hash/output or geometry/compatibility claim. Primary T34/85 collector access restriction preserved, not retried. Gate evidence: evidence/model-20261031/ACCESS-GATE.json.

1 November 2026: Kestrel is original fictional Tank Battle geometry/materials authored with installed Blender5.2.1 and tools/build-original-tank.py. No downloaded model, texture, font, code, add-on or historical asset. Editable source and GLB: docs/assets/original-tank/kestrel/. Local game profile/stats and collision remain unchanged. Generator and output hashes recorded in evidence/original-model-20261101.

Bastion is the second original visual, authored only after Kestrel passed the first technical/render gate. Both editable .blend files and GLBs are under docs/assets/original-tank/{kestrel,bastion}/. Generator/output SHA256 and rendered/import evidence: evidence/original-model-20261101/assets.json and browser-binding.json. No external model data was acquired; all previous failed acquisition receipts remain historical. Installed MIT Three.js GLTFLoader/BufferGeometryUtils/SkeletonUtils are served unchanged from the existing pinned package.

Current battlefield defaults to the two original Blender visuals; the earlier procedural-tank paragraphs describe preserved legacy/fallback stages. No third-party tank art was subsequently imported.

Slice19 polish remains original project work: selective bevels, authored bolt heads/grab rails and adjusted roughness/metalness on both fictional visuals. New client trail/flash/smoke/sparks/soft blast shaders and geometry are locally authored, with no downloaded textures, model/code acquisition or additional package. Updated generator/blend/GLB/studio hashes and budgets: evidence/polish-20261101/assets.json. Existing licensing of installed Three.js/Rapier/ws is unchanged.

Offline4v4 (2026-11-02): tree trunks/crowns are original procedural cylinder/cone instances in public/battlefield-view.mjs, from authored src/solo-map.mjs placements; no external art. Static export reuses the pinned Three.js and Rapier packages and both original tank GLBs above. tools/build-offline.mjs ships installed Three MIT and Rapier Apache-2.0 licence texts under licenses/. No new library or texture acquisition.

4 November field art: Foundry is original project-authored Blender geometry/materials and a fictional WWII-inspired visual. [The Tank Museum’s M4A1 account](https://tankmuseum.org/tank-nuts/tank-collection/m4-sherman) supplied the cast-hull and period suspension cues as text reference only. No historical drawings, museum imagery, measurements, markings or third-party geometry were imported. The editable .blend and runtime GLB are under `docs/assets/original-tank/foundry/`; `tools/build-original-tank.py` produces both. Field colours, the river and instanced crowns are original procedural geometry/colour in `public/landscape-art.mjs`. [Asset hashes and counts](evidence/field-art-20261104/asset-budget.json) and CPU studies are local project output.
