provider "aws" {
  region = "us-east-1"
  profile = "admin"
}

# Create a VPC
resource "aws_vpc" "jenkins_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name= "jenkins_vpc"
  }
}

#Create subnets
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = "10.0.2.0/24"
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

# Associate the Route Table with the public subnet
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

# Create a key pair
resource "aws_key_pair" "jenkins_key_pair" {
  key_name   = "jenkins-key-pair"
  public_key = file("~/.ssh/id_rsa.pub") # Path to your public key file
}

# Launch an EC2 instance with the Jenkins AMI
resource "aws_instance" "jenkins_instance" {
  ami                         = data.aws_ami.jenkins_ami.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.security_group.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.jenkins_key_pair.key_name

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y nginx certbot python3-certbot-nginx
    sudo systemctl start nginx
    sudo certbot --nginx -d jenkins.kshitijprabhu.me -d www.jenkins.kshitijprabhu.me
    sudo systemctl reload nginx
    # Jenkins setup commands here
  EOF
}

# Associate the existing Elastic IP with the EC2 instance
resource "aws_eip_association" "eip_association" {
  instance_id   = aws_instance.jenkins_instance.id
  allocation_id = data.aws_eip.existing_eip.id
}

output "vpc_id" {
  value = aws_vpc.jenkins_vpc.id
}
