terraform {
    /*
    * backends are configured within Terraform settings
    *
    * If a configuration includes no backend block, Terraform defaults to using the 
    * local backend, which stores state as a plain file in the current working directory.
    *
    * https://developer.hashicorp.com/terraform/language/settings/backends/configuration
    * https://developer.hashicorp.com/terraform/language/settings/backends/s3
    */ 
  backend "s3" {
    // from aws backend module output
    bucket = var.bucket
    /**
    * We HAVE TO create a unique key for our project, which is basically just a prefix
    * to the object stored in S3
    */
    key = "team1/another-cool-project"
    /**
    * This is the region where the remote state backend lives and may be different 
    * than the region being deployed to. It cannot be configured via a variable as 
    * it is evaluated during initialization. 
    * 
    * from aws backend module output
    */ 
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

variable "region" {
    description = "AWS Region"
    type = string
}

provider "aws" {
  region = var.region
}

data "aws_ami" "ubuntu" {
    most_recent = true
    filter {
        name = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
    }
    owners = ["099720109477"]
}

resource "aws_instance" "instance" {
	ami = data.aws_ami.ubuntu.id
	instance_type = "t2.micro"
	tags = {
        // A special variable like "path", containing only one attribute: "workspace"
		Name = terraform.workspace
	}
}