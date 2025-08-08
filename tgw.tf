# Step 1: Create TGW with default route tables disabled for manual control
resource "aws_ec2_transit_gateway" "tgw" {
  description                     = "Transit Gateway with TGW-attached Network Firewall"
  amazon_side_asn                 = "64526"
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"  # Disable for manual control
  default_route_table_propagation = "disable"  # Disable for manual control
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = {
    "Name" = "tgw_with_network_firewall"
  }
}

# Step 2: Create spoke, egress and firewall route tables for TGW-attached firewall architecture
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

resource "aws_ec2_transit_gateway_route_table" "firewall" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = {
    "Name" = "firewall-route-table"
  }
}

# Step 3: Manual route table associations for predictable behavior

# Step 4: Create egress VPC attachment and associate with egress route table
resource "aws_ec2_transit_gateway_vpc_attachment" "egress" {
  subnet_ids                                      = [for subnet in aws_subnet.tgw_attach_subnet : subnet.id]
  transit_gateway_id                              = aws_ec2_transit_gateway.tgw.id
  vpc_id                                          = aws_vpc.vpc.id
  transit_gateway_default_route_table_association = false  # Override default association for egress VPC
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

# Manual route table associations for predictable behavior
resource "aws_ec2_transit_gateway_route_table_association" "spoke_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke2_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

resource "aws_ec2_transit_gateway_route_table_association" "egress_assoc" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
}

resource "aws_ec2_transit_gateway_route_table_association" "firewall_assoc" {
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_attachments.firewall.ids[0]
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
  
  depends_on = [aws_networkfirewall_firewall.tgw_attached, data.aws_ec2_transit_gateway_attachments.firewall]
}

# Manual route table propagations for predictable behavior
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_to_firewall" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke2_to_firewall" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke2.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "egress_to_firewall" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.firewall.id
}

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

# Egress VPC also routes through firewall for return traffic inspection
resource "aws_ec2_transit_gateway_route" "egress_to_firewall" {
  destination_cidr_block         = var.parent_cidr_block
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.egress.id
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_attachments.firewall.ids[0]
  
  depends_on = [aws_networkfirewall_firewall.tgw_attached, data.aws_ec2_transit_gateway_attachments.firewall]
}