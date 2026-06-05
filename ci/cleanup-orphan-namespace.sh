#!/usr/bin/env bash
#
# cleanup-orphan-namespace.sh
# ----------------------------------------------------------------------------
# Force-delete every resource the S3 Backend Module creates for ONE namespace.
#
# Why this exists: the Phase 2 e2e test (test/) always tears itself down, but if
# a run dies mid-apply because the CI role is missing an action (a Phase 0-style
# least-privilege iteration), the deferred `terraform destroy` can hit the same
# 403 and clean up nothing — leaving an orphaned namespace behind. A fresh test
# run gets a NEW random namespace, so it never reclaims the old one. This script
# is the manual sweep for that orphan.
#
# Scope: deletes ONLY resources whose names/tag carry the given namespace. It is
# intended for the disposable CI account, run by the maintainer with the SSO
# admin session — never by CI.
#
# Resources (per module main.tf / iam.tf):
#   - S3 bucket            <ns>-state-bucket      (versioned + KMS-encrypted)
#   - DynamoDB table       <ns>-state-lock
#   - KMS key              (found by ResourceGroup tag; scheduled for deletion)
#   - IAM role             <ns>-tf-assume-role
#   - IAM policy           <ns>-tf-policy
#   - Resource group       <ns>-terraform-group
#
# Usage:
#   aws sso login --profile s3backend-poc
#   export AWS_PROFILE=s3backend-poc AWS_REGION=ap-southeast-2
#   ./ci/cleanup-orphan-namespace.sh <namespace>      # prompts before deleting
#   FORCE=1 ./ci/cleanup-orphan-namespace.sh <namespace>   # skip the prompt
#
# A namespace looks like: e2e-p85t7z7tz381uidqqc2l
# ----------------------------------------------------------------------------
set -euo pipefail

NS="${1:-}"
[ -n "$NS" ] || { echo "usage: $0 <namespace> (e.g. e2e-p85t7z7tz381uidqqc2l)" >&2; exit 2; }
[ -n "${AWS_REGION:-}" ] || { echo "ERROR: export AWS_REGION (e.g. ap-southeast-2)" >&2; exit 2; }

for bin in aws jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: $bin not on PATH" >&2; exit 2; }
done

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
CALLER="$(aws sts get-caller-identity --query Arn --output text)"

BUCKET="${NS}-state-bucket"
TABLE="${NS}-state-lock"
ROLE="${NS}-tf-assume-role"
POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/${NS}-tf-policy"
GROUP="${NS}-terraform-group"

echo "About to DELETE all S3 Backend Module resources for namespace:"
echo "    namespace : $NS"
echo "    account   : $ACCOUNT   region: $AWS_REGION"
echo "    caller    : $CALLER"
echo "    targets   : s3://$BUCKET, ddb:$TABLE, iam-role:$ROLE, iam-policy:${NS}-tf-policy,"
echo "                rg:$GROUP, + any KMS key tagged ResourceGroup=$NS"
if [ "${FORCE:-0}" != "1" ]; then
  printf 'Type the namespace to confirm: '
  read -r confirm
  [ "$confirm" = "$NS" ] || { echo "aborted (no match)"; exit 1; }
fi

log() { printf '\n=== %s ===\n' "$*"; }

# --- S3 bucket: empty all versions + delete markers, then delete -------------
log "S3 bucket $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  # Versioned bucket: `aws s3 rb --force` does not remove old versions, so we
  # loop list-object-versions -> delete-objects until nothing remains.
  while :; do
    payload="$(aws s3api list-object-versions --bucket "$BUCKET" --max-items 500 \
      --query '{Objects: [Versions, DeleteMarkers][][].{Key:Key,VersionId:VersionId}}' \
      --output json)"
    count="$(echo "$payload" | jq '.Objects | length')"
    [ "$count" -eq 0 ] && break
    echo "deleting $count object version(s)/marker(s)..."
    aws s3api delete-objects --bucket "$BUCKET" --delete "$payload" >/dev/null
  done
  aws s3api delete-bucket --bucket "$BUCKET" && echo "deleted bucket $BUCKET"
else
  echo "bucket not found (already gone)"
fi

# --- DynamoDB lock table -----------------------------------------------------
log "DynamoDB table $TABLE"
if aws dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "$TABLE" >/dev/null && echo "deleting table $TABLE"
else
  echo "table not found (already gone)"
fi

# --- IAM role (detach managed policies first) + policy -----------------------
log "IAM role $ROLE"
if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  for parn in $(aws iam list-attached-role-policies --role-name "$ROLE" \
                  --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$parn" && echo "detached $parn"
  done
  for pname in $(aws iam list-role-policies --role-name "$ROLE" \
                   --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$ROLE" --policy-name "$pname"
  done
  aws iam delete-role --role-name "$ROLE" && echo "deleted role $ROLE"
else
  echo "role not found (already gone)"
fi

log "IAM policy ${NS}-tf-policy"
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  for v in $(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
               --query 'Versions[?!IsDefaultVersion].VersionId' --output text); do
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$v"
  done
  aws iam delete-policy --policy-arn "$POLICY_ARN" && echo "deleted policy $POLICY_ARN"
else
  echo "policy not found (already gone)"
fi

# --- KMS key (schedule for deletion; cannot be deleted immediately) ----------
log "KMS key(s) tagged ResourceGroup=$NS"
kms_arns="$(aws resourcegroupstaggingapi get-resources \
              --tag-filters "Key=ResourceGroup,Values=$NS" \
              --resource-type-filters kms \
              --query 'ResourceTagMappingList[].ResourceARN' --output text || true)"
if [ -n "$kms_arns" ]; then
  for arn in $kms_arns; do
    state="$(aws kms describe-key --key-id "$arn" --query 'KeyMetadata.KeyState' --output text 2>/dev/null || echo UNKNOWN)"
    if [ "$state" = "PendingDeletion" ]; then
      echo "already scheduled for deletion: $arn"
    else
      aws kms schedule-key-deletion --key-id "$arn" --pending-window-in-days 7 \
        --query 'DeletionDate' --output text && echo "scheduled for deletion: $arn"
    fi
  done
else
  echo "no KMS key found for this namespace"
fi

# --- Resource group ----------------------------------------------------------
log "Resource group $GROUP"
if aws resource-groups get-group --group "$GROUP" >/dev/null 2>&1; then
  aws resource-groups delete-group --group "$GROUP" >/dev/null && echo "deleted group $GROUP"
else
  echo "group not found (already gone)"
fi

# --- Verify: only KMS-in-PendingDeletion may remain --------------------------
log "VERIFY (tag ResourceGroup=$NS)"
remaining=""
for arn in $(aws resourcegroupstaggingapi get-resources \
               --tag-filters "Key=ResourceGroup,Values=$NS" \
               --query 'ResourceTagMappingList[].ResourceARN' --output text || true); do
  if [[ "$arn" == *":kms:"*":key/"* ]]; then
    state="$(aws kms describe-key --key-id "$arn" --query 'KeyMetadata.KeyState' --output text 2>/dev/null || echo UNKNOWN)"
    [ "$state" = "PendingDeletion" ] && { echo "ok (KMS pending deletion): $arn"; continue; }
  fi
  remaining="$remaining $arn"
done
remaining="$(echo "$remaining" | xargs)"
if [ -n "$remaining" ]; then
  echo "STILL PRESENT — may need a second pass (eventual consistency) or manual delete:" >&2
  printf '%s\n' $remaining >&2
  exit 1
fi
echo "clean — namespace $NS swept (KMS key, if any, is pending deletion)."