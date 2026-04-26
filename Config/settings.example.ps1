$CurrentTenantId = '<source-tenant-guid>'
$TargetTenantId  = '<target-tenant-guid>'

$SubscriptionNameRegexes = @(
    '^Visual Studio',
    'Visual Studio',
    'DevTest',
    'VS\s+Enterprise',
    'VS\s+Professional'
)

$Mode = 'Discovery'
# Allowed: Discovery, Notify, Preflight, Migrate, Validate, Report

$OutputRoot = '.\SubscriptionEvacuation'

$NotificationMode = 'Email'
# Allowed: None, Email, TeamsChannel

$SenderUserId = 'azure-sub-cleanup@contoso.com'

$InviteOwnersToTargetTenant = $true
$GrantOwnerInTargetTenant = $true

$PreserveOnlySubscriptionOwners = $true
$IncludeInheritedOwners = $true

$MaxParallelism = 8
$ThrottleDelaySeconds = 2

$WhatIf = $true
$ChangeTicketId = 'CHG000000'

$SubscriptionIdAllowList = @()
$SubscriptionIdDenyList = @()

$TargetMigrationAdminObjectId = ''
$TargetMigrationAdminType = 'Group'
$CandidateCsvPath = ''
$NotificationDeadline = (Get-Date).AddDays(14).ToString('yyyy-MM-dd')

$RequiredModules = @(
    'Az.Accounts',
    'Az.Resources',
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Users.Actions',
    'Microsoft.Graph.Identity.SignIns'
)
