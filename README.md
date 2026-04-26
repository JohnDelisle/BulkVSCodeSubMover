# BulkVSCodeSubMover

PowerShell automation for staged Azure subscription evacuation from a source Microsoft Entra tenant to a target tenant.

## Status

Initial implementation is in place for:
- configuration loading
- discovery-mode orchestration
- run artifact creation
- candidate filtering and classification
- owner RBAC snapshotting with raw JSON capture
- principal normalization and orphan detection
- lightweight resource-risk inspection with raw resource capture
- notify mode with owner notification row generation and Graph email delivery path
- preflight mode with target guest mapping and preflight-results output
- notification target deduplication by subscription and recipient
- preflight access gating for source RBAC and target tenant reachability
- safety gates for migrate mode
- migrate mode execution scaffolding with resumable planning and per-subscription migration results
- validate mode scaffolding for post-transfer validation rows
- report mode final summary generation (`final-report.json`)

The actual directory transfer step remains intentionally blocked until a supported Microsoft API or CLI path is proven in a pilot.

## Entry point

```powershell
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Discovery
```

Other implemented modes:

```powershell
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Notify
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Preflight
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Migrate
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Validate
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Report
```

Preflight sets `TransferSupported = true` only when [docs/pilot-transfer-proof.md](docs/pilot-transfer-proof.md) contains this line:

```text
SUPPORTED_TRANSFER_PATH_VALIDATED: true
```

Without that marker, preflight remains conservative and reports `TransferSupported = false`.

`Migrate` remains safe by default:
- if transfer support is not validated, each eligible subscription is marked `BlockedNoSupportedPath`
- if transfer support is validated, the transfer function is invoked and still enforces the hard implementation guard
