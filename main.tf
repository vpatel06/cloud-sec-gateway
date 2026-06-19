# =====================================================================
# 1. NETWORKING LAYER
# =====================================================================

resource "aws_vpc" "vanij_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "vanij_vpc_secure"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vanij_vpc.id
  tags   = { Name = "vanij_igw_secure" }
}

resource "aws_subnet" "public_subnet" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.vanij_vpc.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = cidrsubnet(aws_vpc.vanij_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true

  tags = { Name = "vanij_subnet_${var.availability_zones[count.index]}" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vanij_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "vanij_public_rt_secure" }
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# =====================================================================
# 2. HARDENED PERIMETER FIREWALL — zero inbound SSH/HTTP, WireGuard only
# =====================================================================

resource "aws_security_group" "hardened_sg" {
  name        = "vanij_hardened_sg_secure"
  vpc_id      = aws_vpc.vanij_vpc.id
  description = "Zero inbound SSH/HTTP. WireGuard UDP only. SSM handles admin access."

  ingress {
    description = "WireGuard VPN tunnel"
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound HTTPS - updates, SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound HTTP - apt repos"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vanij_hardened_firewall" }
}

# =====================================================================
# 3. IAM ROLE FOR SSM
# =====================================================================

resource "aws_iam_role" "ssm_role" {
  name = "vanij_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "vanij_ssm_role" }
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "vanij_ssm_profile"
  role = aws_iam_role.ssm_role.name
}

# =====================================================================
# 4. SECURE COMPUTE ENGINE
# =====================================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "secure_gateway" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.public_subnet[0].id
  vpc_security_group_ids = [aws_security_group.hardened_sg.id]
  iam_instance_profile    = aws_iam_instance_profile.ssm_profile.name

  user_data = <<-EOF
    #!/bin/bash
    snap install amazon-ssm-agent --classic
    snap start amazon-ssm-agent
  EOF

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted              = true
    delete_on_termination = true
  }

  tags = { Name = "vanij_secure_gateway" }
}