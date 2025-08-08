# Get main route table of egress VPC
data "aws_route_table" "default" {
  vpc_id = aws_vpc.vpc.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# Override main route table of egress VPC with empty routes
resource "aws_default_route_table" "default" {
  default_route_table_id = data.aws_route_table.default.id
  route                  = []
  tags = {
    Name = "egress_vpc_default_route_table"
  }
}

# Route table for TGW attachment subnets in egress VPC
# Simple routing to NAT gateways for internet access
resource "aws_route_table" "tgw_attach_subnet" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[0].id
  }
  tags = {
    "Name" = "egress_tgw_attach_subnet_rtb"
  }
}

# Associate TGW attachment subnets with simplified route table
resource "aws_route_table_association" "tgw_attach_subnet_rt" {
  count          = length(aws_subnet.tgw_attach_subnet)
  subnet_id      = aws_subnet.tgw_attach_subnet[count.index].id
  route_table_id = aws_route_table.tgw_attach_subnet.id
}


# Route table for public subnets in egress VPC
# Simple routing to internet gateway for NAT gateway connectivity
resource "aws_route_table" "public_subnet" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  # Return route for spoke VPCs traffic (aggregated CIDR)
  route {
    cidr_block         = var.parent_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  }

  tags = {
    "Name" = "egress_public_subnet_rtb"
  }
}

# Associate public subnets with simplified route table
resource "aws_route_table_association" "public_subnet_rt" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_subnet.id
}
