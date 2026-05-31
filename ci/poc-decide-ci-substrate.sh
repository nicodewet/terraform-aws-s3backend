#!/usr/bin/env bash
#
# poc-decide-ci-substrate.sh
# ----------------------------------------------------------------------------
# Phase-0 proof-of-concept for the spec:
#   specs/2026-05-23-phase-0-decide-ci-substrate/
#
# This is a single-purpose, throwaway harness that answers ONE question:
# "Can a disposable AWS account run the module's full backend lifecycle —
#  create -> consume (write real Terraform state) -> destroy -> prove no leak —
#  using only short-lived local SSO credentials?"
# It is NOT the long-term test rig; do not build on it.
#
# Prereqs:
#   - terraform (>= 0.14, for -chdir), aws-cli v2, and jq on PATH.
#   - Local SSO auth wired per ../specs/2026-05-23-phase-0-decide-ci-substrate/
#     auth-setup.md, then, in this shell:
#         aws sso login --profile s3backend-poc
#         export AWS_PROFILE=s3backend-poc
#         export AWS_REGION=ap-southeast-2
#
# Run:    ./ci/poc-decide-ci-substrate.sh
# Time:   ~3-5 min (KMS + S3 + DynamoDB + IAM create, then destroy).
# Result: exit 0 = full lifecycle worked and the account is clean afterwards.
#         Any non-zero exit = a step failed OR a leak was detected; the trap
#         still attempts a full teardown before exiting.
# ----------------------------------------------------------------------------
set -euo pipefail

# --- paths resolved relative to this script, not the caller's cwd -----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/poc-fixture/deploy"
TEST_DIR="$SCRIPT_DIR/poc-fixture/test"

# --- state shared with the cleanup trap -------------------------------------
NAMESPACE=""      # ResourceGroup tag value; derived from the bucket name
DEPLOYED=0        # 1 once STEP A applied (deploy teardown needed)
TEST_INITED=0     # 1 once STEP B init'd  (test teardown needed)

log()  { printf '\n=== %s ===\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

leak_check() {
  [ -z "$NAMESPACE" ] && { echo "leak check skipped (nothing was deployed)"; return 0; }
  log "LEAK CHECK (tag ResourceGroup=$NAMESPACE)"
  local all real arn state
  all="$(aws resourcegroupstaggingapi get-resources \
           --tag-filters "Key=ResourceGroup,Values=$NAMESPACE" \
           --query 'ResourceTagMappingList[].ResourceARN' --output text || true)"
  real=""
  for arn in $all; do
    # `terraform destroy` SCHEDULES a KMS key for deletion rather than deleting
    # it; the key sits in PendingDeletion (tags intact) for its deletion window.
    # That is expected AWS behaviour in a disposable account, not a leak.
    if [[ "$arn" == *":kms:"*":key/"* ]]; then
      state="$(aws kms describe-key --key-id "$arn" \
                 --query 'KeyMetadata.KeyState' --output text 2>/dev/null || echo UNKNOWN)"
      if [ "$state" = "PendingDeletion" ]; then
        echo "ignoring KMS key scheduled for deletion: $arn"
        continue
      fi
    fi
    real="$real $arn"
  done
  real="$(echo "$real" | xargs)"
  if [ -n "$real" ]; then
    echo "LEAKED — these resources still carry the tag and need manual cleanup:" >&2
    printf '%s\n' $real >&2
    return 1
  fi
  echo "clean — no unexpected resource carries tag ResourceGroup=$NAMESPACE."
  return 0
}

cleanup() {
  local rc=$?
  set +e   # best-effort teardown: keep going even if a step fails
  log "CLEANUP (triggering exit code: $rc)"
  if [ "$TEST_INITED" -eq 1 ]; then
    terraform -chdir="$TEST_DIR" destroy -auto-approve -input=false \
      || echo "WARN: test destroy failed; deploy destroy (force_destroy) should still clean up"
  fi
  if [ "$DEPLOYED" -eq 1 ]; then
    terraform -chdir="$DEPLOY_DIR" destroy -auto-approve -input=false \
      || echo "WARN: deploy destroy failed; see leak check below"
  fi
  leak_check || rc=1
  # Clear the deploy's local state so a rerun starts from zero, but KEEP the
  # .terraform provider cache: re-downloading providers each run is slow and a
  # freshly installed plugin can trip Terraform's plugin-start timeout.
  rm -rf "$DEPLOY_DIR"/terraform.tfstate* 2>/dev/null
  log "DONE (exit $rc)"
  exit "$rc"
}
trap cleanup EXIT

# --- preflight --------------------------------------------------------------
log "PREFLIGHT"
for bin in terraform aws jq; do
  command -v "$bin" >/dev/null 2>&1 || fail "$bin is not on PATH"
done
[ -n "${AWS_REGION:-}" ] || fail "AWS_REGION is not set (export AWS_REGION=ap-southeast-2)"
# Terraform's AWS SDK can fail to refresh an SSO token even when the aws CLI is
# perfectly happy (InvalidGrantException). If we're on an SSO/profile session,
# materialise short-lived env credentials from it so terraform and the CLI share
# identical, SDK-friendly creds. Falls through harmlessly if export is unsupported.
if [ -n "${AWS_PROFILE:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  if creds="$(aws configure export-credentials --profile "$AWS_PROFILE" --format env 2>/dev/null)"; then
    eval "$creds"
    unset AWS_PROFILE
    echo "materialised short-lived env credentials from the SSO profile"
  fi
fi
aws sts get-caller-identity >/dev/null 2>&1 \
  || fail "aws sts get-caller-identity failed — run: aws sso login --profile s3backend-poc"
echo "caller: $(aws sts get-caller-identity --query Arn --output text)"

# --- STEP A: deploy the backend (this repo's module) ------------------------
log "STEP A — deploy backend (module source = ../../../)"
terraform -chdir="$DEPLOY_DIR" init -input=false
terraform -chdir="$DEPLOY_DIR" apply -auto-approve -input=false
DEPLOYED=1

CONFIG="$(terraform -chdir="$DEPLOY_DIR" output -json s3backend_config)"
BUCKET="$(echo "$CONFIG" | jq -r '.bucket')"
DDB_TABLE="$(echo "$CONFIG" | jq -r '.dynamodb_table')"
REGION="$(echo "$CONFIG" | jq -r '.region')"
ROLE_ARN="$(echo "$CONFIG" | jq -r '.role_arn')"
NAMESPACE="${BUCKET%-state-bucket}"   # tag value == bucket name minus suffix
echo "bucket=$BUCKET"
echo "table=$DDB_TABLE  region=$REGION"
echo "role=$ROLE_ARN"
echo "namespace(tag)=$NAMESPACE"

# --- STEP B: consume the backend (assume role, write real state) ------------
log "STEP B — init + apply the test config against the new backend"
# Terraform >= 1.6 dropped the top-level `role_arn` backend arg in favour of an
# `assume_role` block; supply it as an object via -backend-config.
#
# IAM is eventually consistent: the role + policy created in STEP A can take a
# few seconds to become assumable with full S3/KMS permissions. Until they do,
# the backend's state HeadObject returns 403. Retry init with linear backoff.
attempt=1
max_attempts=6
while true; do
  if terraform -chdir="$TEST_DIR" init -input=false -reconfigure \
       -backend-config="bucket=$BUCKET" \
       -backend-config="region=$REGION" \
       -backend-config="dynamodb_table=$DDB_TABLE" \
       -backend-config="assume_role={role_arn=\"$ROLE_ARN\"}"; then
    TEST_INITED=1
    break
  fi
  [ "$attempt" -ge "$max_attempts" ] \
    && fail "backend init still failing after $max_attempts attempts (IAM propagation?)"
  echo "init attempt $attempt failed — IAM likely still propagating; retrying in $((attempt * 5))s"
  sleep "$((attempt * 5))"
  attempt=$((attempt + 1))
done
terraform -chdir="$TEST_DIR" apply -auto-approve -input=false

# --- assertions -------------------------------------------------------------
log "ASSERTIONS"
aws s3api head-bucket --bucket "$BUCKET" \
  && echo "OK 1/3 — state bucket exists: $BUCKET"
aws dynamodb describe-table --table-name "$DDB_TABLE" >/dev/null \
  && echo "OK 2/3 — lock table exists: $DDB_TABLE"
aws s3 ls "s3://$BUCKET/team1/my-cool-project" | grep -q . \
  && echo "OK 3/3 — state object written under team1/my-cool-project"

log "ALL ASSERTIONS PASSED — teardown + leak check run next via the EXIT trap"