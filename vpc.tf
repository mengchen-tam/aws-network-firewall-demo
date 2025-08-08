## CREATE EGRESS VPC ###

resource "aws_vpc" "vpc" {
  cidr_block           = var.egress_vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    "Name" = "egress_vpc"
  }
}

### CREATE PUBLIC AND TGW ATTACHMENT SUBNETS IN 2 AZs###

resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.egress_vpc_cidr_block, 4, count.index)
  tags = {
    Name = "egress_public_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_subnet" "tgw_attach_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.egress_vpc_cidr_block, 4, count.index + 2)
  tags = {
    Name = "egress_tgw_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

### IGW ###

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "egress_vpc_igw"
  }
}

## NAT GATEWAYS FOR EGRESS VPC ## 

resource "aws_eip" "ngw_eip" {
  count = length(aws_subnet.public_subnet.*.id)
  tags = {
    Name = "egress_nat_eip_${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  count         = length(aws_subnet.public_subnet.*.id)
  allocation_id = aws_eip.ngw_eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id
  tags = {
    "Name" = "egress_natgw_${data.aws_availability_zones.available.names[count.index]}"
  }
  depends_on = [
    aws_internet_gateway.igw
  ]
}
