// https://registry.terraform.io/providers/hashicorp/aws/latest/docs
provider "aws" {
  region = "ap-southeast-2"
  // https://registry.terraform.io/providers/hashicorp/aws/latest/docs#shared-configuration-and-credentials-files
  // https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-files.html
  profile = "default"
}

data "aws_region" "current" {}

// https://developer.hashicorp.com/terraform/language/resources/syntax#resource-syntax
// The "random_string" resource type is named "rand"
resource "random_string" "rand" {
  length  = 24
  special = false
  upper   = false
}

locals {
  namespace = substr( join("-", [var.namespace, random_string.rand.result, "terraform-3backend"]), 0, 24 )
  resource_stack_type_tag_key = "iac-stack-type" 
  resource_stack_type_tag_value = "team-terraform-3backend"
}

/************************************************************
* Put resources into a group based on tag
*
* https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group
*************************************************************/
resource "aws_resourcegroups_group" "resourcegroups_group" {
  name = "${local.namespace}-terraform-group"

  resource_query {
    query = <<-JSON
{
  "ResourceTypeFilters": [
    "AWS::AllSupported"
  ],
  "TagFilters": [
    {
      "Key": "ResourceGroup",
      "Values": ["${local.namespace}"]
    }
  ]
}
  JSON
  }
}

resource "aws_kms_key" "kms_key" {
  tags = {
    ResourceGroup = local.namespace
    local.resource_stack_type_tag_key = local.resource_stack_type_tag_value
  }
}

/****************************************************************************************************************************
* State is stored in the S3 Bucket
* 
* https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
* https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning
* https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration
*****************************************************************************************************************************/

resource "aws_s3_bucket" "s3_bucket" {
  bucket        = "${local.namespace}-state-bucket"
  force_destroy = var.force_destroy_state

  tags = {
    ResourceGroup = local.namespace
    local.resource_stack_type_tag_key = local.resource_stack_type_tag_value
  }
}

resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.s3_bucket.id
  rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.kms_key.arn
      }
    } 
}

resource "aws_s3_bucket_public_access_block" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

/*******************************************************************************************
* Pay per request Makes the database serverless instead of provisioned
*
* https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table
*
********************************************************************************************/

resource "aws_dynamodb_table" "dynamodb_table" {
  name         = "${local.namespace}-state-lock"
  hash_key     = "LockID"
  billing_mode = "PAY_PER_REQUEST"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    ResourceGroup = local.namespace
    local.resource_stack_type_tag_key = local.resource_stack_type_tag_value
  }
}