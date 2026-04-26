# BulkVSCodeSubMover

PowerShell automation for staged Azure subscription evacuation from a source Microsoft Entra tenant to a target tenant.

## Status

Initial implementation is in place for:
- configuration loading
- discovery-mode orchestration
- run artifact creation
- candidate filtering and classification
- safety gates for migrate mode

The actual directory transfer step remains intentionally blocked until a supported Microsoft API or CLI path is proven in a pilot.

## Entry point

```powershell
pwsh ./BulkVSCodeSubMover.ps1 -ConfigPath ./Config/settings.ps1 -Mode Discovery
```
