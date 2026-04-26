Set-StrictMode -Version Latest

$script:KnownModes = @('Discovery', 'Notify', 'Preflight', 'Migrate', 'Validate', 'Report')
$script:KnownNotificationModes = @('None', 'Email', 'TeamsChannel')
$script:KnownRiskTypes = @(
    'Microsoft.ContainerService/managedClusters',
    'Microsoft.KeyVault/vaults',
    'Microsoft.ManagedIdentity/userAssignedIdentities',
    'Microsoft.Sql/servers',
    'Microsoft.Synapse/workspaces',
    'Microsoft.DevCenter/projects',
    'Microsoft.DevCenter/devcenters',
    'Microsoft.Authorization/policyAssignments',
    'Microsoft.Authorization/policyDefinitions'
)
$script:CsvColumns = @{
    Candidates = @('SubscriptionId', 'SubscriptionName', 'State', 'MatchRegex', 'Status', 'RiskLevel')
    Owners = @('SubscriptionId', 'SubscriptionName', 'SourcePrincipalId', 'SourcePrincipalType', 'SourceSignInName', 'Mail', 'AccountEnabled', 'ResolvedInGraph', 'TargetPrincipalId', 'Action')
    Notifications = @('SubscriptionId', 'Recipient', 'Channel', 'Sent', 'SentAt', 'Error')
    Preflight = @('SubscriptionId', 'CanReadRbac', 'HasOwner', 'HasResolvableOwner', 'CanCreateTargetGuest', 'TransferSupported', 'RiskLevel', 'Decision')
    Migration = @('SubscriptionId', 'StartedAt', 'CompletedAt', 'TransferStatus', 'OwnerRestoreStatus', 'ValidationStatus', 'Error')
    Orphans = @('SubscriptionId', 'SubscriptionName', 'Reason', 'RecommendedAction')
    PostValidation = @('SubscriptionId', 'SubscriptionName', 'ExpectedTenantId', 'ActualTenantId', 'MigrationAdminOwner', 'PreservedOwnerCount', 'MissingOwnerCount', 'Status', 'Notes')
}

function Import-EvacuationConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Configuration file not found at '$ConfigPath'."
    }

    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    . $resolvedConfigPath

    $requiredVariables = @(
        'CurrentTenantId',
        'TargetTenantId',
        'SubscriptionNameRegexes',
        'Mode',
        'OutputRoot',
        'NotificationMode',
        'SenderUserId',
        'InviteOwnersToTargetTenant',
        'GrantOwnerInTargetTenant',
        'PreserveOnlySubscriptionOwners',
        'IncludeInheritedOwners',
        'MaxParallelism',
        'ThrottleDelaySeconds',
        'WhatIf',
        'ChangeTicketId'
    )

    foreach ($name in $requiredVariables) {
        if (-not (Get-Variable -Name $name -Scope Local -ErrorAction SilentlyContinue)) {
            throw "Configuration variable '$name' is missing from '$resolvedConfigPath'."
        }
    }

    if (-not (Get-Variable -Name 'SubscriptionIdAllowList' -Scope Local -ErrorAction SilentlyContinue)) {
        $SubscriptionIdAllowList = @()
    }

    if (-not (Get-Variable -Name 'SubscriptionIdDenyList' -Scope Local -ErrorAction SilentlyContinue)) {
        $SubscriptionIdDenyList = @()
    }

    if (-not (Get-Variable -Name 'TargetMigrationAdminObjectId' -Scope Local -ErrorAction SilentlyContinue)) {
        $TargetMigrationAdminObjectId = ''
    }

    if (-not (Get-Variable -Name 'TargetMigrationAdminType' -Scope Local -ErrorAction SilentlyContinue)) {
        $TargetMigrationAdminType = 'Group'
    }

    if (-not (Get-Variable -Name 'CandidateCsvPath' -Scope Local -ErrorAction SilentlyContinue)) {
        $CandidateCsvPath = ''
    }

    if (-not (Get-Variable -Name 'NotificationDeadline' -Scope Local -ErrorAction SilentlyContinue)) {
        $NotificationDeadline = $null
    }

    if (-not (Get-Variable -Name 'RequiredModules' -Scope Local -ErrorAction SilentlyContinue)) {
        $RequiredModules = @(
            'Az.Accounts',
            'Az.Resources',
            'Microsoft.Graph.Authentication',
            'Microsoft.Graph.Users',
            'Microsoft.Graph.Users.Actions',
            'Microsoft.Graph.Identity.SignIns'
        )
    }

    $configuration = [ordered]@{
        ConfigPath                    = $resolvedConfigPath
        CurrentTenantId               = $CurrentTenantId
        TargetTenantId                = $TargetTenantId
        SubscriptionNameRegexes       = @($SubscriptionNameRegexes)
        Mode                          = $Mode
        OutputRoot                    = $OutputRoot
        NotificationMode              = $NotificationMode
        SenderUserId                  = $SenderUserId
        InviteOwnersToTargetTenant    = [bool]$InviteOwnersToTargetTenant
        GrantOwnerInTargetTenant      = [bool]$GrantOwnerInTargetTenant
        PreserveOnlySubscriptionOwners = [bool]$PreserveOnlySubscriptionOwners
        IncludeInheritedOwners        = [bool]$IncludeInheritedOwners
        MaxParallelism                = [int]$MaxParallelism
        ThrottleDelaySeconds          = [int]$ThrottleDelaySeconds
        WhatIf                        = [bool]$WhatIf
        ChangeTicketId                = $ChangeTicketId
        SubscriptionIdAllowList       = @($SubscriptionIdAllowList)
        SubscriptionIdDenyList        = @($SubscriptionIdDenyList)
        TargetMigrationAdminObjectId  = $TargetMigrationAdminObjectId
        TargetMigrationAdminType      = $TargetMigrationAdminType
        CandidateCsvPath              = $CandidateCsvPath
        NotificationDeadline          = $NotificationDeadline
        RequiredModules               = @($RequiredModules)
    }

    if ($configuration.Mode -notin $script:KnownModes) {
        throw "Unsupported mode '$($configuration.Mode)'. Allowed values: $($script:KnownModes -join ', ')."
    }

    if ($configuration.NotificationMode -notin $script:KnownNotificationModes) {
        throw "Unsupported notification mode '$($configuration.NotificationMode)'. Allowed values: $($script:KnownNotificationModes -join ', ')."
    }

    return [pscustomobject]$configuration
}

function Test-RegexConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Regexes
    )

    $results = foreach ($regex in $Regexes) {
        try {
            [void][regex]::new($regex)
            [pscustomobject]@{
                Regex   = $regex
                IsValid = $true
                Error   = $null
            }
        }
        catch {
            [pscustomobject]@{
                Regex   = $regex
                IsValid = $false
                Error   = $_.Exception.Message
            }
        }
    }

    $invalid = $results | Where-Object { -not $_.IsValid }
    if ($invalid) {
        $messages = $invalid | ForEach-Object { "'$($_.Regex)': $($_.Error)" }
        throw "Regex validation failed. $($messages -join '; ')"
    }

    return $results
}

function Assert-MigrateModeAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    if ($Configuration.Mode -ne 'Migrate') {
        return $true
    }

    if ($Configuration.WhatIf) {
        throw 'Migrate mode requires WhatIf = $false.'
    }

    if ([string]::IsNullOrWhiteSpace($Configuration.ChangeTicketId) -or $Configuration.ChangeTicketId -eq 'CHG000000') {
        throw 'Migrate mode requires a real change ticket ID.'
    }

    if ([string]::IsNullOrWhiteSpace($Configuration.CandidateCsvPath)) {
        throw 'Migrate mode requires CandidateCsvPath to point to a previously approved candidate CSV.'
    }

    if (-not (Test-Path -LiteralPath $Configuration.CandidateCsvPath)) {
        throw "Candidate CSV '$($Configuration.CandidateCsvPath)' was not found."
    }

    if ([string]::IsNullOrWhiteSpace($Configuration.TargetMigrationAdminObjectId)) {
        throw 'Migrate mode requires TargetMigrationAdminObjectId so the target tenant has durable Owner access after transfer.'
    }

    return $true
}

function New-ArtifactFileMap {
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot
    )

    return [ordered]@{
        Transcript      = Join-Path $RunRoot 'transcript.log'
        Manifest        = Join-Path $RunRoot 'run-manifest.json'
        Candidates      = Join-Path $RunRoot 'candidates.csv'
        Owners          = Join-Path $RunRoot 'owners.csv'
        Notifications   = Join-Path $RunRoot 'owner-notifications.csv'
        Preflight       = Join-Path $RunRoot 'preflight-results.csv'
        Migration       = Join-Path $RunRoot 'migration-results.csv'
        PostValidation  = Join-Path $RunRoot 'post-validation.csv'
        Orphans         = Join-Path $RunRoot 'orphan-review.csv'
        Errors          = Join-Path $RunRoot 'errors.jsonl'
        Events          = Join-Path $RunRoot 'events.jsonl'
        Raw             = Join-Path $RunRoot 'raw'
    }
}

function New-DirectoryIfMissing {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function Initialize-RunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    foreach ($tenantId in @($Configuration.CurrentTenantId, $Configuration.TargetTenantId)) {
        $parsedGuid = [guid]::Empty
        if (-not [guid]::TryParse($tenantId, [ref]$parsedGuid)) {
            throw "Tenant ID '$tenantId' is not a valid GUID."
        }
    }

    Test-RegexConfiguration -Regexes $Configuration.SubscriptionNameRegexes | Out-Null

    $resolvedRepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($Configuration.OutputRoot)) {
        $Configuration.OutputRoot
    }
    else {
        Join-Path $resolvedRepositoryRoot $Configuration.OutputRoot
    }

    $runStamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $changeTicketSegment = if ([string]::IsNullOrWhiteSpace($Configuration.ChangeTicketId)) {
        'NOCHANGE'
    }
    else {
        ($Configuration.ChangeTicketId -replace '[^A-Za-z0-9_-]', '_')
    }

    $runRoot = Join-Path (Join-Path $resolvedOutputRoot 'runs') "${runStamp}_${changeTicketSegment}"
    $artifactFiles = New-ArtifactFileMap -RunRoot $runRoot

    New-DirectoryIfMissing -Path $resolvedOutputRoot
    New-DirectoryIfMissing -Path (Join-Path $resolvedOutputRoot 'runs')
    New-DirectoryIfMissing -Path $runRoot
    New-DirectoryIfMissing -Path $artifactFiles.Raw

    Start-Transcript -Path $artifactFiles.Transcript -Append | Out-Null

    $availableModules = Get-Module -ListAvailable | Group-Object -Property Name -AsHashTable -AsString
    $moduleVersions = foreach ($moduleName in $Configuration.RequiredModules) {
        $module = $availableModules[$moduleName] | Sort-Object Version -Descending | Select-Object -First 1
        [pscustomobject]@{
            Name      = $moduleName
            Installed = [bool]$module
            Version   = if ($module) { $module.Version.ToString() } else { $null }
        }
    }

    $azContext = $null
    if (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue) {
        $azContext = Get-AzContext -ErrorAction SilentlyContinue
    }

    $operator = [ordered]@{
        UserName       = [Environment]::UserName
        UserDomain     = [Environment]::UserDomainName
        MachineName    = [Environment]::MachineName
        AzAccount      = if ($azContext) { $azContext.Account.Id } else { $null }
        AzTenantId     = if ($azContext) { $azContext.Tenant.Id } else { $null }
        PowerShell     = $PSVersionTable.PSVersion.ToString()
    }

    $manifest = [ordered]@{
        StartedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        RepositoryRoot = $resolvedRepositoryRoot
        RunRoot        = $runRoot
        Mode           = $Configuration.Mode
        ChangeTicketId = $Configuration.ChangeTicketId
        WhatIf         = $Configuration.WhatIf
        Operator       = $operator
        Configuration  = [ordered]@{
            CurrentTenantId              = $Configuration.CurrentTenantId
            TargetTenantId               = $Configuration.TargetTenantId
            SubscriptionNameRegexes      = @($Configuration.SubscriptionNameRegexes)
            NotificationMode             = $Configuration.NotificationMode
            InviteOwnersToTargetTenant   = $Configuration.InviteOwnersToTargetTenant
            GrantOwnerInTargetTenant     = $Configuration.GrantOwnerInTargetTenant
            PreserveOnlySubscriptionOwners = $Configuration.PreserveOnlySubscriptionOwners
            IncludeInheritedOwners       = $Configuration.IncludeInheritedOwners
            MaxParallelism               = $Configuration.MaxParallelism
            ThrottleDelaySeconds         = $Configuration.ThrottleDelaySeconds
            CandidateCsvPath             = $Configuration.CandidateCsvPath
            TargetMigrationAdminObjectId = $Configuration.TargetMigrationAdminObjectId
        }
        Modules        = $moduleVersions
        ArtifactFiles  = $artifactFiles
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifactFiles.Manifest -Encoding utf8

    $context = [pscustomobject]@{
        Configuration = $Configuration
        RepositoryRoot = $resolvedRepositoryRoot
        RunRoot = $runRoot
        ArtifactFiles = [pscustomobject]$artifactFiles
        StartedAtUtc = $manifest.StartedAtUtc
    }

    Write-RunLog -RunContext $context -Level Information -Stage 'Initialize' -Message 'Run context initialized.'

    return $context
}

function Write-RunLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [ValidateSet('Information', 'Warning', 'Error', 'Critical')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Stage,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [System.Exception]$Failure,

        [Parameter()]
        [hashtable]$Data
    )

    $logEntry = [ordered]@{
        timestamp      = (Get-Date).ToUniversalTime().ToString('o')
        level          = $Level
        stage          = $Stage
        subscriptionId = $SubscriptionId
        message        = $Message
    }

    if ($Data) {
        $logEntry.data = $Data
    }

    if ($Failure) {
        $logEntry.exception = $Failure.Message
    }

    $line = $logEntry | ConvertTo-Json -Compress -Depth 6
    Add-Content -LiteralPath $RunContext.ArtifactFiles.Events -Value $line -Encoding utf8

    if ($Level -in @('Error', 'Critical')) {
        Add-Content -LiteralPath $RunContext.ArtifactFiles.Errors -Value $line -Encoding utf8
    }
}

function Stop-RunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext
    )

    Write-RunLog -RunContext $RunContext -Level Information -Stage 'Finalize' -Message 'Stopping run context.'

    try {
        Stop-Transcript | Out-Null
    }
    catch {
        Write-Warning 'Transcript was not active when Stop-RunContext executed.'
    }
}

function Connect-SourceTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext
    )

    if (-not (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)) {
        throw 'Az.Accounts is not available. Install required modules before running Discovery.'
    }

    Connect-AzAccount -Tenant $RunContext.Configuration.CurrentTenantId | Out-Null
    Set-AzContext -Tenant $RunContext.Configuration.CurrentTenantId | Out-Null
    Write-RunLog -RunContext $RunContext -Level Information -Stage 'Authentication' -Message 'Connected to source tenant.'
}

function Connect-TargetTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext
    )

    if (-not (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)) {
        throw 'Az.Accounts is not available. Install required modules before running target-tenant operations.'
    }

    Connect-AzAccount -Tenant $RunContext.Configuration.TargetTenantId | Out-Null
    Set-AzContext -Tenant $RunContext.Configuration.TargetTenantId | Out-Null
    Write-RunLog -RunContext $RunContext -Level Information -Stage 'Authentication' -Message 'Connected to target tenant.'
}

function Test-SubscriptionSelection {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,

        [Parameter(Mandatory)]
        [string]$SubscriptionId
    )

    if ($Configuration.SubscriptionIdDenyList -contains $SubscriptionId) {
        return 'Blocked'
    }

    if ($Configuration.SubscriptionIdAllowList.Count -gt 0 -and $Configuration.SubscriptionIdAllowList -notcontains $SubscriptionId) {
        return 'Blocked'
    }

    return 'Selected'
}

function Get-CandidateSubscriptions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Configuration,

        [Parameter()]
        [object[]]$Subscriptions
    )

    $sourceSubscriptions = if ($PSBoundParameters.ContainsKey('Subscriptions')) {
        $Subscriptions
    }
    else {
        if (-not (Get-Command -Name Get-AzSubscription -ErrorAction SilentlyContinue)) {
            throw 'Get-AzSubscription is not available. Install Az.Accounts before running Discovery.'
        }

        Get-AzSubscription -TenantId $Configuration.CurrentTenantId
    }

    $seen = @{}
    $candidates = foreach ($subscription in $sourceSubscriptions) {
        if (-not $subscription.Id -or -not $subscription.Name) {
            continue
        }

        if ($seen.ContainsKey($subscription.Id)) {
            continue
        }

        foreach ($regex in $Configuration.SubscriptionNameRegexes) {
            if ($subscription.Name -match $regex) {
                $seen[$subscription.Id] = $true

                $selectionState = Test-SubscriptionSelection -Configuration $Configuration -SubscriptionId $subscription.Id
                $status = switch ($true) {
                    ($subscription.TenantId -eq $Configuration.TargetTenantId) { 'AlreadyInTarget'; break }
                    ($subscription.State -ne 'Enabled') { 'Disabled'; break }
                    ($selectionState -eq 'Blocked') { 'Blocked'; break }
                    default { 'Candidate' }
                }

                [pscustomobject]@{
                    SubscriptionId   = $subscription.Id
                    SubscriptionName = $subscription.Name
                    State            = $subscription.State
                    MatchRegex       = $regex
                    Status           = $status
                    RiskLevel        = 'Unknown'
                    TenantId         = $subscription.TenantId
                }

                break
            }
        }
    }

    return $candidates | Sort-Object SubscriptionName, SubscriptionId
}

function New-EmptyCsv {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Headers
    )

    Set-Content -LiteralPath $Path -Value ($Headers -join ',') -Encoding utf8
}

function Export-StructuredCsv {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$Headers
    )

    if (-not $InputObject -or $InputObject.Count -eq 0) {
        New-EmptyCsv -Path $Path -Headers $Headers
        return
    }

    $InputObject |
        Select-Object -Property $Headers |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}

function Export-DiscoveryReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [object[]]$Candidates,

        [Parameter()]
        [object[]]$Owners = @(),

        [Parameter()]
        [object[]]$Orphans = @()
    )

    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Candidates -InputObject $Candidates -Headers $script:CsvColumns.Candidates
    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Owners -InputObject $Owners -Headers $script:CsvColumns.Owners
    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Orphans -InputObject $Orphans -Headers $script:CsvColumns.Orphans
    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Notifications -InputObject @() -Headers $script:CsvColumns.Notifications
    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Preflight -InputObject @() -Headers $script:CsvColumns.Preflight
    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Migration -InputObject @() -Headers $script:CsvColumns.Migration
    Export-StructuredCsv -Path $RunContext.ArtifactFiles.PostValidation -InputObject @() -Headers $script:CsvColumns.PostValidation

    Write-RunLog -RunContext $RunContext -Level Information -Stage 'Reporting' -Message 'Discovery artifacts exported.' -Data @{ CandidateCount = $Candidates.Count; OwnerCount = $Owners.Count; OrphanCount = $Orphans.Count }
}

function Get-SubscriptionOwnerSnapshot {
    [CmdletBinding()]
    param()

    throw 'Get-SubscriptionOwnerSnapshot is planned but not implemented in this initial slice.'
}

function Resolve-SourcePrincipal {
    [CmdletBinding()]
    param()

    throw 'Resolve-SourcePrincipal is planned but not implemented in this initial slice.'
}

function Get-SubscriptionResourceRisk {
    [CmdletBinding()]
    param()

    throw 'Get-SubscriptionResourceRisk is planned but not implemented in this initial slice.'
}

function Send-OwnerNotification {
    [CmdletBinding()]
    param()

    throw 'Send-OwnerNotification is planned but not implemented in this initial slice.'
}

function Set-TargetGuestUser {
    [CmdletBinding()]
    param()

    throw 'Ensure-TargetGuestUser is planned but not implemented in this initial slice.'
}

function Build-OwnerMapping {
    [CmdletBinding()]
    param()

    throw 'Build-OwnerMapping is planned but not implemented in this initial slice.'
}

function Test-TransferPrerequisites {
    [CmdletBinding()]
    param()

    throw 'Test-TransferPrerequisites is planned but not implemented in this initial slice.'
}

function Grant-MigrationAccess {
    [CmdletBinding()]
    param()

    throw 'Grant-MigrationAccess is planned but not implemented in this initial slice.'
}

function Invoke-SubscriptionDirectoryTransfer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [string]$SourceTenantId,

        [Parameter(Mandatory)]
        [string]$TargetTenantId
    )

    throw 'Implementation must use a validated Microsoft-supported API or CLI path. Portal automation is not allowed.'
}

function Wait-SubscriptionInTargetTenant {
    [CmdletBinding()]
    param()

    throw 'Wait-SubscriptionInTargetTenant is planned but not implemented in this initial slice.'
}

function Grant-TargetOwnerAccess {
    [CmdletBinding()]
    param()

    throw 'Grant-TargetOwnerAccess is planned but not implemented in this initial slice.'
}

function Test-PostTransferAccess {
    [CmdletBinding()]
    param()

    throw 'Test-PostTransferAccess is planned but not implemented in this initial slice.'
}

function Export-FinalReport {
    [CmdletBinding()]
    param()

    throw 'Export-FinalReport is planned but not implemented in this initial slice.'
}

function Start-SubscriptionEvacuation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter()]
        [ValidateSet('Discovery', 'Notify', 'Preflight', 'Migrate', 'Validate', 'Report')]
        [string]$Mode
    )

    $configuration = Import-EvacuationConfiguration -ConfigPath $ConfigPath
    if ($PSBoundParameters.ContainsKey('Mode')) {
        $configuration.Mode = $Mode
    }

    Assert-MigrateModeAllowed -Configuration $configuration | Out-Null

    $runContext = Initialize-RunContext -Configuration $configuration -RepositoryRoot $RepositoryRoot

    try {
        switch ($configuration.Mode) {
            'Discovery' {
                Connect-SourceTenant -RunContext $runContext
                $candidates = Get-CandidateSubscriptions -Configuration $configuration
                Export-DiscoveryReports -RunContext $runContext -Candidates $candidates
                Write-RunLog -RunContext $runContext -Level Information -Stage 'Discovery' -Message 'Discovery completed.' -Data @{ CandidateCount = $candidates.Count }

                return [pscustomobject]@{
                    Mode           = $configuration.Mode
                    RunRoot        = $runContext.RunRoot
                    CandidateCount = $candidates.Count
                }
            }
            default {
                throw "Mode '$($configuration.Mode)' is scaffolded but not implemented in this initial slice."
            }
        }
    }
    catch {
        Write-RunLog -RunContext $runContext -Level Error -Stage $configuration.Mode -Message 'Run failed.' -Failure $_.Exception
        throw
    }
    finally {
        Stop-RunContext -RunContext $runContext
    }
}

Set-Alias -Name Ensure-TargetGuestUser -Value Set-TargetGuestUser
