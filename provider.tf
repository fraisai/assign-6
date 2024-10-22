terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "5.72.1"
        }
    }
}

provider "aws" {
    profile = "default"
    region  = var.region
}

/* AWS Certificate Manager requires all certificates in US East 1 */
provider "aws" {
  alias  = "acm"
  region = "us-east-1"
}

