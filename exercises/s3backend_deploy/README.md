# Deploy the AWS S3 Backend

As of 09 September 2024 using 0.6.0 

s3backend_config = {
  "bucket" = "team-nico-exspfwog32lchd-state-bucket"
  "dynamodb_table" = "team-nico-exspfwog32lchd-state-lock"
  "region" = "ap-southeast-2"
  "role_arn" = "arn:aws:iam::339078945058:role/team-nico-exspfwog32lchd-tf-assume-role"
}

Once you've done this you'll have nothing in the S3 bucket since you don't have any Terraform state yey, it's just
an empty bucket.
