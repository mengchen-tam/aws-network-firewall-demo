#### CREATE SGs ####

resource "aws_security_group" "spoke" {
  name        = "spoke_sg"
  description = "Spoke VPC - Security Group"
  vpc_id      = aws_vpc.spoke_vpc.id
  
  ingress {
    cidr_blocks = [var.parent_cidr_block]
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
  }

  # Only allow outbound traffic
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
  }
  
  tags = {
    "Name" = "spoke_sg"
  }
}


resource "aws_security_group" "ssm_ep" {
  name        = "ssm_ep_sg"
  description = "SSM EP - Spoke VPC Security Group"
  vpc_id      = aws_vpc.spoke_vpc.id
  ingress {
    cidr_blocks = ["${aws_vpc.spoke_vpc.cidr_block}"]
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
  }
  tags = {
    "Name" = "ssm_ep_sg"
  }
}

# spoke2 Security Groups
resource "aws_security_group" "spoke_2" {
  name        = "spoke_vpc_2_sg"
  description = "Allow SSH and HTTP access"
  vpc_id      = aws_vpc.spoke_vpc_2.id

  ingress {
    cidr_blocks = [var.parent_cidr_block]
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "spoke_vpc_2_sg"
  }
}

resource "aws_security_group" "ssm_ep_2" {
  name        = "spoke_vpc_2_ssm_ep_sg"
  description = "Allow SSM endpoint access"
  vpc_id      = aws_vpc.spoke_vpc_2.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.spoke_vpc_2.cidr_block}"]
  }

  tags = {
    Name = "spoke_vpc_2_ssm_ep_sg"
  }
}
