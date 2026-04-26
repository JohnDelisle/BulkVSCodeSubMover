# BulkVSCodeSubMover Runbook

## Current implementation slice

This repository currently implements:
- configuration loading and validation
- run-folder, transcript, manifest, and JSONL event creation
- migrate-mode safety gates
- source-tenant discovery orchestration
- candidate subscription regex matching, deduplication, and base status classification
- CSV artifact creation for the full report set

This repository does not yet implement:
- owner or RBAC snapshotting
- resource-risk inspection
- owner notifications
- target-tenant guest preparation
- preflight checks
- migration orchestration beyond safety gating
- post-transfer restoration and validation

## First run

1. Copy `Config/settings.example.ps1` to `Config/settings.ps1`.
2. Replace both tenant IDs with real GUIDs.
3. Confirm the regex list and output path.
4. Leave `$WhatIf = $true`.
5. Run:

```powershell
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Discovery
```

## Artifacts

Each run creates:
- `transcript.log`
- `run-manifest.json`
- `events.jsonl`
- `errors.jsonl`
- `candidates.csv`
- placeholder CSVs for owners, notifications, preflight, migration, post-validation, and orphan review

## Operational note

`Invoke-SubscriptionDirectoryTransfer` is intentionally blocked until a supported transfer mechanism is proven in a pilot. Do not replace that guard with portal automation.
