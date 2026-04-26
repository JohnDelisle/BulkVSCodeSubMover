# BulkVSCodeSubMover Runbook

## Current implementation slice

This repository currently implements:
- configuration loading and validation
- run-folder, transcript, manifest, and JSONL event creation
- migrate-mode safety gates
- source-tenant discovery orchestration
- candidate subscription regex matching, deduplication, and base status classification
- owner snapshotting from Azure RBAC
- raw RBAC snapshot export under each run folder
- orphan and no-resolvable-owner reporting
- resource-risk inspection with Low, Medium, High, and Blocked classification
- raw resource snapshot export under each run folder
- Notify mode owner targeting and notification report generation
- Graph email send path for notifications when `NotificationMode = Email` and `WhatIf = $false`
- notification deduplication by `(SubscriptionId, Recipient)` to avoid duplicate sends
- Preflight mode with target guest mapping and preflight-results report generation
- preflight access gating that marks `Decision = BlockedPreflight` when source RBAC or target tenant access checks fail
- Migrate mode scaffolding with resumable execution planning and `migration-results.csv` output
- Validate mode scaffolding with `post-validation.csv` output
- Report mode with `final-report.json` summary output
- CSV artifact creation for the full report set

This repository does not yet implement:
- supported transfer API/CLI implementation (the transfer stub remains intentionally guarded)
- automated owner restoration and deep post-transfer validation logic
- transfer support detection beyond marker-based proof signaling

## First run

1. Copy `Config/settings.example.ps1` to `Config/settings.ps1`.
2. Replace both tenant IDs with real GUIDs.
3. Confirm the regex list and output path.
4. Leave `$WhatIf = $true`.
5. Run:

```powershell
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Discovery
```

Additional implemented modes:

```powershell
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Notify
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Preflight
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Migrate
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Validate
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Report
```

Transfer support flag behavior:
- Preflight reports `TransferSupported = true` only when [docs/pilot-transfer-proof.md](docs/pilot-transfer-proof.md) includes `SUPPORTED_TRANSFER_PATH_VALIDATED: true`.
- Otherwise preflight reports `TransferSupported = false` and keeps migration readiness conservative.

## Artifacts

Each run creates:
- `transcript.log`
- `run-manifest.json`
- `events.jsonl`
- `errors.jsonl`
- `candidates.csv`
- `owners.csv`
- `orphan-review.csv`
- `owner-notifications.csv`
- `preflight-results.csv`
- `migration-results.csv`
- `post-validation.csv`
- `final-report.json`
- raw RBAC and resource JSON snapshots in the `raw` folder

## Operational note

`Invoke-SubscriptionDirectoryTransfer` is intentionally blocked until a supported transfer mechanism is proven in a pilot. Do not replace that guard with portal automation.
