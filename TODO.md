# TODO

## Now
 
- This module creates a terraform backend module on AWS. Using AWS Organizations I created an account that will only used for CI to exercise creating the terraform backend module using the scripts supplied. The goal is to use this disposable account to make sure the Terraform backend module works.
- The first issue to tackle is to get secure integration going between GitHub Actions in associated with repository and the relevant account.
- It is important to note that all provisioned resources in the account should be deleted after we have proven the module works via appropriate CI steps. The account should be treated as disposable, it exists purely for CI purposes.
- We should consider whether a better approach is possible, should we use localstack or continue to use AWS?

## Next

- Once we have the secure integration between GitHub Actions and this account going, we need to create the backend module and test it, then delete all resources in the account, this is standard GIVEN, WHEN, THEN test phases but with actual infrastructure.
- The README.md in this project should include a badge that shows the module works in some manner. This is 
to give the general public confidence in this Terraform component.

