@{
    RootModule        = 'BulkVSCodeSubMover.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b02d28aa-a6d9-4ea2-ac95-f87441f8c6b8'
    Author            = 'GitHub Copilot'
    CompanyName       = 'Local'
    Copyright         = '(c) 2026'
    Description       = 'PowerShell automation for Azure subscription evacuation workflows.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Assert-MigrateModeAllowed',
        'Build-OwnerMapping',
        'Connect-SourceTenant',
        'Connect-TargetTenant',
        'Export-DiscoveryReports',
        'Export-FinalReport',
        'Get-CandidateSubscriptions',
        'Get-MigrationExecutionPlan',
        'Get-NotificationTargets',
        'Get-SubscriptionOwnerSnapshot',
        'Get-SubscriptionResourceRisk',
        'Get-TransferSupportSignal',
        'Grant-MigrationAccess',
        'Grant-TargetOwnerAccess',
        'Import-EvacuationConfiguration',
        'Initialize-RunContext',
        'Invoke-SubscriptionDirectoryTransfer',
        'Resolve-SourcePrincipal',
        'Send-OwnerNotification',
        'Set-TargetGuestUser',
        'Start-SubscriptionEvacuation',
        'Stop-RunContext',
        'Test-PostTransferAccess',
        'Test-RegexConfiguration',
        'Test-TransferPrerequisites',
        'Wait-SubscriptionInTargetTenant',
        'Write-RunLog'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Ensure-TargetGuestUser')
    PrivateData       = @{
        PSData = @{
            Tags       = @('Azure', 'Subscription', 'Migration', 'PowerShell')
            ProjectUri = 'https://github.com/JohnDelisle/BulkVSCodeSubMover'
        }
    }
}
