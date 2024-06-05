variable "cidr-vpc" {
  description = "CIDR for VPC"
  type        = string
}

variable "cidr-subnets-public" {
  description = "CIDR for Public Subnets"
  type        = string
}

variable "profile" {
  description = "profile"
  type        = string
}

variable "cidr-subnets-private" {
  description = "CIDR for Private Subnets"
  type        = string
}

provider "aws" {
  region  = "us-east-1"
  profile = var.profile
}

#Create a VPC
resource "aws_vpc" "jenkins_vpc" {
  cidr_block           = var.cidr-vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "jenkins_vpc"
  }
}

#Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.jenkins_vpc.id
  cidr_block              = var.cidr-subnets-public
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = var.cidr-subnets-private
  availability_zone = "us-east-1a"
}

# Create an Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.jenkins_vpc.id
}

# Create a Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.jenkins_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

# Associate the Route Table
resource "aws_route_table_association" "route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.route_table.id
}

# Create a Security Group
resource "aws_security_group" "security_group" {
  vpc_id      = aws_vpc.jenkins_vpc.id
  description = "Allow SSH and HTTP/HTTPS"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_eip" "existing_eip" {
  filter {
    name   = "tag:Name"
    values = ["jenkins-ip"]
  }
}

# Find the latest Jenkins AMI
data "aws_ami" "jenkins_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["csye7125-ami-*"] # Replace with the AMI name pattern you're looking for
  }

  owners = ["self", "269002347067"] # Replace with your AWS account ID or the ID of the owner of the AMI
}

resource "aws_instance" "jenkins_instance" {
  ami                         = data.aws_ami.jenkins_ami.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.security_group.id]
  associate_public_ip_address = true
  key_name                    = "csye7125"

  # User data script to set up Jenkins
  user_data = file("script.sh")
  tags = {
    Name = "Jenkins Server"
  }
}

# Associate the existing Elastic IP with the EC2 instance
resource "aws_eip_association" "eip_association" {
  instance_id   = aws_instance.jenkins_instance.id
  allocation_id = data.aws_eip.existing_eip.id
}

output "vpc_id" {
  value = aws_vpc.jenkins_vpc.id
}
