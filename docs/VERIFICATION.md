# Verification and reproduction

This is a source publication check, not a new classroom release. Unchanged source files are bound in source-manifest.json. The public snapshot deliberately omits private history/raw operational evidence. Historical evidence validators that reference omitted receipts are not a fresh acceptance command; keep that distinction when using tools/.

## Focused local checks

After import using the matching Godot version:

- `godot --headless --path . --script tests/smoke.gd`
- `godot --headless --path . --script tests/wire_contact_types.gd`
- `python tools/check-visual-assets.py`
- JavaScript parse checking: `node --check <file.mjs>` for the included backend modules.

Godot executable names vary by installation. The backend's legacy npm lint/test scripts reference files not included in this preserved bridge subset; they are not represented as passing aggregate checks. There is no backend typecheck script. Do not install extra tools merely to hide a missing check.

A real browser match must still cover create/join, balance, both-ready/start, drive/aim/fire, accepted damage/reload, death/respawn, capture/win, rejoin, rematch and second round, with error checks and secure cleanup. Native fixtures do not replace ordinary input.

## Publication safety

The destination is the user's specifically requested public DaytimeBlues/Tank repository. Its pre-existing MIT LICENSE and commit are preserved. No private source history, environment files, dependency directories, deployment credentials, raw ticket/cookie logs or user documents are included. Pattern scanning is a bounded safeguard, not a proof that arbitrary code has no security issues. No live service is deployed by this upload.

Fresh publication-check results are in PUBLICATION-CHECKS.json. Remaining runtime, hosted and recovery limits are recorded in CURRENT-STATUS.md.
