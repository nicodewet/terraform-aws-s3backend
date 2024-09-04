output "config" {
  value = {
    /**
    * This S3 bucket is used for Terraform state storage. The state file records infrastructure resources that Terraform 
    * manages, allowing Terraform to reconcile the current infrastructure with what is already in production. Because the 
    * state file may contain sensitive information (such as secrets or resource configurations), the contents are encrypted, 
    * either using AWS Key Management Service (SSE-KMS). S3 versioning is also applied to maintain a history of state 
    * changes and enable rollback if necessary.
    * See: https://developer.hashicorp.com/terraform/language/state
    */
    bucket         = aws_s3_bucket.s3_bucket.bucket
    /**
    * The AWS region the backend was deployed to.
    */
    region         = data.aws_region.current.name
    /**
    * Amazon Resource Name (ARN) of the role that can be assumed.
    */ 
    role_arn       = aws_iam_role.iam_role.arn
    /**
    * Terraform S3 state locking is used to prevent race conditions during simultaneous updates to the state file. This 
    * locking mechanism is managed through a separate DynamoDB table, which stores lock data to ensure that only one 
    * operation can modify the state at any given time.
    */
    dynamodb_table = aws_dynamodb_table.dynamodb_table.name
  }
}