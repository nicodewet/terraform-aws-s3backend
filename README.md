# Production-ready S3 Backend Module

## Context - Why?

So often this kind of material is done for you, as a professional software engineer, with pre-established *guardrails* as the reasoning, or various pigeon holing titles.

That makes sense. Unless you want to leearn about something and master it, so let's go.

## Introduction

The S3 backend module works as follows. State files are encrypted at rest using KMS. Access is controlled by a least-privileged IAM policy, and everything is synchronised with DynamoDB.

The S3 backend module contains shared state and is used by developers to manage shared infrastructure using 
an *initialized* local workspace.

A workspace needs the following variables defined in order to initialize and deploy against an S3 backend:

- Name of the S3 bucket
- Region the backend was deployed to
- Amazon Resource Name (ARN) of the role that can be assumed
- Name of the DynamoDB table

In this module we follow the [Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure).

## References

The following key references were leveraged in this work.

The first one is the key reference that I used and I've updated the publically available [S3 Backend Module source](https://github.com/terraform-in-action/manning-code/tree/master/chapter6) to use the latest provider versions (amongst other adaptations).

- [Terraform in Action, Chapter 6, Scott Winkler](https://www.manning.com/books/terraform-in-action) *I highly recommend buying a copy of this book.* 
- [Hashicorp S3 Backend Online Documentation](https://developer.hashicorp.com/terraform/language/settings/backends/s3)

## Basic Setup Instructions

You should use the [published module](https://registry.terraform.io/modules/nicodewet/s3backend/aws/latest) in another Terraform project, 
e.g. named *s3backend_deploy*.

As you would expect by convention the input variables are in the file *variables.tf*

You need to specify the **namespace** which should be your team name, or some other appropriate team name. Do not use the default value. The notion of team is mentioned because a key purpose of the S3 Backend Module is to share state between people. But it could also just be your personal state, in that case perhaps use your name (nico in my case) or company name (thorgil in my case).

Next you'll need to specify **principal_arns** and also the **force_destroy_state** which is true by default.

I've added an **Extensive Setup Instructions** section with references to exercises in the *exercises* folder as a means of remembering how 
to get going with the S3 Backend Module. Note [Terraform in Action, Chapter 6, Scott Winkler](https://www.manning.com/books/terraform-in-action) is the authoritative guide, these are my personal notes.

## S3 Backend Module Overview

![S3 backend flow](readme_pics/s3_backend_module_flow.png)

The S3 backend module has 3 input variables and one output variable. The output variable *config* contains the configuration for a workspace to initialise itself against the S3 backend.

## S3 Backend Module Input and Output Variables

![S3 backend variables](readme_pics/s3_module_variables.png)

Four distinct components comprise the S3 backend module:

- DynamoDB table - For state locking.
- S3 bucket and Key Management Service (KMS) key - For state storage and encryption at rest.
- Identity and Access Management (IAM) least-privileged role - So other AWS accounts can assume a role to this account and perform deployments against the S3 backend.
- Miscellaneous housekeeping resources.

The following diagram shows the four distinct components that make up the S3 Backend Module.

## S3 Backend Module Detailed Component Diagram

![S3 backend variables](readme_pics/s3_backend_module_components.png)

Because there is no dependency relationship between the modules, and so no resource hierarchy, and also because we have a small-to-medium sized cobebase a *flat module* can be used to organize the Terraform code. The advantage of the flat module,
rather than nested modules, is not needing to link modules together.

## S3 Backend Module is a Flat Module

Rather than using a nested module structure we've opted for a flat module structure.

![S3 backend variables](readme_pics/s3_backend_flat_module.png)

## Extensive Setup Instructions

This is a run through the exercises which I've adapted to suit my needs (e.g. using AWS regions in Asia Pacific).

### Terraform Registry Setup

This simply entailed following the [public module Terraform Registry publication requirements](https://developer.hashicorp.com/terraform/registry/modules/publish).

Once these requirements have been met [semantically versioned GitHub release tags automatically result in Terraform Registry module publication](https://developer.hashicorp.com/terraform/registry/modules/publish).

### s3backend_deploy

Resources have two tags:

- The first has Key **ResourceGroup** which is used by Terraform and has randomisation built into the value (see main.tf in the S3 Backend Module).
- The second has Key **Name** has the fixed value **terraform-s3backend-component** and is to populate this field in the AWS Console UI.

Now for the S3 Backend Configuration. 

Note the **priincipal_arns** variable has not been specified because as per the S3 Backend Module's **iam.tf** it will default to the AWS
caller identity's ARN, so your ARN, *which is good to start with*.

The ominoulsy named **force_destroy_state** variable hasn't been specified either as it only [applies when the bucket is destroyed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket#force_destroy).

```
s3backend_module/exercises/s3backend_deploy  (git)-[main]- % cat s3backend.tf 

provider "aws" {
    region  = "ap-southeast-2"
}

module "s3backend" {
    source      = "nicodewet/s3backend/aws"
    version     = "0.6.0"
    namespace   = "team-nico"
}

output "s3backend_config" {
    // config required to connect to the backend
    value = module.s3backend.config
}
```

Now let's deploy so we can start using it. 

I'm intentionally not using the *auto-approve* option along with the *apply* command as I feel it's important to pause
and study the output, even when one is very familiar with what the module does. 

```
s3backend_module/exercises/s3backend_deploy  (git)-[main]- % terraform init && terraform apply
```

In terms of the output, here is an example with identifiers scrambled. 

In the next step, namely s3backend_test, we'll abstracting sensitive ARNs and this means using placeholders 
or environment variables instead of hardcoding them.

```
s3backend_config = {
  "bucket" = "team-nico-g502k751zdtty1-state-bucket"
  "dynamodb_table" = "team-nico-g502k751zdtty1-state-lock"
  "region" = "ap-southeast-2"
  "role_arn" = "arn:aws:iam::111111111111:role/team-nico-g502k751zdtty1-tf-assume-role"
}
```

### s3backend_test

Firstly inspect test.tf and notice the variables in the s3 backend declaration section which we'll populate using environment variables 
and command line flags.

The s3 backend configuration with the variable declerations follows.

```
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
```

Now initialise Terraform and the s3 backend in particular.

```
s3backend_module/exercises/s3backend_test % export ROLE_ARN='arn:aws:iam::111111111111:role/team-nico-g502k751zdtty1-tf-assume-role'
s3backend_module/exercises/s3backend_test % export DYNAMODB_TABLE='team-nico-g502k751zdtty1-state-lock'
s3backend_module/exercises/s3backend_test % export REGION='ap-southeast-2'
s3backend_module/exercises/s3backend_test % export BUCKET='team-nico-g502k751zdtty1-state-bucket'
s3backend_module/exercises/s3backend_test % terraform init \
-backend-config="bucket=$BUCKET" \
-backend-config="dynamodb_table=$DYNAMODB_TABLE" \
-backend-config="region=$REGION" \
-backend-config="role_arn=$ROLE_ARN"
```

So now let's get the [null_resource](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) to do 
run a command locally as a test, then run it again to convince yourself the null_resource will be replaced on each run.

```
s3backend_module/exercises/s3backend_test % terraform apply -auto-approve
null_resource.DI_FM_Radio: Refreshing state... [id=6831082778838108296]

Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
-/+ destroy and then create replacement

Terraform will perform the following actions:

  # null_resource.DI_FM_Radio must be replaced
-/+ resource "null_resource" "DI_FM_Radio" {
      ~ id       = "6831082778838108296" -> (known after apply)
      ~ triggers = { # forces replacement
          ~ "always" = "2024-09-13T23:43:37Z" -> (known after apply)
        }
    }

Plan: 1 to add, 0 to change, 1 to destroy.
null_resource.DI_FM_Radio: Destroying... [id=6831082778838108296]
null_resource.DI_FM_Radio: Destruction complete after 0s
null_resource.DI_FM_Radio: Creating...
null_resource.DI_FM_Radio: Provisioning with 'local-exec'...
null_resource.DI_FM_Radio (local-exec): Executing: ["/bin/sh" "-c" "echo 'Bass & Jackin House'"]
null_resource.DI_FM_Radio (local-exec): Bass & Jackin House
null_resource.DI_FM_Radio: Creation complete after 0s [id=3461312214203961120]

Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

As a final check, navigate to the Resource Groups view on the AWS Console, your team's S3 backend should be easy to find. Then click on the S3
component and notice the *team1* folder with *my-cool-project* state file.

A swifter way of figuring out what state exists is to run the *state list* command as follows.

```
s3backend_module/exercises/s3backend_test % terraform state list
null_resource.DI_FM_Radio
```

At this stage we've made good progress, but we'll want to use workspaces to be truly effective in a team environment. We'll move onto the next 
section for that.

### s3backend_with_workspaces

#### Why workspaces?

Workspaces give you the ability to have more than one state file with the same configuration code.

Each workspace has a variable definitions file to parameterize the environment. The net benefit is not having to copy and past configuration code
on a per environment basis.

### Implementation

The S3 backend initialization is as before in terms of feeding environment variables into the backend-config command line parameters.

We want to avoid using the *default* workspace which is what you would be on after initialisaing Terraform without specifying a workspace. 
We'll confirm this first and then dive into targeted workspace initialization.

#### The default workspace

This example is just to illustrate the behaviour of Terraform directly after initialisation.

```
s3backend_module/exercises/s3backend_with_workspaces % terraform init \
-backend-config="bucket=$BUCKET" \
-backend-config="dynamodb_table=$DYNAMODB_TABLE" \
-backend-config="region=$REGION" \
-backend-config="role_arn=$ROLE_ARN"
s3backend_module/exercises/s3backend_with_workspaces % terraform workspace list
* default
```

We'll now move onto using our **environments/dev.tfvars** and **environments/prod.tfvars** workspace variable definition files.

#### Using environment workspace definition files

A feature branch name or more traditional environment name could be used. Here we're using *dev* and *prod*.

It is best to switch to a non default environment immediately.

Take a look at main.tf and environments/dev.tfvars to see we'll be deploying an EC2 instance to the **ap-southeast-2** region (Sydney).

```
s3backend_module/exercises/s3backend_with_workspaces  (git)-[main]- % terraform workspace new dev
Created and switched to workspace "dev"!

You're now on a new, empty workspace. Workspaces isolate their state,
so if you run "terraform plan" Terraform will not see any existing state
for this configuration.

s3backend_module/exercises/s3backend_with_workspaces % terraform apply -var-file=./environments/dev.tfvars -auto-approve
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Now let's switch to the *prod* workspace and launch an EC2 instance in the ap-northeast-1 (Tokyo) region.

```
3backend_module/exercises/s3backend_with_workspaces % terraform workspace new prod
Created and switched to workspace "prod"!
s3backend_module/exercises/s3backend_with_workspaces % terraform apply -var-file=./environments/prod.tfvars -auto-approve
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

The image that follows shows what our state looks like after these two deployments. There will still be *default* state at 
the top level because we did not use environment workspaces in our *s3backend_test* exercise.

![S3 backend variables](readme_pics/S3_State_Env_Workspaces.png)

#### Cleanup

Let's delete the EC2 instance from each environment and then also delete the entire S3 backend to competely clean up. Of course
you won't do the latter in a team environment but this is an exercise.

Our configuration is still set at the prod environment so that will get destroyed first. We'll then switch to dev and then
navigate to the s3backend_deploy directory to destroy the S3 backend.

If you forget to specify the region (by not including the -var-file=./environments/prod.tfvars) you'll be prompted for the 
variable value.

```
s3backend_module/exercises/s3backend_with_workspaces % terraform destroy -var-file=./environments/prod.tfvars -auto-approve
Destroy complete! Resources: 1 destroyed.
s3backend_module/exercises/s3backend_with_workspaces % terraform workspace select dev
Switched to workspace "dev".
s3backend_module/exercises/s3backend_with_workspaces % terraform destroy -var-file=./environments/dev.tfvars -auto-approve
Destroy complete! Resources: 1 destroyed.
s3backend_module/exercises/s3backend_with_workspaces % cd ../s3backend_deploy
s3backend_module/exercises/s3backend_deploy % terraform destroy -auto-approve
Destroy complete! Resources: 11 destroyed.
```

## Future Work

### What about a continuous build and deploy pipeline for this very S3 Backend Module?

**This is planned as future work.**

It is important to have a periodic, say daily (even without commits), build and deploy of this module.

Implementing CI/CD, say using GitHub Actions, will proactively ensure that this module remains stable and 
functional over time.

In a generic sense, doing so offer the following benefits:

- **Automated Testing**: Every time you or someone else makes changes to the module, you can automatically run 
tests (e.g., terraform validate, terraform plan) to ensure no regressions or issues are introduced.

- **Versioning Control**: You can automate the process of version tagging and releasing new versions to the Terraform 
registry, ensuring consistent version management.

- **Early Detection**: If dependencies or underlying services change, tests will catch those issues before they impact users.

- **Confidence for Public Users**: As it's publicly available, external users will have more confidence in a module that is 
rigorously tested and maintained.