[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Config\settings.ps1'),

    [Parameter()]
    [ValidateSet('Discovery', 'Notify', 'Preflight', 'Migrate', 'Validate', 'Report')]
    [string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'Modules\BulkVSCodeSubMover\BulkVSCodeSubMover.psd1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Module manifest not found at '$modulePath'."
}

Import-Module -Name $modulePath -Force

$invokeParameters = @{
    ConfigPath     = $ConfigPath
    RepositoryRoot = $PSScriptRoot
}

if ($PSBoundParameters.ContainsKey('Mode')) {
    $invokeParameters.Mode = $Mode
}

Start-SubscriptionEvacuation @invokeParameters
