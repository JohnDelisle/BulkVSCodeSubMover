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
$script:KnownBlockedRiskTypes = @()
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

function ConvertTo-JsonDocument {
    param(
        [Parameter()]
        [object[]]$InputObject = @(),

        [Parameter()]
        [int]$Depth = 10
    )

    if (-not $InputObject -or $InputObject.Count -eq 0) {
        return '[]'
    }

    return ($InputObject | ConvertTo-Json -Depth $Depth)
}

function Get-RoleAssignmentObjectId {
    param(
        [Parameter(Mandatory)]
        [object]$RoleAssignment
    )

    foreach ($propertyName in @('ObjectId', 'PrincipalId', 'Id')) {
        if ($RoleAssignment.PSObject.Properties.Name -contains $propertyName) {
            $value = $RoleAssignment.$propertyName
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return $null
}

function Get-RoleAssignmentObjectType {
    param(
        [Parameter(Mandatory)]
        [object]$RoleAssignment
    )

    foreach ($propertyName in @('ObjectType', 'PrincipalType')) {
        if ($RoleAssignment.PSObject.Properties.Name -contains $propertyName) {
            $value = $RoleAssignment.$propertyName
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return 'Unknown'
}

function Get-RoleAssignmentRoleName {
    param(
        [Parameter(Mandatory)]
        [object]$RoleAssignment
    )

    foreach ($propertyName in @('RoleDefinitionName', 'RoleDisplayName')) {
        if ($RoleAssignment.PSObject.Properties.Name -contains $propertyName) {
            $value = $RoleAssignment.$propertyName
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return $null
}

function Get-RoleAssignmentScope {
    param(
        [Parameter(Mandatory)]
        [object]$RoleAssignment,

        [Parameter(Mandatory)]
        [string]$FallbackScope
    )

    if ($RoleAssignment.PSObject.Properties.Name -contains 'Scope' -and -not [string]::IsNullOrWhiteSpace([string]$RoleAssignment.Scope)) {
        return [string]$RoleAssignment.Scope
    }

    return $FallbackScope
}

function Test-IsOwnerLikeRole {
    param(
        [Parameter(Mandatory)]
        [string]$RoleDefinitionName
    )

    return $RoleDefinitionName -in @('Owner', 'ServiceAdministrator', 'CoAdministrator')
}

function Get-OwnerAction {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$OwnerRecord
    )

    switch ($OwnerRecord.SourcePrincipalType) {
        'User' {
            if (-not $OwnerRecord.ResolvedInGraph -and [string]::IsNullOrWhiteSpace($OwnerRecord.UserPrincipalName) -and [string]::IsNullOrWhiteSpace($OwnerRecord.Mail)) {
                return 'ReviewUnresolvableUser'
            }

            if ($OwnerRecord.AccountEnabled -eq $false) {
                return 'ReviewDisabledUser'
            }

            return 'NotifyAndPreserve'
        }
        'Group' {
            return 'ManualGroupMappingRequired'
        }
        'ServicePrincipal' {
            return 'ManualServicePrincipalMappingRequired'
        }
        default {
            return 'ReviewUnknownPrincipalType'
        }
    }
}

function Update-CandidateStatusFromOwners {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Candidate,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Owners,

        [Parameter()]
        [pscustomobject]$OrphanRecord
    )

    if ($Candidate.Status -ne 'Candidate') {
        return $Candidate.Status
    }

    if ($OrphanRecord) {
        return 'NoOwner'
    }

    if ($Owners.Count -gt 0) {
        return 'ReadyForNotification'
    }

    return 'Candidate'
}

function Get-ResourceTypeName {
    param(
        [Parameter(Mandatory)]
        [object]$Resource
    )

    foreach ($propertyName in @('ResourceType', 'Type')) {
        if ($Resource.PSObject.Properties.Name -contains $propertyName) {
            $value = $Resource.$propertyName
            if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
                return [string]$value
            }
        }
    }

    return 'Unknown'
}

function Get-SubscriptionOwnerSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$Candidate,

        [Parameter()]
        [object[]]$RoleAssignments,

        [Parameter()]
        [hashtable]$ResolvedPrincipalMap
    )

    $scope = "/subscriptions/$($Candidate.SubscriptionId)"
    $snapshotPath = Join-Path $RunContext.ArtifactFiles.Raw ("rbac-{0}.json" -f $Candidate.SubscriptionId)
    $effectiveAssignments = if ($PSBoundParameters.ContainsKey('RoleAssignments')) {
        @($RoleAssignments)
    }
    else {
        if (-not (Get-Command -Name Get-AzRoleAssignment -ErrorAction SilentlyContinue)) {
            throw 'Get-AzRoleAssignment is not available. Install Az.Resources before running owner snapshotting.'
        }

        if (Get-Command -Name Set-AzContext -ErrorAction SilentlyContinue) {
            Set-AzContext -Tenant $RunContext.Configuration.CurrentTenantId -SubscriptionId $Candidate.SubscriptionId | Out-Null
        }

        @(Get-AzRoleAssignment -Scope $scope -IncludeClassicAdministrators -ErrorAction Stop)
    }

    ConvertTo-JsonDocument -InputObject $effectiveAssignments -Depth 10 | Set-Content -LiteralPath $snapshotPath -Encoding utf8

    $ownerRecords = foreach ($roleAssignment in $effectiveAssignments) {
        $roleName = Get-RoleAssignmentRoleName -RoleAssignment $roleAssignment
        if ([string]::IsNullOrWhiteSpace($roleName) -or -not (Test-IsOwnerLikeRole -RoleDefinitionName $roleName)) {
            continue
        }

        $assignmentScope = Get-RoleAssignmentScope -RoleAssignment $roleAssignment -FallbackScope $scope
        $isInherited = $assignmentScope -ne $scope
        if (-not $RunContext.Configuration.IncludeInheritedOwners -and $isInherited) {
            continue
        }

        $resolvedPrincipal = Resolve-SourcePrincipal -RoleAssignment $roleAssignment -ResolvedPrincipalMap $ResolvedPrincipalMap
        $objectId = Get-RoleAssignmentObjectId -RoleAssignment $roleAssignment
        $objectType = Get-RoleAssignmentObjectType -RoleAssignment $roleAssignment

        $ownerRecord = [pscustomobject]@{
            SubscriptionId      = $Candidate.SubscriptionId
            SubscriptionName    = $Candidate.SubscriptionName
            SourcePrincipalId   = $objectId
            SourcePrincipalType = $objectType
            SourceSignInName    = if ($roleAssignment.PSObject.Properties.Name -contains 'SignInName') { $roleAssignment.SignInName } else { $resolvedPrincipal.UserPrincipalName }
            SourceDisplayName   = if ($roleAssignment.PSObject.Properties.Name -contains 'DisplayName') { $roleAssignment.DisplayName } else { $resolvedPrincipal.DisplayName }
            RoleDefinitionName  = $roleName
            Scope               = $assignmentScope
            IsInherited         = $isInherited
            ResolvedInGraph     = $resolvedPrincipal.ResolvedInGraph
            AccountEnabled      = $resolvedPrincipal.AccountEnabled
            Mail                = $resolvedPrincipal.Mail
            UserPrincipalName   = $resolvedPrincipal.UserPrincipalName
            TargetPrincipalId   = $null
            TargetPrincipalType = $null
            Action              = $null
        }

        $ownerRecord.Action = Get-OwnerAction -OwnerRecord $ownerRecord
        $ownerRecord
    }

    $notifiableOwners = @(
        $ownerRecords | Where-Object {
            $_.SourcePrincipalType -eq 'User' -and
            $_.AccountEnabled -ne $false -and
            (-not [string]::IsNullOrWhiteSpace($_.Mail) -or -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName))
        }
    )

    $orphanRecord = $null
    if ($ownerRecords.Count -eq 0) {
        $orphanRecord = [pscustomobject]@{
            SubscriptionId    = $Candidate.SubscriptionId
            SubscriptionName  = $Candidate.SubscriptionName
            Reason            = 'NoOwner'
            RecommendedAction = 'Hold for review or deletion; do not migrate automatically.'
        }
    }
    elseif ($notifiableOwners.Count -eq 0) {
        $orphanRecord = [pscustomobject]@{
            SubscriptionId    = $Candidate.SubscriptionId
            SubscriptionName  = $Candidate.SubscriptionName
            Reason            = 'NoResolvableOwner'
            RecommendedAction = 'Manual review required; owner exists but cannot be auto-preserved.'
        }
    }

    Write-RunLog -RunContext $RunContext -Level $(if ($orphanRecord) { 'Warning' } else { 'Information' }) -Stage 'OwnerSnapshot' -SubscriptionId $Candidate.SubscriptionId -Message 'Owner snapshot completed.' -Data @{ OwnerCount = $ownerRecords.Count; NotifiableOwnerCount = $notifiableOwners.Count; SnapshotPath = $snapshotPath; OrphanReason = if ($orphanRecord) { $orphanRecord.Reason } else { $null } }

    return [pscustomobject]@{
        Owners               = @($ownerRecords)
        NotifiableOwners     = @($notifiableOwners)
        OrphanRecord         = $orphanRecord
        RawSnapshotPath      = $snapshotPath
        RecommendedStatus    = Update-CandidateStatusFromOwners -Candidate $Candidate -Owners $notifiableOwners -OrphanRecord $orphanRecord
    }
}

function Resolve-SourcePrincipal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RoleAssignment,

        [Parameter()]
        [hashtable]$ResolvedPrincipalMap
    )

    $objectId = Get-RoleAssignmentObjectId -RoleAssignment $RoleAssignment
    $objectType = Get-RoleAssignmentObjectType -RoleAssignment $RoleAssignment

    if ($ResolvedPrincipalMap -and $objectId -and $ResolvedPrincipalMap.ContainsKey($objectId)) {
        $mappedPrincipal = $ResolvedPrincipalMap[$objectId]
        return [pscustomobject]@{
            ResolvedInGraph   = [bool]$mappedPrincipal.ResolvedInGraph
            AccountEnabled    = $mappedPrincipal.AccountEnabled
            Mail              = $mappedPrincipal.Mail
            UserPrincipalName = $mappedPrincipal.UserPrincipalName
            DisplayName       = $mappedPrincipal.DisplayName
        }
    }

    $fallbackPrincipal = [pscustomobject]@{
        ResolvedInGraph   = $false
        AccountEnabled    = $null
        Mail              = $null
        UserPrincipalName = if ($RoleAssignment.PSObject.Properties.Name -contains 'SignInName') { $RoleAssignment.SignInName } else { $null }
        DisplayName       = if ($RoleAssignment.PSObject.Properties.Name -contains 'DisplayName') { $RoleAssignment.DisplayName } else { $null }
    }

    if ([string]::IsNullOrWhiteSpace($objectId)) {
        return $fallbackPrincipal
    }

    try {
        switch ($objectType) {
            'User' {
                if (Get-Command -Name Get-MgUser -ErrorAction SilentlyContinue) {
                    $user = Get-MgUser -UserId $objectId -Property Id,DisplayName,Mail,UserPrincipalName,AccountEnabled -ErrorAction Stop
                    return [pscustomobject]@{
                        ResolvedInGraph   = $true
                        AccountEnabled    = $user.AccountEnabled
                        Mail              = $user.Mail
                        UserPrincipalName = $user.UserPrincipalName
                        DisplayName       = $user.DisplayName
                    }
                }
            }
            'Group' {
                if (Get-Command -Name Get-MgGroup -ErrorAction SilentlyContinue) {
                    $group = Get-MgGroup -GroupId $objectId -Property Id,DisplayName,Mail -ErrorAction Stop
                    return [pscustomobject]@{
                        ResolvedInGraph   = $true
                        AccountEnabled    = $null
                        Mail              = $group.Mail
                        UserPrincipalName = $null
                        DisplayName       = $group.DisplayName
                    }
                }
            }
            'ServicePrincipal' {
                if (Get-Command -Name Get-MgServicePrincipal -ErrorAction SilentlyContinue) {
                    $servicePrincipal = Get-MgServicePrincipal -ServicePrincipalId $objectId -Property Id,DisplayName,AppId -ErrorAction Stop
                    return [pscustomobject]@{
                        ResolvedInGraph   = $true
                        AccountEnabled    = $null
                        Mail              = $null
                        UserPrincipalName = $servicePrincipal.AppId
                        DisplayName       = $servicePrincipal.DisplayName
                    }
                }
            }
        }
    }
    catch {
        return $fallbackPrincipal
    }

    return $fallbackPrincipal
}

function Get-SubscriptionResourceRisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$Candidate,

        [Parameter()]
        [object[]]$Resources,

        [Parameter()]
        [string[]]$BlockedResourceTypes = $script:KnownBlockedRiskTypes
    )

    $snapshotPath = Join-Path $RunContext.ArtifactFiles.Raw ("resources-{0}.json" -f $Candidate.SubscriptionId)
    $effectiveResources = if ($PSBoundParameters.ContainsKey('Resources')) {
        @($Resources)
    }
    else {
        if (-not (Get-Command -Name Get-AzResource -ErrorAction SilentlyContinue)) {
            throw 'Get-AzResource is not available. Install Az.Resources before running resource-risk inspection.'
        }

        if (Get-Command -Name Set-AzContext -ErrorAction SilentlyContinue) {
            Set-AzContext -Tenant $RunContext.Configuration.CurrentTenantId -SubscriptionId $Candidate.SubscriptionId | Out-Null
        }

        @(Get-AzResource -ExpandProperties -ErrorAction Stop)
    }

    ConvertTo-JsonDocument -InputObject $effectiveResources -Depth 12 | Set-Content -LiteralPath $snapshotPath -Encoding utf8

    $resourceTypes = @($effectiveResources | ForEach-Object { Get-ResourceTypeName -Resource $_ })
    $resourceCount = $resourceTypes.Count
    $riskyTypes = @($resourceTypes | Where-Object { $_ -in $script:KnownRiskTypes } | Sort-Object -Unique)
    $blockingTypes = @($resourceTypes | Where-Object { $_ -in $BlockedResourceTypes } | Sort-Object -Unique)

    $riskLevel = switch ($true) {
        ($blockingTypes.Count -gt 0) { 'Blocked'; break }
        ($resourceCount -eq 0) { 'Low'; break }
        ($riskyTypes.Count -gt 0) { 'High'; break }
        default { 'Medium' }
    }

    $notes = switch ($riskLevel) {
        'Low' { 'No resources detected.'; break }
        'Medium' { 'Resources exist but no known tenant-bound resource types were detected.'; break }
        'High' { 'Tenant-bound resource types were detected and may require remediation after transfer.'; break }
        'Blocked' { 'Known blocking resource types were detected. Manual review required before migration.'; break }
    }

    Write-RunLog -RunContext $RunContext -Level $(if ($riskLevel -in @('High', 'Blocked')) { 'Warning' } else { 'Information' }) -Stage 'RiskInspection' -SubscriptionId $Candidate.SubscriptionId -Message 'Resource risk inspection completed.' -Data @{ ResourceCount = $resourceCount; RiskLevel = $riskLevel; RiskyTypes = $riskyTypes; BlockingTypes = $blockingTypes; SnapshotPath = $snapshotPath }

    return [pscustomobject]@{
        SubscriptionId   = $Candidate.SubscriptionId
        SubscriptionName = $Candidate.SubscriptionName
        RiskLevel        = $riskLevel
        ResourceCount    = $resourceCount
        RiskyTypes       = @($riskyTypes)
        BlockingTypes    = @($blockingTypes)
        RawSnapshotPath  = $snapshotPath
        Notes            = $notes
    }
}

function Invoke-DiscoveryCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    Connect-SourceTenant -RunContext $RunContext
    $candidates = Get-CandidateSubscriptions -Configuration $Configuration
    $owners = @()
    $orphans = @()

    $updatedCandidates = foreach ($candidate in $candidates) {
        $workingCandidate = [pscustomobject]@{
            SubscriptionId   = $candidate.SubscriptionId
            SubscriptionName = $candidate.SubscriptionName
            State            = $candidate.State
            MatchRegex       = $candidate.MatchRegex
            Status           = $candidate.Status
            RiskLevel        = $candidate.RiskLevel
            TenantId         = $candidate.TenantId
        }

        if ($workingCandidate.Status -notin @('AlreadyInTarget', 'Blocked')) {
            try {
                $riskAssessment = Get-SubscriptionResourceRisk -RunContext $RunContext -Candidate $workingCandidate
                $workingCandidate.RiskLevel = $riskAssessment.RiskLevel
                if ($workingCandidate.Status -eq 'Candidate' -and $riskAssessment.RiskLevel -eq 'Blocked') {
                    $workingCandidate.Status = 'Blocked'
                }
            }
            catch {
                Write-RunLog -RunContext $RunContext -Level Warning -Stage 'RiskInspection' -SubscriptionId $workingCandidate.SubscriptionId -Message 'Resource risk inspection failed; leaving risk level as Unknown.' -Failure $_.Exception
            }
        }

        if ($workingCandidate.Status -eq 'Candidate') {
            $snapshot = Get-SubscriptionOwnerSnapshot -RunContext $RunContext -Candidate $workingCandidate
            $owners += @($snapshot.Owners)
            if ($snapshot.OrphanRecord) {
                $orphans += $snapshot.OrphanRecord
            }

            $workingCandidate.Status = $snapshot.RecommendedStatus
        }

        $workingCandidate
    }

    return [pscustomobject]@{
        Candidates = @($updatedCandidates)
        Owners     = @($owners)
        Orphans    = @($orphans)
    }
}

function Get-TemplateContent {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter()]
        [string]$TemplatePath
    )

    $effectiveTemplatePath = if (-not [string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath
    }
    else {
        Join-Path $RunContext.RepositoryRoot 'Templates\owner-notification.md'
    }

    if (-not (Test-Path -LiteralPath $effectiveTemplatePath)) {
        throw "Notification template not found at '$effectiveTemplatePath'."
    }

    return Get-Content -LiteralPath $effectiveTemplatePath -Raw
}

function Build-NotificationContent {
    param(
        [Parameter(Mandatory)]
        [string]$TemplateContent,

        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$OwnerRecord
    )

    $deadline = if (-not [string]::IsNullOrWhiteSpace([string]$RunContext.Configuration.NotificationDeadline)) {
        [string]$RunContext.Configuration.NotificationDeadline
    }
    else {
        (Get-Date).AddDays(14).ToString('yyyy-MM-dd')
    }

    $replacements = @{
        '{{SubscriptionName}}'   = $OwnerRecord.SubscriptionName
        '{{SubscriptionId}}'     = $OwnerRecord.SubscriptionId
        '{{SourceTenantId}}'     = $RunContext.Configuration.CurrentTenantId
        '{{TargetTenantId}}'     = $RunContext.Configuration.TargetTenantId
        '{{NotificationDeadline}}' = $deadline
        '{{ChangeTicketId}}'     = $RunContext.Configuration.ChangeTicketId
    }

    $body = $TemplateContent
    foreach ($entry in $replacements.GetEnumerator()) {
        $safeValue = if ($null -eq $entry.Value) { '' } else { [string]$entry.Value }
        $body = $body.Replace($entry.Key, $safeValue)
    }

    $subject = 'Action notice: Azure subscription will move to holding tenant'
    if ($body -match '^(?im)Subject:\s*(.+)$') {
        $subject = $matches[1].Trim()
        $body = [regex]::Replace($body, '^(?im)Subject:\s*.+\r?\n?', '', 1)
    }

    return [pscustomobject]@{
        Subject = $subject
        Body    = $body.Trim()
    }
}

function Export-NotificationReport {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter()]
        [object[]]$Notifications = @()
    )

    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Notifications -InputObject $Notifications -Headers $script:CsvColumns.Notifications
}

function Export-PreflightReport {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter()]
        [object[]]$PreflightResults = @()
    )

    Export-StructuredCsv -Path $RunContext.ArtifactFiles.Preflight -InputObject $PreflightResults -Headers $script:CsvColumns.Preflight
}

function Get-OwnerNotificationRecipient {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$OwnerRecord
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$OwnerRecord.Mail)) {
        return [string]$OwnerRecord.Mail
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$OwnerRecord.UserPrincipalName)) {
        return [string]$OwnerRecord.UserPrincipalName
    }

    return $null
}

function Get-NotificationTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Owners
    )

    $seen = @{}
    $targets = foreach ($owner in $Owners) {
        if ($owner.Action -ne 'NotifyAndPreserve') {
            continue
        }

        $recipient = Get-OwnerNotificationRecipient -OwnerRecord $owner
        if ([string]::IsNullOrWhiteSpace($recipient)) {
            continue
        }

        $key = "{0}|{1}" -f $owner.SubscriptionId, $recipient.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $owner
    }

    return @($targets)
}

function Get-TransferSupportSignal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext
    )

    $proofPath = Join-Path $RunContext.RepositoryRoot 'docs\pilot-transfer-proof.md'
    if (-not (Test-Path -LiteralPath $proofPath)) {
        return $false
    }

    $proofContent = Get-Content -LiteralPath $proofPath -Raw
    return [bool]($proofContent -match '(?im)^SUPPORTED_TRANSFER_PATH_VALIDATED\s*[:=]\s*true\s*$')
}

function Test-TenantAzAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$StageName
    )

    try {
        if (-not (Get-Command -Name Connect-AzAccount -ErrorAction SilentlyContinue)) {
            return $false
        }

        Connect-AzAccount -Tenant $TenantId | Out-Null
        Set-AzContext -Tenant $TenantId | Out-Null
        [void](Get-AzSubscription -TenantId $TenantId -ErrorAction Stop | Select-Object -First 1)
        Write-RunLog -RunContext $RunContext -Level Information -Stage $StageName -Message 'Tenant access check succeeded.' -Data @{ TenantId = $TenantId }
        return $true
    }
    catch {
        Write-RunLog -RunContext $RunContext -Level Warning -Stage $StageName -Message 'Tenant access check failed.' -Failure $_.Exception -Data @{ TenantId = $TenantId }
        return $false
    }
}

function Send-OwnerNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$OwnerRecord,

        [Parameter()]
        [string]$TemplatePath,

        [Parameter()]
        [switch]$SkipDelivery
    )

    $recipient = if (-not [string]::IsNullOrWhiteSpace($OwnerRecord.Mail)) {
        $OwnerRecord.Mail
    }
    else {
        $OwnerRecord.UserPrincipalName
    }

    if ([string]::IsNullOrWhiteSpace($recipient)) {
        return [pscustomobject]@{
            SubscriptionId = $OwnerRecord.SubscriptionId
            Recipient      = $null
            Channel        = $RunContext.Configuration.NotificationMode
            Sent           = $false
            SentAt         = $null
            Error          = 'Owner record does not contain Mail or UserPrincipalName.'
        }
    }

    if ($RunContext.Configuration.NotificationMode -eq 'None' -or $SkipDelivery) {
        Write-RunLog -RunContext $RunContext -Level Information -Stage 'Notification' -SubscriptionId $OwnerRecord.SubscriptionId -Message 'Notification skipped due to mode/WhatIf.' -Data @{ Recipient = $recipient }
        return [pscustomobject]@{
            SubscriptionId = $OwnerRecord.SubscriptionId
            Recipient      = $recipient
            Channel        = $RunContext.Configuration.NotificationMode
            Sent           = $false
            SentAt         = $null
            Error          = $null
        }
    }

    if ($RunContext.Configuration.NotificationMode -ne 'Email') {
        return [pscustomobject]@{
            SubscriptionId = $OwnerRecord.SubscriptionId
            Recipient      = $recipient
            Channel        = $RunContext.Configuration.NotificationMode
            Sent           = $false
            SentAt         = $null
            Error          = 'Only Email notification mode is implemented in this slice.'
        }
    }

    $templateContent = Get-TemplateContent -RunContext $RunContext -TemplatePath $TemplatePath
    $rendered = Build-NotificationContent -TemplateContent $templateContent -RunContext $RunContext -OwnerRecord $OwnerRecord

    try {
        if (-not (Get-Command -Name Send-MgUserMail -ErrorAction SilentlyContinue)) {
            throw 'Send-MgUserMail is not available. Install Microsoft.Graph.Users.Actions before running Notify mode.'
        }

        $mailBody = @{
            Message = @{
                Subject = $rendered.Subject
                Body = @{
                    ContentType = 'Text'
                    Content = $rendered.Body
                }
                ToRecipients = @(
                    @{
                        EmailAddress = @{
                            Address = $recipient
                        }
                    }
                )
            }
            SaveToSentItems = $true
        }

        Send-MgUserMail -UserId $RunContext.Configuration.SenderUserId -BodyParameter $mailBody -ErrorAction Stop
        Write-RunLog -RunContext $RunContext -Level Information -Stage 'Notification' -SubscriptionId $OwnerRecord.SubscriptionId -Message 'Owner notification sent.' -Data @{ Recipient = $recipient }

        return [pscustomobject]@{
            SubscriptionId = $OwnerRecord.SubscriptionId
            Recipient      = $recipient
            Channel        = 'Email'
            Sent           = $true
            SentAt         = (Get-Date).ToUniversalTime().ToString('o')
            Error          = $null
        }
    }
    catch {
        Write-RunLog -RunContext $RunContext -Level Error -Stage 'Notification' -SubscriptionId $OwnerRecord.SubscriptionId -Message 'Failed to send owner notification.' -Failure $_.Exception -Data @{ Recipient = $recipient }

        return [pscustomobject]@{
            SubscriptionId = $OwnerRecord.SubscriptionId
            Recipient      = $recipient
            Channel        = 'Email'
            Sent           = $false
            SentAt         = $null
            Error          = $_.Exception.Message
        }
    }
}

function Set-TargetGuestUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$OwnerRecord,

        [Parameter()]
        [hashtable]$ExistingUsersByKey
    )

    if ($OwnerRecord.SourcePrincipalType -ne 'User') {
        return [pscustomobject]@{
            SubscriptionId    = $OwnerRecord.SubscriptionId
            SourcePrincipalId = $OwnerRecord.SourcePrincipalId
            TargetPrincipalId = $null
            TargetPrincipalType = $null
            Action            = 'SkippedNonUserPrincipal'
            CanCreateGuest    = $false
            Error             = $null
        }
    }

    $identityKeys = @($OwnerRecord.Mail, $OwnerRecord.UserPrincipalName) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    foreach ($key in $identityKeys) {
        if ($ExistingUsersByKey -and $ExistingUsersByKey.ContainsKey($key)) {
            $user = $ExistingUsersByKey[$key]
            return [pscustomobject]@{
                SubscriptionId      = $OwnerRecord.SubscriptionId
                SourcePrincipalId   = $OwnerRecord.SourcePrincipalId
                TargetPrincipalId   = $user.Id
                TargetPrincipalType = 'User'
                Action              = 'MatchedExistingTargetUser'
                CanCreateGuest      = $true
                Error               = $null
            }
        }
    }

    if (-not $RunContext.Configuration.InviteOwnersToTargetTenant) {
        return [pscustomobject]@{
            SubscriptionId      = $OwnerRecord.SubscriptionId
            SourcePrincipalId   = $OwnerRecord.SourcePrincipalId
            TargetPrincipalId   = $null
            TargetPrincipalType = $null
            Action              = 'InviteDisabledByConfiguration'
            CanCreateGuest      = $false
            Error               = $null
        }
    }

    if ($RunContext.Configuration.WhatIf) {
        return [pscustomobject]@{
            SubscriptionId      = $OwnerRecord.SubscriptionId
            SourcePrincipalId   = $OwnerRecord.SourcePrincipalId
            TargetPrincipalId   = $null
            TargetPrincipalType = 'User'
            Action              = 'WouldInviteGuest'
            CanCreateGuest      = $true
            Error               = $null
        }
    }

    try {
        if (-not (Get-Command -Name New-MgInvitation -ErrorAction SilentlyContinue)) {
            throw 'New-MgInvitation is not available. Install Microsoft.Graph.Identity.SignIns before running Preflight guest preparation.'
        }

        $inviteAddress = if (-not [string]::IsNullOrWhiteSpace($OwnerRecord.Mail)) { $OwnerRecord.Mail } else { $OwnerRecord.UserPrincipalName }
        $invitation = New-MgInvitation -InvitedUserEmailAddress $inviteAddress -InviteRedirectUrl 'https://portal.azure.com' -SendInvitationMessage:$true -ErrorAction Stop
        $targetId = if ($invitation.InvitedUser.Id) { $invitation.InvitedUser.Id } else { $invitation.InvitedUserId }

        return [pscustomobject]@{
            SubscriptionId      = $OwnerRecord.SubscriptionId
            SourcePrincipalId   = $OwnerRecord.SourcePrincipalId
            TargetPrincipalId   = $targetId
            TargetPrincipalType = 'User'
            Action              = 'InvitedGuestUser'
            CanCreateGuest      = $true
            Error               = $null
        }
    }
    catch {
        return [pscustomobject]@{
            SubscriptionId      = $OwnerRecord.SubscriptionId
            SourcePrincipalId   = $OwnerRecord.SourcePrincipalId
            TargetPrincipalId   = $null
            TargetPrincipalType = $null
            Action              = 'GuestInviteFailed'
            CanCreateGuest      = $false
            Error               = $_.Exception.Message
        }
    }
}

function Build-OwnerMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [object[]]$Owners,

        [Parameter()]
        [hashtable]$ExistingUsersByKey
    )

    $results = foreach ($owner in $Owners) {
        $mapping = Set-TargetGuestUser -RunContext $RunContext -OwnerRecord $owner -ExistingUsersByKey $ExistingUsersByKey
        [pscustomobject]@{
            SubscriptionId    = $owner.SubscriptionId
            SourcePrincipalId = $owner.SourcePrincipalId
            TargetPrincipalId = $mapping.TargetPrincipalId
            TargetPrincipalType = $mapping.TargetPrincipalType
            Action            = $mapping.Action
            Error             = $mapping.Error
        }
    }

    return @($results)
}

function Test-TransferPrerequisites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [object[]]$Candidates,

        [Parameter(Mandatory)]
        [object[]]$Owners,

        [Parameter()]
        [hashtable]$ExistingUsersByKey,

        [Parameter()]
        [bool]$CanReadRbac = $true,

        [Parameter()]
        [bool]$CanAccessTargetTenant = $true,

        [Parameter()]
        [bool]$TransferSupported = $false
    )

    $ownerMappings = Build-OwnerMapping -RunContext $RunContext -Owners $Owners -ExistingUsersByKey $ExistingUsersByKey
    $ownerLookup = $Owners | Group-Object -Property SubscriptionId -AsHashTable -AsString
    $mappingLookup = $ownerMappings | Group-Object -Property SubscriptionId -AsHashTable -AsString

    $results = foreach ($candidate in $Candidates) {
        $candidateOwners = if ($ownerLookup.ContainsKey($candidate.SubscriptionId)) { @($ownerLookup[$candidate.SubscriptionId]) } else { @() }
        $candidateMappings = if ($mappingLookup.ContainsKey($candidate.SubscriptionId)) { @($mappingLookup[$candidate.SubscriptionId]) } else { @() }

        $hasOwner = @($candidateOwners).Count -gt 0
        $resolvableOwners = @($candidateOwners | Where-Object { $_.SourcePrincipalType -eq 'User' -and $_.AccountEnabled -ne $false -and (-not [string]::IsNullOrWhiteSpace($_.Mail) -or -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName)) })
        $hasResolvableOwner = @($resolvableOwners).Count -gt 0
        $canCreateGuest = @($candidateMappings | Where-Object { $_.TargetPrincipalId -or $_.Action -eq 'WouldInviteGuest' -or $_.Action -eq 'InvitedGuestUser' }).Count -gt 0
        $decision = switch ($true) {
            (-not $CanReadRbac) { 'BlockedPreflight'; break }
            (-not $CanAccessTargetTenant) { 'BlockedPreflight'; break }
            ($candidate.Status -in @('Blocked', 'UnsupportedBillingType', 'NoOwner', 'AlreadyInTarget', 'Disabled')) { 'NoAction'; break }
            (-not $hasOwner) { 'NoAction'; break }
            (-not $hasResolvableOwner) { 'NoAction'; break }
            (-not $TransferSupported) { 'ReadyForManualTransferValidation' ; break }
            default { 'ReadyForMigration' }
        }

        [pscustomobject]@{
            SubscriptionId     = $candidate.SubscriptionId
            CanReadRbac        = $CanReadRbac
            HasOwner           = $hasOwner
            HasResolvableOwner = $hasResolvableOwner
            CanCreateTargetGuest = ($CanAccessTargetTenant -and $canCreateGuest)
            TransferSupported  = $TransferSupported
            RiskLevel          = $candidate.RiskLevel
            Decision           = $decision
        }
    }

    return [pscustomobject]@{
        Results       = @($results)
        OwnerMappings = @($ownerMappings)
    }
}

function Connect-GraphTenant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string[]]$Scopes
    )

    if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
        throw 'Connect-MgGraph is not available. Install Microsoft.Graph.Authentication before using Graph-dependent modes.'
    }

    Connect-MgGraph -TenantId $TenantId -Scopes $Scopes -NoWelcome -ErrorAction Stop | Out-Null
}

function Get-TargetUserLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Owners
    )

    $lookup = @{}
    $keys = @($Owners | ForEach-Object { @($_.Mail, $_.UserPrincipalName) } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)

    foreach ($key in $keys) {
        try {
            if (Get-Command -Name Get-MgUser -ErrorAction SilentlyContinue) {
                $escaped = $key.Replace("'", "''")
                $user = Get-MgUser -Filter "mail eq '$escaped' or userPrincipalName eq '$escaped'" -ConsistencyLevel eventual -CountVariable _ignore -Top 1 -ErrorAction Stop | Select-Object -First 1
                if ($user) {
                    $lookup[$key] = $user
                }
            }
        }
        catch {
            continue
        }
    }

    return $lookup
}

function Import-CsvIfPresent {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    try {
        return @(Import-Csv -LiteralPath $Path)
    }
    catch {
        return @()
    }
}

function Import-MigrationCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext,

        [Parameter(Mandatory)]
        [pscustomobject]$Configuration
    )

    $candidatePath = if (-not [string]::IsNullOrWhiteSpace($Configuration.CandidateCsvPath)) {
        $Configuration.CandidateCsvPath
    }
    else {
        $RunContext.ArtifactFiles.Candidates
    }

    if (-not (Test-Path -LiteralPath $candidatePath)) {
        throw "Candidate CSV '$candidatePath' was not found."
    }

    $rows = Import-Csv -LiteralPath $candidatePath
    return @($rows | ForEach-Object {
        [pscustomobject]@{
            SubscriptionId   = $_.SubscriptionId
            SubscriptionName = $_.SubscriptionName
            State            = $_.State
            MatchRegex       = $_.MatchRegex
            Status           = $_.Status
            RiskLevel        = if ($_.RiskLevel) { $_.RiskLevel } else { 'Unknown' }
        }
    })
}

function Get-MigrationExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Candidates,

        [Parameter()]
        [object[]]$ExistingMigrationResults = @(),

        [Parameter()]
        [bool]$TransferSupported = $false,

        [Parameter()]
        [bool]$WhatIfMode = $true
    )

    $existingLookup = @{}
    if (@($ExistingMigrationResults).Count -gt 0) {
        $existingLookup = $ExistingMigrationResults | Group-Object -Property SubscriptionId -AsHashTable -AsString
    }

    $plan = foreach ($candidate in $Candidates) {
        $previous = if ($existingLookup.ContainsKey($candidate.SubscriptionId)) {
            @($existingLookup[$candidate.SubscriptionId]) | Select-Object -Last 1
        }
        else {
            $null
        }

        if ($previous -and $previous.TransferStatus -in @('Succeeded', 'SkippedNoAction', 'BlockedNoSupportedPath') -and $previous.ValidationStatus -in @('Validated', 'Skipped', 'PendingManualValidation')) {
            [pscustomobject]@{
                SubscriptionId = $candidate.SubscriptionId
                SubscriptionName = $candidate.SubscriptionName
                ExecutionAction = 'ResumeSkipCompleted'
                PlannedTransferStatus = $previous.TransferStatus
                PlannedOwnerRestoreStatus = $previous.OwnerRestoreStatus
                PlannedValidationStatus = $previous.ValidationStatus
                PlannedError = $previous.Error
            }
            continue
        }

        if ($candidate.Status -in @('Blocked', 'NoOwner', 'UnsupportedBillingType', 'AlreadyInTarget', 'Disabled')) {
            [pscustomobject]@{
                SubscriptionId = $candidate.SubscriptionId
                SubscriptionName = $candidate.SubscriptionName
                ExecutionAction = 'NoAction'
                PlannedTransferStatus = 'SkippedNoAction'
                PlannedOwnerRestoreStatus = 'Skipped'
                PlannedValidationStatus = 'Skipped'
                PlannedError = "Status '$($candidate.Status)' is excluded from migration."
            }
            continue
        }

        if ($WhatIfMode) {
            [pscustomobject]@{
                SubscriptionId = $candidate.SubscriptionId
                SubscriptionName = $candidate.SubscriptionName
                ExecutionAction = 'NoAction'
                PlannedTransferStatus = 'SkippedWhatIf'
                PlannedOwnerRestoreStatus = 'Skipped'
                PlannedValidationStatus = 'Skipped'
                PlannedError = 'WhatIf mode does not execute migration actions.'
            }
            continue
        }

        if (-not $TransferSupported) {
            [pscustomobject]@{
                SubscriptionId = $candidate.SubscriptionId
                SubscriptionName = $candidate.SubscriptionName
                ExecutionAction = 'NoAction'
                PlannedTransferStatus = 'BlockedNoSupportedPath'
                PlannedOwnerRestoreStatus = 'NotStarted'
                PlannedValidationStatus = 'PendingManualValidation'
                PlannedError = 'Supported transfer mechanism has not been validated. See docs/pilot-transfer-proof.md.'
            }
            continue
        }

        [pscustomobject]@{
            SubscriptionId = $candidate.SubscriptionId
            SubscriptionName = $candidate.SubscriptionName
            ExecutionAction = 'Execute'
            PlannedTransferStatus = 'PendingExecution'
            PlannedOwnerRestoreStatus = 'NotStarted'
            PlannedValidationStatus = 'NotStarted'
            PlannedError = $null
        }
    }

    return @($plan)
}

function Convert-PlanToMigrationRows {
    param(
        [Parameter(Mandatory)]
        [object[]]$Plan
    )

    return @($Plan | ForEach-Object {
        [pscustomobject]@{
            SubscriptionId     = $_.SubscriptionId
            StartedAt          = $null
            CompletedAt        = $null
            TransferStatus     = $_.PlannedTransferStatus
            OwnerRestoreStatus = $_.PlannedOwnerRestoreStatus
            ValidationStatus   = $_.PlannedValidationStatus
            Error              = $_.PlannedError
        }
    })
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
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RunContext
    )

    $candidates = Import-CsvIfPresent -Path $RunContext.ArtifactFiles.Candidates
    $owners = Import-CsvIfPresent -Path $RunContext.ArtifactFiles.Owners
    $notifications = Import-CsvIfPresent -Path $RunContext.ArtifactFiles.Notifications
    $preflight = Import-CsvIfPresent -Path $RunContext.ArtifactFiles.Preflight
    $migration = Import-CsvIfPresent -Path $RunContext.ArtifactFiles.Migration
    $validation = Import-CsvIfPresent -Path $RunContext.ArtifactFiles.PostValidation

    $summary = [ordered]@{
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        RunRoot = $RunContext.RunRoot
        CandidateCount = @($candidates).Count
        OwnerCount = @($owners).Count
        NotificationCount = @($notifications).Count
        PreflightCount = @($preflight).Count
        MigrationCount = @($migration).Count
        ValidationCount = @($validation).Count
        TransferSucceededCount = @($migration | Where-Object { $_.TransferStatus -eq 'Succeeded' }).Count
        TransferBlockedCount = @($migration | Where-Object { $_.TransferStatus -eq 'BlockedNoSupportedPath' }).Count
        TransferFailedCount = @($migration | Where-Object { $_.TransferStatus -eq 'Failed' }).Count
    }

    $path = Join-Path $RunContext.RunRoot 'final-report.json'
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8

    Write-RunLog -RunContext $RunContext -Level Information -Stage 'Report' -Message 'Final report exported.' -Data @{ Path = $path }
    return [pscustomobject]$summary
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
                $discovery = Invoke-DiscoveryCollection -RunContext $runContext -Configuration $configuration
                Export-DiscoveryReports -RunContext $runContext -Candidates $discovery.Candidates -Owners $discovery.Owners -Orphans $discovery.Orphans
                Write-RunLog -RunContext $runContext -Level Information -Stage 'Discovery' -Message 'Discovery completed.' -Data @{ CandidateCount = $discovery.Candidates.Count; OwnerCount = $discovery.Owners.Count; OrphanCount = $discovery.Orphans.Count }

                return [pscustomobject]@{
                    Mode           = $configuration.Mode
                    RunRoot        = $runContext.RunRoot
                    CandidateCount = $discovery.Candidates.Count
                    OwnerCount     = $discovery.Owners.Count
                    OrphanCount    = $discovery.Orphans.Count
                }
            }
            'Notify' {
                $discovery = Invoke-DiscoveryCollection -RunContext $runContext -Configuration $configuration
                Export-DiscoveryReports -RunContext $runContext -Candidates $discovery.Candidates -Owners $discovery.Owners -Orphans $discovery.Orphans

                $notificationCandidates = Get-NotificationTargets -Owners $discovery.Owners
                $notifications = @()

                if ($configuration.NotificationMode -eq 'Email' -and -not $configuration.WhatIf) {
                    Connect-GraphTenant -RunContext $runContext -TenantId $configuration.CurrentTenantId -Scopes @('Mail.Send', 'User.Read.All')
                }

                foreach ($ownerRecord in $notificationCandidates) {
                    $notifications += Send-OwnerNotification -RunContext $runContext -OwnerRecord $ownerRecord -SkipDelivery:$configuration.WhatIf
                }

                Export-NotificationReport -RunContext $runContext -Notifications $notifications
                Write-RunLog -RunContext $runContext -Level Information -Stage 'Notify' -Message 'Notify mode completed.' -Data @{ NotificationCandidateCount = $notificationCandidates.Count; SentCount = @($notifications | Where-Object { $_.Sent }).Count }

                return [pscustomobject]@{
                    Mode                     = $configuration.Mode
                    RunRoot                  = $runContext.RunRoot
                    CandidateCount           = $discovery.Candidates.Count
                    NotificationCandidateCount = $notificationCandidates.Count
                    SentCount                = @($notifications | Where-Object { $_.Sent }).Count
                }
            }
            'Preflight' {
                $discovery = Invoke-DiscoveryCollection -RunContext $runContext -Configuration $configuration
                Export-DiscoveryReports -RunContext $runContext -Candidates $discovery.Candidates -Owners $discovery.Owners -Orphans $discovery.Orphans

                $existingUsersByKey = @{}
                $canReadRbac = Test-TenantAzAccess -RunContext $runContext -TenantId $configuration.CurrentTenantId -StageName 'PreflightSourceAccess'
                $canAccessTargetTenant = Test-TenantAzAccess -RunContext $runContext -TenantId $configuration.TargetTenantId -StageName 'PreflightTargetAccess'
                $transferSupported = Get-TransferSupportSignal -RunContext $runContext

                if ($canAccessTargetTenant -and -not $configuration.WhatIf) {
                    Connect-GraphTenant -RunContext $runContext -TenantId $configuration.TargetTenantId -Scopes @('User.Read.All', 'User.ReadWrite.All', 'Directory.ReadWrite.All', 'User.Invite.All')
                    $existingUsersByKey = Get-TargetUserLookup -Owners $discovery.Owners
                }

                $preflight = Test-TransferPrerequisites -RunContext $runContext -Candidates $discovery.Candidates -Owners $discovery.Owners -ExistingUsersByKey $existingUsersByKey -CanReadRbac:$canReadRbac -CanAccessTargetTenant:$canAccessTargetTenant -TransferSupported:$transferSupported
                Export-PreflightReport -RunContext $runContext -PreflightResults $preflight.Results

                Write-RunLog -RunContext $runContext -Level Information -Stage 'Preflight' -Message 'Preflight mode completed.' -Data @{ ResultCount = $preflight.Results.Count; ReadyCount = @($preflight.Results | Where-Object { $_.Decision -eq 'ReadyForManualTransferValidation' }).Count }

                return [pscustomobject]@{
                    Mode        = $configuration.Mode
                    RunRoot     = $runContext.RunRoot
                    ResultCount = $preflight.Results.Count
                    ReadyCount  = @($preflight.Results | Where-Object { $_.Decision -eq 'ReadyForManualTransferValidation' }).Count
                }
            }
            'Migrate' {
                $candidates = Import-MigrationCandidates -RunContext $runContext -Configuration $configuration
                $existingMigration = Import-CsvIfPresent -Path $runContext.ArtifactFiles.Migration
                $transferSupported = Get-TransferSupportSignal -RunContext $runContext
                $plan = Get-MigrationExecutionPlan -Candidates $candidates -ExistingMigrationResults $existingMigration -TransferSupported:$transferSupported -WhatIfMode:$configuration.WhatIf

                $rows = Convert-PlanToMigrationRows -Plan $plan
                foreach ($row in $rows) {
                    $planItem = @($plan | Where-Object { $_.SubscriptionId -eq $row.SubscriptionId } | Select-Object -First 1)
                    if (-not $planItem) {
                        continue
                    }

                    if ($planItem.ExecutionAction -ne 'Execute') {
                        continue
                    }

                    $row.StartedAt = (Get-Date).ToUniversalTime().ToString('o')
                    try {
                        Invoke-SubscriptionDirectoryTransfer -SubscriptionId $row.SubscriptionId -SourceTenantId $configuration.CurrentTenantId -TargetTenantId $configuration.TargetTenantId
                        $row.TransferStatus = 'Succeeded'

                        try {
                            Grant-TargetOwnerAccess
                            $row.OwnerRestoreStatus = 'Succeeded'
                        }
                        catch {
                            $row.OwnerRestoreStatus = 'Failed'
                            $row.Error = $_.Exception.Message
                        }

                        try {
                            Test-PostTransferAccess
                            $row.ValidationStatus = 'Validated'
                        }
                        catch {
                            $row.ValidationStatus = 'Failed'
                            if (-not $row.Error) {
                                $row.Error = $_.Exception.Message
                            }
                        }
                    }
                    catch {
                        $row.TransferStatus = 'Failed'
                        $row.OwnerRestoreStatus = 'Skipped'
                        $row.ValidationStatus = 'Skipped'
                        $row.Error = $_.Exception.Message
                    }
                    finally {
                        $row.CompletedAt = (Get-Date).ToUniversalTime().ToString('o')
                    }
                }

                Export-StructuredCsv -Path $runContext.ArtifactFiles.Migration -InputObject $rows -Headers $script:CsvColumns.Migration
                Write-RunLog -RunContext $runContext -Level Information -Stage 'Migrate' -Message 'Migrate mode completed.' -Data @{ PlannedCount = $plan.Count; ExecutedCount = @($plan | Where-Object { $_.ExecutionAction -eq 'Execute' }).Count }

                return [pscustomobject]@{
                    Mode = $configuration.Mode
                    RunRoot = $runContext.RunRoot
                    PlannedCount = $plan.Count
                    ExecutedCount = @($plan | Where-Object { $_.ExecutionAction -eq 'Execute' }).Count
                    FailedCount = @($rows | Where-Object { $_.TransferStatus -eq 'Failed' }).Count
                }
            }
            'Validate' {
                $migrationRows = Import-CsvIfPresent -Path $runContext.ArtifactFiles.Migration
                if (@($migrationRows).Count -eq 0) {
                    $validationRows = @()
                }
                else {
                    $validationRows = @($migrationRows | ForEach-Object {
                        [pscustomobject]@{
                            SubscriptionId      = $_.SubscriptionId
                            SubscriptionName    = ''
                            ExpectedTenantId    = $configuration.TargetTenantId
                            ActualTenantId      = ''
                            MigrationAdminOwner = $false
                            PreservedOwnerCount = 0
                            MissingOwnerCount   = 0
                            Status              = if ($_.TransferStatus -eq 'Succeeded') { 'PendingManualValidation' } else { 'Skipped' }
                            Notes               = if ($_.TransferStatus -eq 'Succeeded') { 'Automated deep validation not implemented in this slice.' } else { $_.TransferStatus }
                        }
                    })
                }

                Export-StructuredCsv -Path $runContext.ArtifactFiles.PostValidation -InputObject $validationRows -Headers $script:CsvColumns.PostValidation
                Write-RunLog -RunContext $runContext -Level Information -Stage 'Validate' -Message 'Validate mode completed.' -Data @{ ValidationCount = @($validationRows).Count }

                return [pscustomobject]@{
                    Mode = $configuration.Mode
                    RunRoot = $runContext.RunRoot
                    ValidationCount = @($validationRows).Count
                }
            }
            'Report' {
                $summary = Export-FinalReport -RunContext $runContext
                return [pscustomobject]@{
                    Mode = $configuration.Mode
                    RunRoot = $runContext.RunRoot
                    CandidateCount = $summary.CandidateCount
                    MigrationCount = $summary.MigrationCount
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
