terraform {
    /*
    * backends are configured within Terraform settings
    *
    * If a configuration includes no backend block, Terraform defaults to using the 
    * local backend, which stores state as a plain file in the current working directory.
    *
    * https://developer.hashicorp.com/terraform/language/settings/backends/configuration
    */ 
  backend "s3" {
    // from aws backend module output
    bucket = "team-nico-exspfwog32lchd-state-bucket"
    /**
    * We HAVE TO create a unique key for our project, which is basically just a prefix
    * to the object stored in S3
    */
    key = "team1/my-cool-project"
    // from aws backend module output
    region = "ap-southeast-2"
    encrypt = true
    // from aws backend module output
    role_arn = "arn:aws:iam::339078945058:role/team-nico-exspfwog32lchd-tf-assume-role"
    // from aws backend module output
    dynamodb_table = "team-nico-exspfwog32lchd-state-lock"
  }
  required_version = ">= 0.15"
  required_providers {
    null = {
        source = "hashicorp/null"
        version = "~> 3.0"
    }
  }
}

resource "null_resource" "motto" {
    triggers = {
        always = timestamp()
    }
    provisioner "local-exec" {
        // this is where the magic happens
        command = "echo gotta catch em all"
    }
}