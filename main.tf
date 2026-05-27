provider "aws" {
  region = var.aws_region
}

locals {
  # Replaced spaces with a hyphen for consistent cloud naming conventions
  vpc_name     = "${var.env_name}-${var.vpc_name}"
  cluster_name = "${var.cluster_name}-${var.env_name}"
}

## AWS VPC definition
resource "aws_vpc" "main" {
  cidr_block           = var.main_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    "Name"                                        = local.vpc_name
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Subnets (Renamed hyphens to underscores for idiomatic resource names)
resource "aws_subnet" "public_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                        = "${local.vpc_name}-public-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "public_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                        = "${local.vpc_name}-public-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "private_subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    "Name"                                        = "${local.vpc_name}-private-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_subnet" "private_subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    "Name"                                        = "${local.vpc_name}-private-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.vpc_name}-igw"
  }
}

# Route Tables (Decoupled inline routes)
resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

  tags = {
    "Name" = "${local.vpc_name}-public-route"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public_route.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a_association" {
  subnet_id      = aws_subnet.public_subnet_a.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table_association" "public_b_association" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_eip" "nat_a" {
  domain = "vpc"
  tags = {
    "Name" = "${local.vpc_name}-NAT-a"
  }
}

resource "aws_eip" "nat_b" {
  domain = "vpc"
  tags = {
    "Name" = "${local.vpc_name}-NAT-b"
  }
}

resource "aws_nat_gateway" "nat_gw_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id      = aws_subnet.public_subnet_a.id
  depends_on     = [aws_internet_gateway.igw]

  tags = {
    "Name" = "${local.vpc_name}-NAT-gw-a"
  }
}

resource "aws_nat_gateway" "nat_gw_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id      = aws_subnet.public_subnet_b.id
  depends_on     = [aws_internet_gateway.igw]

  tags = {
    "Name" = "${local.vpc_name}-NAT-gw-b"
  }
}

resource "aws_route_table" "private_route_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    "Name" = "${local.vpc_name}-private-route-a"
  }
}

resource "aws_route" "private_nat_a" {
  route_table_id         = aws_route_table.private_route_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw_a.id
}

resource "aws_route_table" "private_route_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    "Name" = "${local.vpc_name}-private-route-b"
  }
}

resource "aws_route" "private_nat_b" {
  route_table_id         = aws_route_table.private_route_b.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw_b.id
}

resource "aws_route_table_association" "private_a_association" {
  subnet_id      = aws_subnet.private_subnet_a.id
  route_table_id = aws_route_table.private_route_a.id
}

resource "aws_route_table_association" "private_b_association" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_route_b.id
}

resource "aws_route53_zone" "private_zone" {
  # Corrected function syntax to guarantee a lowercase DNS entry
  name          = lower("${var.env_name}.${var.vpc_name}.com")
  force_destroy = true

  vpc {
    vpc_id = aws_vpc.main.id
  }
}
