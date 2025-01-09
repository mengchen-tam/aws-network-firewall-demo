## CREATE VPC ###

resource "aws_vpc" "vpc" {
  cidr_block           = var.inspection_vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    "Name" = "inspection_vpc"
  }
}

### CREATE DATA, MGMT AND PRIVATE SUBNETS IN 2 AZs###

resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.inspection_vpc_cidr_block, 4, count.index)
  tags = {
    Name = "public_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_subnet" "tgw_attach_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.inspection_vpc_cidr_block, 4, count.index + 2)
  tags = {
    Name = "tgw_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_subnet" "firewall_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet(var.inspection_vpc_cidr_block, 4, count.index + 4)
  tags = {
    Name = "firewall_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

### IGW ###

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "IGW"
  }
}

## NGW ## 


resource "aws_eip" "ngw_eip" {
  count = length(aws_subnet.public_subnet.*.id)
}

resource "aws_nat_gateway" "nat_gateway" {
  count         = length(aws_subnet.public_subnet.*.id)
  allocation_id = aws_eip.ngw_eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id
  tags = {
    "Name" = "natgw_${data.aws_availability_zones.available.names[count.index]}"
  }
  depends_on = [
    aws_internet_gateway.igw
  ]
}
