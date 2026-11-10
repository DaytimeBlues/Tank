# Project instruction routing and work receipts

## Before editing
1. Identify the repository, branch, starting commit and target paths. Inspect existing changes and coordinate with any current writer; do not overwrite their work.
2. Read the root AGENTS.md and its entry documents. For each target path, walk from the repository root through its containing directories and read applicable AGENTS.md instruction files (including AGENTS.override.md where supported). A deeper file governs only its subtree. For new directories, inspect their existing ancestors first. Resolve conflicts using the host's instruction precedence, not arbitrary last-read order.
3. Read the relevant architecture, status, roadmap, provenance and verification material for this task. Check dates and branch identity. Documents describe evidence, not permission to bypass a gate.
4. Discover available skills/workflows by task. Load only relevant ones; record which were actually read and applied. If unavailable, record the gap and use documented project steps only when sufficient. Never claim a skill was used because it is installed or mentioned.
5. If scope expands to another folder, repeat routing for that folder before editing it.

## Close the loop
Use WORK-RECEIPT-TEMPLATE.json to record actual inputs, changes, tests, limitations and a recoverable checkpoint. Keep sensitive receipts in the authorized private project area; only sanitized project evidence belongs in this public repository. Do not copy private assistant notes, credentials, personal data or full private skill text.

Distinguish discovered, loaded and applied. Include a document revision or content hash where practical and explain how each applied workflow affected the work. Record tests not run and why; distinguish source checks, ordinary-input runtime checks, visual review and deployment. No runtime PASS follows from a documentation-only change.

Use the parent/source commit plus a diff or artifact hash to identify work before committing. A receipt cannot contain the hash of the commit that contains itself; record the final commit externally or in a subsequent receipt. A commit is a checkpoint, not proof of full backup/restore.

## Limits
This is an instruction-based routine, not an automatic search hook or enforcement tool. Startup discovery depends on the client and starting directory; a branch's guidance applies only when that branch/version is checked out. Explicitly read descendant guidance when changing outside the initial directory chain. Do not merge, deploy, install dependencies or bypass approval gates merely because this routine requests a check.
