# Pilot Transfer Proof

The actual tenant transfer step must remain gated until this document is completed with real evidence from your environment.

Transfer support marker for automation:

```text
SUPPORTED_TRANSFER_PATH_VALIDATED: false
```

Set this value to `true` only after all required proof points below are complete and validated.

## Required proof points

1. Identify the Microsoft-supported API or CLI command used for directory transfer.
2. Record the billing model and any prerequisites for the test subscription.
3. Record the exact source-tenant and target-tenant operator flow.
4. Capture evidence that the transfer request succeeds.
5. Capture evidence that the subscription appears in the target tenant.
6. Capture evidence that source-directory RBAC is removed.
7. Capture evidence that target-directory Owner can be restored by script.
8. Record failure modes, retry behavior, and stop conditions.

## Hard rule

If this document cannot be completed with a supported mechanism, the automation must stop at communication, preparation, batching, and post-transfer restoration tooling. Unsupported portal scraping is out of scope.
