# Tank Battle: Godot classroom minimum playable slice

## Goal

A teacher opens a private browser game, creates a room, invites up to seven students and runs a balanced battle without student accounts or personal-data entry. Godot is the client engine; reviewed Node/Rapier authority remains until a separately tested native-server migration is justified. Preserve Three.js throughout.

## Required journey

1. Teacher login and bounded invitations admit authenticated sessions. A room code is not an access credential.
2. Create/Join assigns one anonymous seat/tank each, maximum four per team. Show roster, readiness and reservations. Host starts only balanced, fully ready teams.
3. Desktop movement/steering/aim/fire are intentions. Retain three hits per hull, four-second reload, respawn and existing capture rules.
4. Show seven bases, crossings, own location, base state and nearby capture status. Capture every base to win. Only host may request rematch, returning to readiness.
5. Menus, field focus, hidden/focus-lost pages, errors and unseated transport neutralize controls. Require fresh release on resume. UI clicks do not fire. Presentation follows server acceptance.
6. Bounded same-page reconnect preserves the owner-bound reservation. Expired access and invalid room fail safely and allow correction. Refresh recovery is not promised; credentials stay in memory.

## Acceptance

Exact authority/map/asset provenance and recoverable source/full history. Fresh Godot scene/map/model/UI smoke, eight real native peers, ordinary local two-browser Create/Join/Ready/Start/drive/aim/fire/rejoin/focus checks, strict CSP without JS eval and private-hosting negatives. Independent review must bind final source/export hashes. Label presentation fixtures separately.

Before classroom release: live same-origin HTTPS/WSS/invitations and provider lifecycle, no secret leakage, full ordinary-input capture/win/rematch, school browser/device load/performance and a teacher preview with a working private link.

## Not in this slice

New balance/damage, destructible bridges, economies/accounts, unlicensed copying, native Godot authority, offline AI, mobile touch controls, final visual parity, paid infrastructure and unapproved deployment. Original models remain; optional licensed donors require import/pivot/license checks. A beta export is not automatically a production engine decision.

## Future arcade balance direction, 8 November 2026

The requested direction is balanced arcade tradeoffs, not physical realism: a
heavy tank should move more slowly; a lighter tank should move faster with a
drawback such as less armour or firepower. This is future server-authoritative
tuning, separate from the current visual/first-use fix. The four appearances still
share the existing prototype stats. No final speed, armour, damage or firepower
numbers have been invented or implemented in this pass.

Asset budget for this task: improve the existing original models or use verified
free assets. Paid packs, purchases and paid donor dependencies are not authorized.
Check each asset's actual licence and required attribution before any future
adoption. This candidate uses original geometry/materials/shader and no paid pack.


## 9 November 2026 reconciliation and next acceptance

This project-owned PRD is the current Godot requirement entry point. The older
Crew Trials/Three.js two-seat PRD is historical, not the port contract. The dated
shared roadmap and requirements index were read before this reconciliation;
their Tank sections are applied here without importing unrelated project scope.
Earlier requirements above remain preserved. Runtime code and balance are unchanged.

### Baseline and recovery

The public GitHub source publication is 3290ff7; its runtime files reproduce e83cc89.
Future development starts from the verified GitHub-backed clone on branch
dev/student-pilot-20261109. The frozen e83 tree and private full-history recovery
remain separate and unchanged. Private provider upload, download, hash verification,
fresh 648-file restore, Godot import and focused 54/212 checks completed on 9 November.
Provider details remain private; the public repository does not contain that history.

The same exact e83 PCK now passed the ordinary two-client local match, rejoin, all-seven
win, rematch and second-round damage journey. See docs/LIFECYCLE-20261109.json.
This closes the named local journey gap, not hosted, classroom or performance gates.

### Visual direction and measured gaps

The Tank Contact & Framing concept sheet was inspected as pixels: broad matte olive
armour, darker separated tracks, the whole cannon in chase/narrow framing, supported
track contact, differentiated dirt/grass/stone and a readable bridge approach.
It is generated visual intent, not a model blueprint, collision specification or
finished asset. Existing roster, pivots, hitboxes and authoritative physics govern.
The original selected vehicle/terrain/interface reference names remain the visual
targets; their older pack was not re-inspected in this checkpoint.

Current runtime screenshots show an intact whole tank in the tested wide viewport,
but sparse foliage, flat material blocks, abrupt river edges and oversized world
labels. Portrait framing and camera-obstruction contact still need controlled tests.
Do not claim reference parity or solve these gaps by increasing map size first.

### Ordered work and exit tests

1. Preserve this local lifecycle baseline and review its source/export/evidence identity.
   Maintain the separate protected same-origin hosting gate. A static renderer is not
   the student game. No new service or spending follows from this plan.
2. Build an isolated contact/camera fixture: flat patch, slope, ramp lip, bridge approach,
   wall and obstruction. Compare track support, hull penetration, turn/stop, cannon/reticle
   agreement and peer agreement at wide and narrow viewports. Fix one demonstrated cause;
   never replace Node/Rapier authority as a cosmetic side effect.
3. Improve one original tank and one river-crossing sector before the full map. Preserve
   dimensions/pivots; use explicit Blender-to-GLB export, retained editable source,
   hashes/licence and matching-engine import. Judge gameplay-distance benefit and cost.
4. Author a bounded explosion/firing study: muzzle, accepted contact, scrapped-tank cue
   and fade. Existing effects use capped shader cards/tracers; reuse that tested path
   before introducing a renderer-specific particle dependency. Damage stays server-owned.
   Test cold first shot, repeated fire, death and rematch cleanup and busiest-scene cost.
5. Greybox three proposed maps separately: River Crossings, Quarry Ridges and Farmland
   Perimeter. Start with route graphs, two spawns, seven objectives, alternate approaches
   and scale bars. Choose size from measured travel-to-contact, turning space and visible
   set, not a maximum-world-size target. Populate one sector only after traversability,
   spawn sightlines and a timed two-client route pass. These are proposals, not delivered maps.
6. Integrate class/heat separately with explicit speed/acceleration/turn/health/reload/damage
   tradeoffs and heat generation/cooling/threshold/reset rules. Mass matters only if actual
   mechanics use it. Reconcile the older candidate onto the accepted baseline; do not merge
   its obsolete typed-hit path or imply model appearance already changes statistics.
7. After separately approved hosting, verify real HTTPS/WSS admission, ticket expiry/replay,
   owner-bound reconnect, restart invalidation and room cleanup. Then test actual 4v4 and
   target school devices/network. Measure startup, first-shot hitch, frame-time tails,
   input latency and server load; no performance target is declared passed without data.

### Research admission, 9 November

Official Godot documentation recommends glTF 2.0 export and explains that direct .blend
import invokes Blender. Prefer explicit GLB artifacts with editable Blender sources kept
outside runtime import. Check backface culling and import scale, materials and pivots.
Source: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html

Latest GPUParticles3D documentation says emit_particle is unsupported in Compatibility.
That is not a blanket particle ban, and latest docs may differ from installed beta2.
Keep the existing capped card/tracer fallback and test any one-shot emitter in the exact Web export.
Source: https://docs.godotengine.org/en/latest/classes/class_gpuparticles3d.html

Kenney Nature Kit is a free CC0 environment candidate (page lists 330 files, version 1.0).
It was researched, not downloaded or adopted in this checkpoint. Inspect actual licence,
formats, materials and one small import before using rocks/foliage as a coherent sector kit.
Source: https://kenney.nl/assets/nature-kit

One integration writer owns this branch. Separate art/map candidates must remain isolated,
be reviewed, then merged one at a time with relevant regressions. Save coherent source and
evidence checkpoints; park only the operation whose permission or capability is unavailable.
