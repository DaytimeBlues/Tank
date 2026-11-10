# Isolated Render pilot

This deployment branch preserves baseline 1bf63699 runtime, original flat bridge material, Node/Rapier authority and private teacher/guest admission. It does not contain the held concrete study.

Web export regenerated with Godot 4.8-beta2 official cafc17a19, Compatibility and no threads. Nine generated Web files are deliberately tracked on this deployment branch, bound by deploy/web-manifest.json and verified before build. No credentials belong in this repository or its recovery archive.

Build: `node tools/verify-render-bundle.mjs && npm ci --prefix backend --omit=dev --ignore-scripts`

Start: `node backend/run-godot-hosted.mjs`

Use a separate free Singapore web service, one instance, auto-deploy off. Configure exact HTTPS origin and the approved teacher-key SHA256 digest through Render environment settings. Preserve fail-closed hosted checks; never expose the loopback entry as an internet server. Existing Parkour service must remain unchanged.

Free compute does not itself guarantee zero charges: check included bandwidth/build usage and overage controls before deploy. Free services sleep, can restart, and lose in-memory rooms/sessions. This is a bounded test, not school acceptance.

Source build, provider restore, live HTTPS/WSS, teacher login, guest admission, ordinary driving/aiming/firing and reconnect are separate gates. Do not claim a playable hosted release from deployment status alone.
