Import-Module (Join-Path $PSScriptRoot '..\Modules\BulkVSCodeSubMover\BulkVSCodeSubMover.psd1') -Force

Describe 'Test-RegexConfiguration' {
    It 'accepts valid regexes' {
        { Test-RegexConfiguration -Regexes @('^Visual Studio', 'DevTest') } | Should Not Throw
    }

    It 'rejects invalid regexes' {
        $didThrow = $false

        try {
            Test-RegexConfiguration -Regexes @('[') | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
    }
}

Describe 'Get-CandidateSubscriptions' {
    It 'deduplicates subscriptions and marks statuses' {
        $config = [pscustomobject]@{
            CurrentTenantId = '11111111-1111-1111-1111-111111111111'
            TargetTenantId = '22222222-2222-2222-2222-222222222222'
            SubscriptionNameRegexes = @('Visual Studio', 'DevTest')
            SubscriptionIdAllowList = @()
            SubscriptionIdDenyList = @('sub-blocked')
        }

        $subscriptions = @(
            [pscustomobject]@{ Id = 'sub-1'; Name = 'Visual Studio Alpha'; TenantId = '11111111-1111-1111-1111-111111111111'; State = 'Enabled' },
            [pscustomobject]@{ Id = 'sub-1'; Name = 'Visual Studio Alpha'; TenantId = '11111111-1111-1111-1111-111111111111'; State = 'Enabled' },
            [pscustomobject]@{ Id = 'sub-2'; Name = 'Visual Studio Disabled'; TenantId = '11111111-1111-1111-1111-111111111111'; State = 'Disabled' },
            [pscustomobject]@{ Id = 'sub-3'; Name = 'DevTest Ready'; TenantId = '22222222-2222-2222-2222-222222222222'; State = 'Enabled' },
            [pscustomobject]@{ Id = 'sub-blocked'; Name = 'Visual Studio Pilot'; TenantId = '11111111-1111-1111-1111-111111111111'; State = 'Enabled' }
        )

        $result = Get-CandidateSubscriptions -Configuration $config -Subscriptions $subscriptions

        $result.Count | Should Be 4
        ($result | Where-Object SubscriptionId -eq 'sub-1').Status | Should Be 'Candidate'
        ($result | Where-Object SubscriptionId -eq 'sub-2').Status | Should Be 'Disabled'
        ($result | Where-Object SubscriptionId -eq 'sub-3').Status | Should Be 'AlreadyInTarget'
        ($result | Where-Object SubscriptionId -eq 'sub-blocked').Status | Should Be 'Blocked'
    }
}

Describe 'Assert-MigrateModeAllowed' {
    It 'blocks migrate when WhatIf is true' {
        $config = [pscustomobject]@{
            Mode = 'Migrate'
            WhatIf = $true
            ChangeTicketId = 'CHG123456'
            CandidateCsvPath = 'C:\temp\candidates.csv'
            TargetMigrationAdminObjectId = 'admin-object-id'
        }

        $didThrow = $false

        try {
            Assert-MigrateModeAllowed -Configuration $config | Out-Null
        }
        catch {
            $didThrow = $true
        }

        $didThrow | Should Be $true
    }
}

Describe 'Resolve-SourcePrincipal' {
    It 'uses injected principal mappings before falling back to inline assignment data' {
        $roleAssignment = [pscustomobject]@{
            ObjectId = 'user-1'
            ObjectType = 'User'
            SignInName = 'owner@contoso.com'
            DisplayName = 'Fallback Name'
        }

        $resolved = Resolve-SourcePrincipal -RoleAssignment $roleAssignment -ResolvedPrincipalMap @{
            'user-1' = [pscustomobject]@{
                ResolvedInGraph = $true
                AccountEnabled = $true
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
                DisplayName = 'Resolved Name'
            }
        }

        $resolved.ResolvedInGraph | Should Be $true
        $resolved.DisplayName | Should Be 'Resolved Name'
        $resolved.UserPrincipalName | Should Be 'owner@contoso.com'
    }
}

Describe 'Get-SubscriptionOwnerSnapshot' {
    It 'classifies user owners as ready for notification and writes a raw RBAC snapshot' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $rawRoot = Join-Path $tempRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
                IncludeInheritedOwners = $true
            }
            ArtifactFiles = [pscustomobject]@{
                Raw = $rawRoot
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
        }

        $candidate = [pscustomobject]@{
            SubscriptionId = 'sub-1'
            SubscriptionName = 'Visual Studio Alpha'
            Status = 'Candidate'
        }

        $roleAssignments = @(
            [pscustomobject]@{
                ObjectId = 'user-1'
                ObjectType = 'User'
                SignInName = 'owner@contoso.com'
                DisplayName = 'Owner One'
                RoleDefinitionName = 'Owner'
                Scope = '/subscriptions/sub-1'
            }
        )

        $result = Get-SubscriptionOwnerSnapshot -RunContext $runContext -Candidate $candidate -RoleAssignments $roleAssignments -ResolvedPrincipalMap @{
            'user-1' = [pscustomobject]@{
                ResolvedInGraph = $true
                AccountEnabled = $true
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
                DisplayName = 'Owner One'
            }
        }

        $result.Owners.Count | Should Be 1
        $result.NotifiableOwners.Count | Should Be 1
        $result.RecommendedStatus | Should Be 'ReadyForNotification'
        $result.OrphanRecord | Should Be $null
        (Test-Path -LiteralPath $result.RawSnapshotPath) | Should Be $true

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }

    It 'marks subscriptions without resolvable user owners for manual review' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $rawRoot = Join-Path $tempRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
                IncludeInheritedOwners = $true
            }
            ArtifactFiles = [pscustomobject]@{
                Raw = $rawRoot
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
        }

        $candidate = [pscustomobject]@{
            SubscriptionId = 'sub-2'
            SubscriptionName = 'Visual Studio Group Owned'
            Status = 'Candidate'
        }

        $roleAssignments = @(
            [pscustomobject]@{
                ObjectId = 'group-1'
                ObjectType = 'Group'
                DisplayName = 'Subscription Owners'
                RoleDefinitionName = 'Owner'
                Scope = '/subscriptions/sub-2'
            }
        )

        $result = Get-SubscriptionOwnerSnapshot -RunContext $runContext -Candidate $candidate -RoleAssignments $roleAssignments

        $result.Owners.Count | Should Be 1
        $result.NotifiableOwners.Count | Should Be 0
        $result.RecommendedStatus | Should Be 'NoOwner'
        $result.OrphanRecord.Reason | Should Be 'NoResolvableOwner'

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Describe 'Get-SubscriptionResourceRisk' {
    It 'classifies subscriptions with no resources as low risk' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $rawRoot = Join-Path $tempRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
            }
            ArtifactFiles = [pscustomobject]@{
                Raw = $rawRoot
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
        }

        $candidate = [pscustomobject]@{
            SubscriptionId = 'sub-risk-low'
            SubscriptionName = 'Empty Subscription'
        }

        $result = Get-SubscriptionResourceRisk -RunContext $runContext -Candidate $candidate -Resources @()

        $result.RiskLevel | Should Be 'Low'
        $result.ResourceCount | Should Be 0
        (Test-Path -LiteralPath $result.RawSnapshotPath) | Should Be $true

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }

    It 'classifies subscriptions with ordinary resources as medium risk' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $rawRoot = Join-Path $tempRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
            }
            ArtifactFiles = [pscustomobject]@{
                Raw = $rawRoot
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
        }

        $candidate = [pscustomobject]@{
            SubscriptionId = 'sub-risk-medium'
            SubscriptionName = 'Storage Only'
        }

        $result = Get-SubscriptionResourceRisk -RunContext $runContext -Candidate $candidate -Resources @(
            [pscustomobject]@{ Type = 'Microsoft.Storage/storageAccounts' }
        )

        $result.RiskLevel | Should Be 'Medium'
        $result.ResourceCount | Should Be 1

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }

    It 'classifies subscriptions with known tenant-bound resources as high risk' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $rawRoot = Join-Path $tempRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
            }
            ArtifactFiles = [pscustomobject]@{
                Raw = $rawRoot
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
        }

        $candidate = [pscustomobject]@{
            SubscriptionId = 'sub-risk-high'
            SubscriptionName = 'AKS Subscription'
        }

        $result = Get-SubscriptionResourceRisk -RunContext $runContext -Candidate $candidate -Resources @(
            [pscustomobject]@{ Type = 'Microsoft.ContainerService/managedClusters' },
            [pscustomobject]@{ Type = 'Microsoft.Storage/storageAccounts' }
        )

        $result.RiskLevel | Should Be 'High'
        $result.RiskyTypes.Count | Should Be 1
        $result.RiskyTypes[0] | Should Be 'Microsoft.ContainerService/managedClusters'

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }

    It 'classifies configured blocking resource types as blocked' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $rawRoot = Join-Path $tempRoot 'raw'
        New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
            }
            ArtifactFiles = [pscustomobject]@{
                Raw = $rawRoot
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
        }

        $candidate = [pscustomobject]@{
            SubscriptionId = 'sub-risk-blocked'
            SubscriptionName = 'Blocked Subscription'
        }

        $result = Get-SubscriptionResourceRisk -RunContext $runContext -Candidate $candidate -Resources @(
            [pscustomobject]@{ Type = 'Contoso.Blocked/resourceType' }
        ) -BlockedResourceTypes @('Contoso.Blocked/resourceType')

        $result.RiskLevel | Should Be 'Blocked'
        $result.BlockingTypes.Count | Should Be 1

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Describe 'Send-OwnerNotification' {
    It 'returns unsent notification rows in WhatIf or None modes' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $templatePath = Join-Path $tempRoot 'owner-notification.md'
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Set-Content -LiteralPath $templatePath -Value "Subject: Test`n`nSubscription: {{SubscriptionName}}" -Encoding utf8

        $runContext = [pscustomobject]@{
            RepositoryRoot = $tempRoot
            ArtifactFiles = [pscustomobject]@{
                Events = (Join-Path $tempRoot 'events.jsonl')
                Errors = (Join-Path $tempRoot 'errors.jsonl')
            }
            Configuration = [pscustomobject]@{
                NotificationMode = 'None'
                CurrentTenantId = '11111111-1111-1111-1111-111111111111'
                TargetTenantId = '22222222-2222-2222-2222-222222222222'
                ChangeTicketId = 'CHG123456'
                NotificationDeadline = '2026-05-01'
            }
        }

        $owner = [pscustomobject]@{
            SubscriptionId = 'sub-1'
            SubscriptionName = 'Visual Studio Alpha'
            Mail = 'owner@contoso.com'
            UserPrincipalName = 'owner@contoso.com'
        }

        $result = Send-OwnerNotification -RunContext $runContext -OwnerRecord $owner -TemplatePath $templatePath -SkipDelivery

        $result.Sent | Should Be $false
        $result.Recipient | Should Be 'owner@contoso.com'
        (Test-Path -LiteralPath (Join-Path $tempRoot 'events.jsonl')) | Should Be $true

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Describe 'Get-NotificationTargets' {
    It 'deduplicates notify targets by subscription and recipient' {
        $owners = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                Action = 'NotifyAndPreserve'
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
            },
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                Action = 'NotifyAndPreserve'
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
            },
            [pscustomobject]@{
                SubscriptionId = 'sub-2'
                Action = 'NotifyAndPreserve'
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
            },
            [pscustomobject]@{
                SubscriptionId = 'sub-3'
                Action = 'ReviewDisabledUser'
                Mail = 'disabled@contoso.com'
                UserPrincipalName = 'disabled@contoso.com'
            }
        )

        $targets = Get-NotificationTargets -Owners $owners

        $targets.Count | Should Be 2
    }
}

Describe 'Get-TransferSupportSignal' {
    It 'returns true when pilot proof contains supported marker' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $docsRoot = Join-Path $tempRoot 'docs'
        New-Item -ItemType Directory -Path $docsRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $docsRoot 'pilot-transfer-proof.md') -Value @(
            '# Pilot Transfer Proof',
            'SUPPORTED_TRANSFER_PATH_VALIDATED: true'
        ) -Encoding utf8

        $runContext = [pscustomobject]@{ RepositoryRoot = $tempRoot }

        $result = Get-TransferSupportSignal -RunContext $runContext
        $result | Should Be $true

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Describe 'Set-TargetGuestUser' {
    It 'maps owners to existing target users when available' {
        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                InviteOwnersToTargetTenant = $true
                WhatIf = $true
            }
        }

        $owner = [pscustomobject]@{
            SubscriptionId = 'sub-1'
            SourcePrincipalId = 'src-user-1'
            SourcePrincipalType = 'User'
            Mail = 'owner@contoso.com'
            UserPrincipalName = 'owner@contoso.com'
        }

        $result = Set-TargetGuestUser -RunContext $runContext -OwnerRecord $owner -ExistingUsersByKey @{
            'owner@contoso.com' = [pscustomobject]@{ Id = 'target-user-1' }
        }

        $result.Action | Should Be 'MatchedExistingTargetUser'
        $result.TargetPrincipalId | Should Be 'target-user-1'
    }

    It 'returns would-invite behavior in WhatIf preflight when no match is found' {
        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                InviteOwnersToTargetTenant = $true
                WhatIf = $true
            }
        }

        $owner = [pscustomobject]@{
            SubscriptionId = 'sub-2'
            SourcePrincipalId = 'src-user-2'
            SourcePrincipalType = 'User'
            Mail = 'another@contoso.com'
            UserPrincipalName = 'another@contoso.com'
        }

        $result = Set-TargetGuestUser -RunContext $runContext -OwnerRecord $owner

        $result.Action | Should Be 'WouldInviteGuest'
        $result.CanCreateGuest | Should Be $true
    }
}

Describe 'Test-TransferPrerequisites' {
    It 'marks candidates with resolvable owners as ready for manual transfer validation' {
        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                InviteOwnersToTargetTenant = $true
                WhatIf = $true
            }
        }

        $candidates = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                RiskLevel = 'Low'
                Status = 'ReadyForNotification'
            },
            [pscustomobject]@{
                SubscriptionId = 'sub-2'
                RiskLevel = 'High'
                Status = 'NoOwner'
            }
        )

        $owners = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                SourcePrincipalId = 'src-user-1'
                SourcePrincipalType = 'User'
                AccountEnabled = $true
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
            }
        )

        $result = Test-TransferPrerequisites -RunContext $runContext -Candidates $candidates -Owners $owners

        ($result.Results | Where-Object SubscriptionId -eq 'sub-1').Decision | Should Be 'ReadyForManualTransferValidation'
        ($result.Results | Where-Object SubscriptionId -eq 'sub-2').Decision | Should Be 'NoAction'
    }

    It 'blocks preflight decisions when source RBAC cannot be read' {
        $runContext = [pscustomobject]@{
            Configuration = [pscustomobject]@{
                InviteOwnersToTargetTenant = $true
                WhatIf = $true
            }
        }

        $candidates = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                RiskLevel = 'Low'
                Status = 'ReadyForNotification'
            }
        )

        $owners = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                SourcePrincipalId = 'src-user-1'
                SourcePrincipalType = 'User'
                AccountEnabled = $true
                Mail = 'owner@contoso.com'
                UserPrincipalName = 'owner@contoso.com'
            }
        )

        $result = Test-TransferPrerequisites -RunContext $runContext -Candidates $candidates -Owners $owners -CanReadRbac:$false -CanAccessTargetTenant:$true

        ($result.Results | Where-Object SubscriptionId -eq 'sub-1').Decision | Should Be 'BlockedPreflight'
    }
}

Describe 'Get-MigrationExecutionPlan' {
    It 'marks unsupported transfer path as blocked no-action' {
        $candidates = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                SubscriptionName = 'Visual Studio Alpha'
                Status = 'ReadyForMigration'
            }
        )

        $plan = Get-MigrationExecutionPlan -Candidates $candidates -TransferSupported:$false -WhatIfMode:$false

        $plan.Count | Should Be 1
        $plan[0].ExecutionAction | Should Be 'NoAction'
        $plan[0].PlannedTransferStatus | Should Be 'BlockedNoSupportedPath'
    }

    It 'resumes by skipping subscriptions that are already completed' {
        $candidates = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                SubscriptionName = 'Visual Studio Alpha'
                Status = 'ReadyForMigration'
            }
        )

        $existing = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-1'
                TransferStatus = 'Succeeded'
                OwnerRestoreStatus = 'Succeeded'
                ValidationStatus = 'Validated'
                Error = $null
            }
        )

        $plan = Get-MigrationExecutionPlan -Candidates $candidates -ExistingMigrationResults $existing -TransferSupported:$true -WhatIfMode:$false

        $plan.Count | Should Be 1
        $plan[0].ExecutionAction | Should Be 'ResumeSkipCompleted'
        $plan[0].PlannedTransferStatus | Should Be 'Succeeded'
    }

    It 'plans execution when transfer path is supported and candidate is eligible' {
        $candidates = @(
            [pscustomobject]@{
                SubscriptionId = 'sub-2'
                SubscriptionName = 'Visual Studio Beta'
                Status = 'ReadyForMigration'
            }
        )

        $plan = Get-MigrationExecutionPlan -Candidates $candidates -TransferSupported:$true -WhatIfMode:$false

        $plan.Count | Should Be 1
        $plan[0].ExecutionAction | Should Be 'Execute'
        $plan[0].PlannedTransferStatus | Should Be 'PendingExecution'
    }
}

Describe 'Export-FinalReport' {
    It 'writes final-report.json summary from run artifacts' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $artifactFiles = [pscustomobject]@{
            Candidates = (Join-Path $tempRoot 'candidates.csv')
            Owners = (Join-Path $tempRoot 'owners.csv')
            Notifications = (Join-Path $tempRoot 'owner-notifications.csv')
            Preflight = (Join-Path $tempRoot 'preflight-results.csv')
            Migration = (Join-Path $tempRoot 'migration-results.csv')
            PostValidation = (Join-Path $tempRoot 'post-validation.csv')
            Events = (Join-Path $tempRoot 'events.jsonl')
            Errors = (Join-Path $tempRoot 'errors.jsonl')
        }

        'SubscriptionId,SubscriptionName,State,MatchRegex,Status,RiskLevel' | Set-Content -LiteralPath $artifactFiles.Candidates -Encoding utf8
        'sub-1,Visual Studio Alpha,Enabled,Visual Studio,ReadyForMigration,Low' | Add-Content -LiteralPath $artifactFiles.Candidates -Encoding utf8

        'SubscriptionId,StartedAt,CompletedAt,TransferStatus,OwnerRestoreStatus,ValidationStatus,Error' | Set-Content -LiteralPath $artifactFiles.Migration -Encoding utf8
        'sub-1,2026-04-25T10:00:00Z,2026-04-25T10:10:00Z,Succeeded,Succeeded,Validated,' | Add-Content -LiteralPath $artifactFiles.Migration -Encoding utf8

        'SubscriptionId,SubscriptionName,ExpectedTenantId,ActualTenantId,MigrationAdminOwner,PreservedOwnerCount,MissingOwnerCount,Status,Notes' | Set-Content -LiteralPath $artifactFiles.PostValidation -Encoding utf8

        $runContext = [pscustomobject]@{
            RunRoot = $tempRoot
            ArtifactFiles = $artifactFiles
        }

        $summary = Export-FinalReport -RunContext $runContext

        $summary.CandidateCount | Should Be 1
        $summary.TransferSucceededCount | Should Be 1
        (Test-Path -LiteralPath (Join-Path $tempRoot 'final-report.json')) | Should Be $true

        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
