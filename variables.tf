variable "egress_vpc_cidr_block" {
  type        = string
  description = "CIDR block for the egress VPC that provides internet connectivity via NAT gateways"
  default     = "10.10.255.0/24"
}

variable "spoke_vpc_cidr_block" {
  type        = string
  description = "CIDR block for the spoke VPC"
  default     = "10.10.1.0/24"
}

variable "spoke_vpc2_cidr_block" {
  type        = string
  description = "CIDR block for the second spoke VPC"
  default     = "10.10.2.0/24"
}

variable "parent_cidr_block" {
  type        = string
  description = "Parent CIDR block to summarize all spoke VPCs"
  default     = "10.10.0.0/18"
}

variable "aws_region" {
  type        = string
  default     = "cn-northwest-1"
  description = "AWS region to deploy resources (e.g. cn-north-1, cn-northwest-1)"
}

