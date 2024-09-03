/***********************************************************************
* We don't need a providers.tf because this is a module. The root module
* will implicitly pass all providers during initialization. 
************************************************************************/
terraform {
  required_version = ">= 0.15"
  required_providers {
      aws = {
          source = "hashicorp/aws"
          version = "~> 5.64.0"
      }
      random = {
          source = "hashicorp/random"
          version = "~> 3.6.2"
      }
  }
}