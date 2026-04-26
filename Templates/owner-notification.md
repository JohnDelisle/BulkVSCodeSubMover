Subject: Action notice: Azure subscription will move to holding tenant

You are listed as an Owner on the following Azure subscription:

Subscription: {{SubscriptionName}}
Subscription ID: {{SubscriptionId}}

This subscription was created in the corporate tenant and matches our Visual Studio or personal subscription cleanup policy.

Planned action:
- The subscription will be moved from tenant {{SourceTenantId}} to tenant {{TargetTenantId}}.
- Existing Azure RBAC assignments will not be preserved by Microsoft during tenant transfer.
- The cleanup automation will attempt to grant your current identity Owner access in the target tenant.
- Resource-level access, managed identities, Key Vault policies, service principals, and other tenant-bound dependencies may require your remediation after the move.

No production workloads should be running in these subscriptions. If this is incorrect, respond before {{NotificationDeadline}} and reference {{ChangeTicketId}}.
