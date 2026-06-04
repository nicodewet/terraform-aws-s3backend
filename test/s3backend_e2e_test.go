// Phase-2 end-to-end test — spec: specs/2026-06-03-phase-2-e2e-test/.
//
// GIVEN a clean disposable AWS account,
// WHEN the deploy fixture applies THIS repo's module, then the consumer fixture
// applies against the resulting S3 backend via the module's assume-role,
// THEN the Terraform state object exists at team1/my-cool-project in the bucket
// (THEN-1) and the DynamoDB state table holds the digest item for that state
// (THEN-2),
// and the test ALWAYS destroys both fixtures (consumer before deploy) and then
// leak-checks that zero module-tagged resources survive.
//
// Credentials are read from the ambient environment — the OIDC session in CI,
// the Phase 0 SSO session locally (see HOW_TO_RUN.md). The test never embeds
// long-lived keys.
package test

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	ddbtypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	"github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi"
	rgtypes "github.com/aws/aws-sdk-go-v2/service/resourcegroupstaggingapi/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

const (
	// Region of the Phase 0 disposable-account substrate. The fixtures pin the
	// same region in their provider/backend so SDK assertions hit the right one.
	awsRegion = "ap-southeast-2"

	// The backend `key` the consumer fixture writes its state under. THEN-1
	// asserts the object exists here; THEN-2 derives the digest LockID from it.
	stateKey = "team1/my-cool-project"
)

func TestS3BackendEndToEnd(t *testing.T) {
	ctx := context.Background()

	// Ambient credentials: OIDC session (CI) or SSO session (local). No keys.
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(awsRegion))
	require.NoError(t, err, "loading ambient AWS credentials")

	// ----------------------------------------------------------------------
	// WHEN-1 — deploy this repo's module (the S3 backend).
	// ----------------------------------------------------------------------
	deployOpts := &terraform.Options{
		TerraformDir: "fixtures/deploy",
		NoColor:      true,
	}
	// Register destroy immediately after apply so teardown runs even if a later
	// assertion fails. Deferred LIFO => consumer destroy (below) runs first.
	defer terraform.Destroy(t, deployOpts)
	terraform.InitAndApply(t, deployOpts)

	cfg := terraform.OutputMap(t, deployOpts, "s3backend_config")
	bucket := cfg["bucket"]
	table := cfg["dynamodb_table"]
	region := cfg["region"]
	roleArn := cfg["role_arn"]
	require.NotEmpty(t, bucket, "deploy output: bucket")
	require.NotEmpty(t, table, "deploy output: dynamodb_table")
	require.NotEmpty(t, region, "deploy output: region")
	require.NotEmpty(t, roleArn, "deploy output: role_arn")

	// Tag value the module stamps on every resource == bucket name minus the
	// "-state-bucket" suffix (module local.namespace). Drives the leak check.
	namespace := strings.TrimSuffix(bucket, "-state-bucket")

	// The leak check must run AFTER both fixtures are destroyed. Deferred funcs
	// run as the test unwinds; t.Cleanup funcs run afterwards — so registering
	// the leak check here guarantees it runs last, once the disposable account
	// should be empty.
	t.Cleanup(func() { assertNoLeaks(t, ctx, awsCfg, namespace) })

	// ----------------------------------------------------------------------
	// WHEN-2 — consume the backend via the module's assume-role.
	// ----------------------------------------------------------------------
	consumerOpts := &terraform.Options{
		TerraformDir: "fixtures/consumer",
		// Partial backend config supplied at init. assume_role is an object
		// literal (Terraform >= 1.6 dropped the top-level role_arn arg).
		BackendConfig: map[string]interface{}{
			"bucket":         bucket,
			"region":         region,
			"dynamodb_table": table,
			"assume_role":    fmt.Sprintf("{role_arn=%q}", roleArn),
		},
		// -reconfigure so retries re-init cleanly against the partial backend.
		Reconfigure: true,
		NoColor:     true,
	}
	defer terraform.Destroy(t, consumerOpts)

	// IAM is eventually consistent: the role + policy created in WHEN-1 can take
	// a few seconds to become assumable with full S3/KMS rights. Until then the
	// backend's state HeadObject returns 403 (Phase 0 saw this <1s after create).
	// Retry the whole init+apply with linear-ish backoff.
	retry.DoWithRetry(t, "consumer init+apply (absorb IAM eventual consistency)", 6, 10*time.Second,
		func() (string, error) {
			return terraform.InitAndApplyE(t, consumerOpts)
		})

	// ----------------------------------------------------------------------
	// THEN-1 — the state object exists in the bucket.
	// ----------------------------------------------------------------------
	s3c := s3.NewFromConfig(awsCfg)
	_, err = s3c.HeadObject(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(stateKey),
	})
	require.NoErrorf(t, err, "THEN-1: state object %q should exist in bucket %q", stateKey, bucket)

	// ----------------------------------------------------------------------
	// THEN-2 — the DynamoDB state table holds the persistent digest item.
	// The active lock is transient; the digest (LockID = <bucket>/<key>-md5) is
	// the stable record the S3 backend keeps for the written state.
	// ----------------------------------------------------------------------
	ddbc := dynamodb.NewFromConfig(awsCfg)
	lockID := fmt.Sprintf("%s/%s-md5", bucket, stateKey)
	item, err := ddbc.GetItem(ctx, &dynamodb.GetItemInput{
		TableName:      aws.String(table),
		ConsistentRead: aws.Bool(true),
		Key: map[string]ddbtypes.AttributeValue{
			"LockID": &ddbtypes.AttributeValueMemberS{Value: lockID},
		},
	})
	require.NoErrorf(t, err, "THEN-2: reading digest item %q from table %q", lockID, table)
	require.NotEmptyf(t, item.Item, "THEN-2: digest item LockID=%q should exist in table %q", lockID, table)
}

// assertNoLeaks fails the test if any resource still carries the module's
// ResourceGroup tag after teardown, excluding KMS keys in PendingDeletion —
// `terraform destroy` schedules KMS keys for deletion rather than deleting them,
// so they sit tagged for their deletion window. That is expected AWS behaviour
// in a disposable account, not a leak (Phase 0 lesson).
func assertNoLeaks(t *testing.T, ctx context.Context, awsCfg aws.Config, namespace string) {
	if namespace == "" {
		t.Log("leak check skipped (nothing was deployed)")
		return
	}
	t.Logf("leak check — resources tagged ResourceGroup=%s", namespace)

	rgc := resourcegroupstaggingapi.NewFromConfig(awsCfg)
	kmsc := kms.NewFromConfig(awsCfg)

	var leaked []string
	paginator := resourcegroupstaggingapi.NewGetResourcesPaginator(rgc, &resourcegroupstaggingapi.GetResourcesInput{
		TagFilters: []rgtypes.TagFilter{{
			Key:    aws.String("ResourceGroup"),
			Values: []string{namespace},
		}},
	})
	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx)
		require.NoError(t, err, "leak check: listing tagged resources")
		for _, m := range page.ResourceTagMappingList {
			arn := aws.ToString(m.ResourceARN)
			if strings.Contains(arn, ":kms:") && strings.Contains(arn, ":key/") {
				if isPendingDeletion(ctx, kmsc, arn) {
					t.Logf("ignoring KMS key scheduled for deletion: %s", arn)
					continue
				}
			}
			leaked = append(leaked, arn)
		}
	}
	require.Emptyf(t, leaked, "leak check: resources still tagged ResourceGroup=%s: %v", namespace, leaked)
	if len(leaked) == 0 {
		t.Logf("clean — no unexpected resource carries tag ResourceGroup=%s", namespace)
	}
}

// isPendingDeletion reports whether the KMS key is scheduled for deletion. A
// failed describe is treated as "not pending" so a genuinely orphaned key is
// surfaced as a leak rather than silently ignored.
func isPendingDeletion(ctx context.Context, kmsc *kms.Client, keyArn string) bool {
	return kmsKeyState(ctx, kmsc, keyArn) == "PendingDeletion"
}

func kmsKeyState(ctx context.Context, kmsc *kms.Client, keyArn string) string {
	out, err := kmsc.DescribeKey(ctx, &kms.DescribeKeyInput{KeyId: aws.String(keyArn)})
	if err != nil {
		return "UNKNOWN"
	}
	return string(out.KeyMetadata.KeyState)
}
