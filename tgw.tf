# Step 1: Create TGW with custom default route tables for TGW-attached firewall architecture
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Transit Gateway with TGW-attached Network Firewall"
  amazon_side_asn                 = "64526"
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"  # Enable to use spoke RT as default
  default_route_table_propagation = "enable"  # Enable to use firewall RT as default
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = {
    "Name" = "tgw_with_network_firewall"
  }
}

# Step 2: Create spoke and egress route tables for TGW-attached firewall architecture
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    "Name" = "spoke-route-table"
  }
}

resource "aws_ec2_transit_gateway_route_table" "egress" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    "Name" = "egress-route-table"
  }
}

# Step 3: Create firewall route table for TGW-attached Network Firewall
resource "aws_ec2_transit_gateway_route_table" "firewall" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    "Name" = "firewall-route-table"
  }
}

# Set spoke route table as default association route table
resource "aws_ec2_transit_gateway_default_route_table_association" "default_association" {
  transit_gateway_id             = aws_ec2_transit_gateway.tgw.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Set firewall route table as default propagation route table
resource "aws_ec2_transit_gateway_default_route_table_propagation" "default_propagation" {
  transit_gateway_id             = aws_ec2_transit_gateway.tgw.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

# Step 4: Create egress VPC attachment and associate with egress route table
resource "aws_ec2_transit_gateway_vpc_attachment" "egress" {
  subnet_ids         = [for subnet in aws_subnet.tgw_attach_subnet : subnet.id]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.vpc.id
  tags = {
    "Name" = "egress_attach"
  }
}

# Data source to get firewall attachment information
data "aws_ec2_transit_gateway_attachments" "firewall" {
  filter {
    name   = "transit-gateway-id"
    values = [aws_ec2_transit_gateway.tgw.id]
  }
  
  filter {
    name   = "resource-type"
    values = ["network-function"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
  
  depends_on = [aws_networkfirewall_firewall.tgw_attached]
}

# Add Name tag to the firewall TGW attachment
resource "aws_ec2_tag" "firewall_attachment_name" {
  resource_id = data.aws_ec2_transit_gateway_attachments.firewall.ids[0]
  key         = "Name"
  value       = "firewall-attachment"
  
  depends_on = [data.aws_ec2_transit_gateway_attachments.firewall]
}

# Note: Spoke VPCs automatically associate with default association route table (spoke RT)
# No explicit associations needed for spoke VPCs

# Egress VPC uses its own route table
resource "aws_ec2_transit_gateway_route_table_association" "egress_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
}

# Note: Firewall attachment also uses default association (spoke RT) for routing decisions
# No explicit association needed for firewall attachment

# Note: All VPC attachments automatically propagate routes to default propagation route table (firewall RT)
# This includes spoke VPCs and egress VPC routes

# Step 5: Create spoke VPC attachments for TGW-attached firewall architecture
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

# Route configuration for TGW-attached firewall architecture
# Spoke VPCs route all traffic (including inter-VPC and internet) through firewall
resource "aws_ec2_transit_gateway_route" "spoke_default_to_firewall" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_attachments.firewall.ids[0]
  
  depends_on = [aws_networkfirewall_firewall.tgw_attached, data.aws_ec2_transit_gateway_attachments.firewall]
}

# Firewall routes internet traffic to egress VPC
resource "aws_ec2_transit_gateway_route" "firewall_to_egress" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
}

# Note: Spoke VPC routes are automatically propagated to firewall route table
# through default propagation settings, no static routes needed

# Egress VPC also routes through firewall for return traffic inspection
resource "aws_ec2_transit_gateway_route" "egress_to_firewall" {
  destination_cidr_block         = var.parent_cidr_block
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_attachments.firewall.ids[0]
  
  depends_on = [aws_networkfirewall_firewall.tgw_attached, data.aws_ec2_transit_gateway_attachments.firewall]
}