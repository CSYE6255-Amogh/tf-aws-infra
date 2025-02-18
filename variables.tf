variable "aws_profile" {
  description = "AWS profile to use"
  type        = string
  default     = "dev"
}
variable "aws_region" {
  description = "AWS region to use"
  type        = string
  default     = "us-east-1"
  
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "my-vpc-new"

}

variable "igw_name" {
  description = "Name of the Internet Gateway"
  type        = string
  default     = "my-igw"

}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_name" {
  description = "Name of the public subnets"
  type        = string
  default     = "my-public-subnet"

}

variable "destination_public_cidr" {
  description = "Destination CIDR block for the public route"
  type        = string
  default     = "0.0.0.0/0"
}
variable "private_subnet_name" {
  description = "Name of the private subnets"
  type        = string
  default     = "my-private-subnet"

}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
