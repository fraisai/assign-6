variable "region" {
    default                 = "eu-north-1"
    description             = "AWS region"
    type                    = string
}

variable "aditya_domain" {
    default                 = "aditya-dev.com"
}
variable "vpc_cidr" {
    default                 = "10.100.0.0/16"
    type                    = string
}

variable "subnet_public_cidr" {
    type                    = list(string)
    description             = "CIDR Block for Public Subnets in VPC"
    default                 = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "subnet_private_cidr" {
    type                    = list(string)
    description             = "CIDR Block for Private Subnets in VPC"
    default                 = ["10.0.103.0/24", "10.0.104.0/24"]
}

variable "subnet_count" {
    description = "Number of public/private subnets"
    type = map(number)
    default = {
        public = 2
        private = 2
    }
}

variable "allocate_id" {
    type = string
    description = "EIP allocation ID for fariha-eip-1"
    default = "eipalloc-07723985fdd8e376f"
}


variable "f_ip" {
    sensitive               = true
    type                    = string
}
