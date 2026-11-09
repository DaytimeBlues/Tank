# Architecture and hosting boundary

Godot owns rendering, the 320 m map, four original tank appearances, intentions, HUD and room UI. Node/Rapier owns movement/collision, health, accepted shots, reload, damage, respawn, capture, readiness, team seats and reservations. Clients do not submit authoritative transforms or damage.

`backend/run-godot-local.mjs` serves the generated `web/` export and injects the connection bridge. It binds 127.0.0.1 only. Never expose this development mode to a LAN or public network as a shortcut.

`backend/run-godot-hosted.mjs` is a separate fail-closed adapter preserving teacher login, bounded guest invitations, secure cookies, scoped one-use connection tickets, exact Host/Origin, tank-v1 WebSocket negotiation, owner-bound reconnect and single-instance epoch assumptions. Credentials stay out of source, URLs and logs. Configuration names and validation are in `backend/src/server-config.mjs` and `backend/src/private-access.mjs`.

Hosting requires the backend plus sibling Web export on one canonical HTTPS origin with WSS support. A static asset site supplies neither authority nor admission. `/health` alone is insufficient provenance because the legacy fingerprint excludes the Godot wrapper/export. Verify deployed source, lockfile, entrypoint and all ten served assets, including injected HTML and godot-bridge.js.

The repository contains no GitHub Actions workflow, root deployment blueprint or hosting auto-deploy configuration. The retained legacy backend deployment example is historical source, not an instruction to activate it. Do not use a legacy entrypoint for a Godot pilot.

Any live release needs separate provider/audience/budget approval and explicit lifecycle tests. Public source availability does not approve public gameplay, new credentials, paid infrastructure or student data collection.
