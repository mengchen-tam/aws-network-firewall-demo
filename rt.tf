# Get main route table of inspection VPC
data "aws_route_table" "default" {
  vpc_id = aws_vpc.vpc.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# Override main route table of inspection VPC with empty routes
resource "aws_default_route_table" "default" {
  default_route_table_id = data.aws_route_table.default.id
  route = []
  tags = {
    Name = "default_route_table"
  }
}


# Route table for TGW attachment subnet in AZ 1a
# Routes all traffic to Network Firewall endpoint
resource "aws_route_table" "tgw_attach_subnet_cn_northwest_1a" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = [for state in aws_networkfirewall_firewall.inspection.firewall_status[0].sync_states : state.attachment[0].endpoint_id if state.availability_zone == aws_subnet.tgw_attach_subnet[0].availability_zone][0]
  }
  tags = {
    "Name" = "tgw_attach_subnet_cn_northwest_1a_rtb"
  }
}


# Associate TGW attachment subnet in AZ 1a with its route table
resource "aws_route_table_association" "tgw_attach_subnet_cn_northwest_1a_rt" {
  subnet_id      = aws_subnet.tgw_attach_subnet.*.id[0]
  route_table_id = aws_route_table.tgw_attach_subnet_cn_northwest_1a.id
  depends_on = [
    aws_subnet.tgw_attach_subnet
  ]
}

# Route table for TGW attachment subnet in AZ 1b
# Routes all traffic to Network Firewall endpoint
resource "aws_route_table" "tgw_attach_subnet_cn_northwest_1b" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block      = "0.0.0.0/0"
    vpc_endpoint_id = [for state in aws_networkfirewall_firewall.inspection.firewall_status[0].sync_states : state.attachment[0].endpoint_id if state.availability_zone == aws_subnet.tgw_attach_subnet[1].availability_zone][0]
  }
  tags = {
    "Name" = "tgw_attach_subnet_cn_northwest_1b_rtb"
  }
}

# Associate TGW attachment subnet in AZ 1b with its route table
resource "aws_route_table_association" "tgw_attach_subnet_cn_northwest_1b_rt" {
  subnet_id      = aws_subnet.tgw_attach_subnet.*.id[1]
  route_table_id = aws_route_table.tgw_attach_subnet_cn_northwest_1b.id
  depends_on = [
    aws_subnet.tgw_attach_subnet
  ]
}


#### Fireawll  Subnet Routes - Inspection VPC ####



resource "aws_route_table" "firewall_subnet_cn_northwest_1a" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block         = var.parent_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.*.id[0]
  }
  tags = {
    "Name" = "firewall_subnet_cn_northwest_1a_rtb"
  }
}


resource "aws_route_table_association" "firewall_subnet_rt_cn_northwest_1a" {
  subnet_id      = aws_subnet.firewall_subnet.*.id[0]
  route_table_id = aws_route_table.firewall_subnet_cn_northwest_1a.id
  depends_on = [
    aws_subnet.firewall_subnet
  ]
}



resource "aws_route_table" "firewall_subnet_cn_northwest_1b" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block         = var.parent_cidr_block
    transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.*.id[1]
  }
  tags = {
    "Name" = "firewall_subnet_cn_northwest_1b_rtb"
  }
}

resource "aws_route_table_association" "firewall_subnet_rt_cn_northwest_1b" {
  subnet_id      = aws_subnet.firewall_subnet.*.id[1]
  route_table_id = aws_route_table.firewall_subnet_cn_northwest_1b.id
  depends_on = [
    aws_subnet.firewall_subnet
  ]
}


#### NAT GATEWAY  Subnet Routes - Inspection VPC ####

resource "aws_route_table" "public_subnet_cn_northwest_1a" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block      = var.parent_cidr_block
    vpc_endpoint_id = [for state in aws_networkfirewall_firewall.inspection.firewall_status[0].sync_states : state.attachment[0].endpoint_id if state.availability_zone == aws_subnet.public_subnet[0].availability_zone][0]
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    "Name" = "public_subnet_cn_northwest_1a_rtb"
  }
}


resource "aws_route_table_association" "public_subnet_cn_northwest_1a_rt" {
  subnet_id      = aws_subnet.public_subnet[0].id
  route_table_id = aws_route_table.public_subnet_cn_northwest_1a.id
  depends_on = [
    aws_subnet.public_subnet
  ]
}

resource "aws_route_table" "public_subnet_cn_northwest_1b" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block      = var.parent_cidr_block
    vpc_endpoint_id = [for state in aws_networkfirewall_firewall.inspection.firewall_status[0].sync_states : state.attachment[0].endpoint_id if state.availability_zone == aws_subnet.public_subnet[1].availability_zone][0]
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    "Name" = "public_subnet_cn_northwest_1b_rtb"
  }
}

resource "aws_route_table_association" "public_subnet_cn_northwest_1b_rt" {
  subnet_id      = aws_subnet.public_subnet[1].id
  route_table_id = aws_route_table.public_subnet_cn_northwest_1b.id
  depends_on = [
    aws_subnet.public_subnet
  ]
}
