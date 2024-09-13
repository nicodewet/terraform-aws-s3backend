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
    bucket = var.bucket
    /**
    * We HAVE TO create a unique key for our project, which is basically just a prefix
    * to the object stored in S3
    */
    key = "team1/my-cool-project"
    // from aws backend module output
    region = var.region
    encrypt = true
    // from aws backend module output
    role_arn = var.role_arn
    // from aws backend module output
    dynamodb_table = var.dynamodb_table
  }
  required_version = ">= 0.15"
  required_providers {
    null = {
        source = "hashicorp/null"
        version = "~> 3.0"
    }
  }
}

/**
* The null_resource is a placeholder resource that doesn't create any infrastructure but can
* trigger provisioners based on changes to its triggers argument.
*/
resource "null_resource" "DI_FM_Radio" {
    triggers = {
      /**
      * The triggers block in null_resource ensures that the local-exec command is 
      * run every time Terraform applies, because timestamp() makes the resource 
      * change every time it's run.
      */
        always = timestamp() # This ensures the command will always run.
    }
    provisioner "local-exec" {
        // The actual command you want to run locally. This can be anything 
        // executable on your local machine.
        command = "echo 'Bass & Jackin House'"
    }
}