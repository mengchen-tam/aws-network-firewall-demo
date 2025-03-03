# ### CREATE SECOND SPOKE VPC ###

resource "aws_vpc" "spoke_vpc_2" {
  cidr_block           = var.spoke_vpc2_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    "Name" = "spoke_vpc_2"
  }
}

# ### CREATE PRIVATE SUBNETS ###

resource "aws_subnet" "app_subnet_2" {
  count                   = 2
  vpc_id                  = aws_vpc.spoke_vpc_2.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet("${aws_vpc.spoke_vpc_2.cidr_block}", 4, "${1 + count.index}")
  tags = {
    Name = "spoke_vpc_2_private_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

resource "aws_subnet" "app_tgw_subnet_2" {
  count                   = 2
  vpc_id                  = aws_vpc.spoke_vpc_2.id
  map_public_ip_on_launch = false
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  cidr_block              = cidrsubnet("${aws_vpc.spoke_vpc_2.cidr_block}", 4, "${3 + count.index}")
  tags = {
    Name = "spoke_vpc_2_tgw_subnet_${data.aws_availability_zones.available.names[count.index]}"
  }
}

# #### Spoke VPC 2 Subnet Routes ####

resource "aws_route_table" "spoke_vpc_2_subnets_rt" {
  vpc_id = aws_vpc.spoke_vpc_2.id
  route {
    cidr_block         = "0.0.0.0/0"
    transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  }
  tags = {
    "Name" = "spoke_vpc_2_subnet_rtb"
  }
}

resource "aws_route_table_association" "spoke_vpc_2_subnets_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.app_subnet_2[count.index].id
  route_table_id = aws_route_table.spoke_vpc_2_subnets_rt.id
}

resource "aws_route_table" "spoke_vpc_2_tgw_subnets_rt" {
  vpc_id = aws_vpc.spoke_vpc_2.id
  tags = {
    "Name" = "spoke_vpc_2_tgw_subnet_rtb"
  }
}

resource "aws_route_table_association" "spoke_vpc_2_tgw_subnets_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.app_tgw_subnet_2[count.index].id
  route_table_id = aws_route_table.spoke_vpc_2_tgw_subnets_rt.id
}

# #### Spoke VPC 2 Security Groups ###


resource "aws_instance" "spoke_vm_2" {
  count                  = 2
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.spoke_2.id]
  subnet_id              = aws_subnet.app_subnet_2[count.index].id
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }
  tags = {
    "Name" = "spoke_vpc_2_vm_${data.aws_availability_zones.available.names[count.index]}"
  }
  depends_on = [
    aws_security_group.spoke_2
  ]
}

## SSM Endpoints for EC2 Connectivity ###

resource "aws_vpc_endpoint" "spoke_vpc_2_ssm_ep" {
  count             = 2
  subnet_ids        = [for subnet in aws_subnet.app_subnet_2 : subnet.id]
  vpc_endpoint_type = "Interface"
  service_name      = [
    "com.amazonaws.${var.aws_region}.ssm",
    "com.amazonaws.${var.aws_region}.ssmmessages",
    "com.amazonaws.${var.aws_region}.ec2messages"
  ][count.index]
  private_dns_enabled = true
  ip_address_type     = "ipv4"
  security_group_ids  = [aws_security_group.ssm_ep_2.id]
  dns_options {
    dns_record_ip_type = "ipv4"
  }
  vpc_id = aws_vpc.spoke_vpc_2.id
  tags = {
    "Name" = "spoke_vpc_2_ssm_endpoint_${data.aws_availability_zones.available.names[count.index]}"
  }
}
