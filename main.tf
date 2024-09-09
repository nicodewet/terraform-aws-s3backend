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
  /**
  * Prefix with built in uniqueness used in all S3 Backend Module resource names and AWS Resource Group tag values.
  */
  namespace = substr( join("-", [var.namespace, random_string.rand.result, "terraform-3backend"]), 0, 24 )
  /** 
  * The resource_tag_name is the value of the "Tag: Name" which is mainly important from an AWS Console
  * use case perspective. It matters for the following AWS Console user-friendliness centered use cases. Note, 
  * these use cases don't matter when solely relying on Terraform for managing and organizing resources (without 
  * much manual interaction in the AWS Console).
  *
  * 1. Ease of Identification: It makes it easier to identify and manage resources in the AWS Console. Without 
  *                            a Name tag, resources can appear only with unique identifiers making it more 
  *                            challenging to differentiate between them.
  * 2. Search & Filtering in AWS Console: The Name tag is frequently used for filtering and searching resources 
  *                          within the AWS Management Console.
  * 3. Resource Groups: When using AWS Resource Groups and tagging-based resource management, as we do in this 
  *                    S3 Backend Module, having consistent tags, including Name, improves the usability of these 
  *                    tools. 
  */
  resource_aws_console_tag_name = "terraform-s3backend-component"
}

/*******************************************************************************************************
* Put resources into a query-based AWS Resource Groups group based on the common tag filter namely the 
* ResourceGroup key and local.namespace value.
*
* Our TagFilter Key of ResourceGroup and Value of local.namespace places a constraint on any S3 Backend 
* Module resources that we privision. The key of ResourceGroup and value of local.namespace MUST be used
* in order for the mentioned TagFilter to function.
*
* https://docs.aws.amazon.com/ARG/latest/userguide/gettingstarted-query.html
* https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/resourcegroups_group
******************************************************************************************************/
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
    // The following tag is required as per our AWS Resource Groups tag-based TagFilter query filter specification.
    ResourceGroup = local.namespace
    // The following tag is required from an AWS Console user-friendliness perspective.
    Name = "${local.resource_aws_console_tag_name}"
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
    // The following tag is required as per our AWS Resource Groups tag-based TagFilter query filter specification.
    ResourceGroup = local.namespace
    // The following tag is required from an AWS Console user-friendliness perspective.
    Name = "${local.resource_aws_console_tag_name}"
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
    // The following tag is required as per our AWS Resource Groups tag-based TagFilter query filter specification.
    ResourceGroup = local.namespace
    // The following tag is required from an AWS Console user-friendliness perspective.
    Name = "${local.resource_aws_console_tag_name}"
  }
}