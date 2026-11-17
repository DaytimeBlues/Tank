# Meshy Tank oak candidate, 17 November 2026
Task 01a1e71c-47ac-7723-b855-6943a5291884, Meshy t2 smart topology, requested 1500 faces, actual 1362 triangles, 835 source vertices. One 5-credit geometry generation, no texturing charges. Source preview visually inspected: branching silhouette with gaps and angular clusters is promising, not evaluated in game. Source scale is 1m with centered root; prepared version is 7m tall, root at zero, explicit face normals and two simple rough materials. Trunk component separated by root connectivity; crown remaining components. No UV/texture dependency.

Source SHA256 951bce87d5984d7bec7e3487e9194da4ada808a53efcaa085dece382f0470d02
Prepared SHA256 076b93739b3b06ec1f3df7e385812b22351635f2585dcdf132ff7e8af02ebba8

prepare.py ran twice with identical hash. validate.py checks source header, finite vertices, indices and self-contained buffers. Native Godot runtime import and rendered material assignment NOT yet checked. get_task did not return license field; public distribution acceptance remains unresolved. Do not deploy automatically. Integrator must adapt to an existing authoritative tree collider, not scatter new solid trunks without matching collision. No main-tree edits.

Skill receipt: validate-game-assets | skill://user/6ac0bd5c841c819180c783ef931a773b/validate-game-assets/SKILL.md | loaded/applied | dependency/count/hash/determinism checks | validation.json and scripts | runtime/material/public license acceptance pending.

## Follow-up validation
Godot 4.6.3 Compatibility headless imported prepared GLB successfully: 2 surfaces/materials, explicit normals, 1362 triangles; AABB (-2.5435,0,-2.7125), size(5.0804,7,5.4341). This is actual engine import, not rendered acceptance in project's 4.8 beta2.

Collision-fit result: NOT a drop-in replacement. Existing authority cylinder radius .55m and height3.8m. Prepared tree rooted component radial extents by vertical band: y0–.5 root flare1.218m, y.5–1 trunk.512m, y1–2 trunk.532m, y2–3.8 branching2.184m. Straight trunk agrees closely but root flare and low solid branches protrude well beyond cylinder. Must retain existing trunk geometry/authority and adapt decorative upper crown, or explicitly design/test new matching authority before integration. Never claim invisible collider parity from a simple bounding box.

License review 17Nov2026: Meshy Terms last updated19Sep2026, section3.2 states free-plan output available under CC BY4.0 with appropriate Meshy credit; paid-plan customers own generated outputs to extent law permits. This task used original text and no third-party inputs, was not published to Meshy Community. Account tier wasn't returned, so retain conservative attribution: “Oak model generated with Meshy; modified for Tank (scale, normals, materials). https://www.meshy.ai/ https://creativecommons.org/licenses/by/4.0/”. Official terms https://www.meshy.ai/terms-of-use and https://help.meshy.ai/en/articles/10137554-what-is-the-ownership-of-the-generated-models. This provides a distribution route with attribution regardless of free/paid tier; no claim of exclusive ownership or CC0.
