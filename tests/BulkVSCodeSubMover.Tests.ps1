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
