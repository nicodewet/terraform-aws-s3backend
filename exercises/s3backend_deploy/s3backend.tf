/*******************************************************************************************
* You can use the for-each meta-argument to deploy multiple copies of the s3 backend module.
********************************************************************************************/

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
