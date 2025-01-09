# Step 1: Create TGW with default route tables disabled
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Transit Gateway FOR CENTRALIZED EGRESS"
  amazon_side_asn                 = "64526"
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = {
    "Name" = "tgw_inspection_vpc"
  }
}

# Step 2: Create spoke and inspection route tables
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    "Name" = "spoke"
  }
}

resource "aws_ec2_transit_gateway_route_table" "inspection" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    "Name" = "inspection"
  }
}

# Step 4: Create inspection VPC attachment and associate with inspection route table
resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  subnet_ids             = [for subnet in aws_subnet.tgw_attach_subnet : subnet.id]
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
  vpc_id                 = aws_vpc.vpc.id
  appliance_mode_support = "enable"
  tags = {
    "Name" = "inspection_attach"
  }
}

# Manual associations
resource "aws_ec2_transit_gateway_route_table_association" "spoke_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke2_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "inspection_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Manual propagations
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_prop" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke2_prop" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.inspection.id
}

# Step 5: Create spoke VPC attachments and add default route to inspection
resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  subnet_ids         = [for subnet in aws_subnet.app_tgw_subnet : subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.spoke_vpc.id
  tags = {
    "Name" = "spoke_attach"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke2" {
  subnet_ids         = [for subnet in aws_subnet.app_tgw_subnet_2 : subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.spoke_vpc_2.id
  tags = {
    "Name" = "spoke2_attach"
  }
}

# Add default route in spoke route table pointing to inspection VPC
resource "aws_ec2_transit_gateway_route" "spoke_rt" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.inspection.id
}
