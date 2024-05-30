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

# Launch an EC2 instance with the Jenkins AMI
resource "aws_instance" "jenkins_instance" {
  ami                         = data.aws_ami.jenkins_ami.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_subnet.id
  vpc_security_group_ids      = [aws_security_group.security_group.id]
  associate_public_ip_address = true
  key_name                    = "csye7125"

  # User data script to set up Jenkins
  user_data = <<-EOF
    #!/bin/bash

    # Update and upgrade the system
    sudo apt update && sudo apt upgrade -y

    # Install Java
    sudo apt install openjdk-11-jdk -y

    # Add Jenkins repository and install Jenkins
    wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
    sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
    sudo apt update
    sudo apt install jenkins -y

    # Start and enable Jenkins
    sudo systemctl start jenkins
    sudo systemctl enable jenkins

    # Install Nginx
    sudo apt install nginx -y

    # Start and enable Nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx

    # Configure firewall
    sudo ufw allow 'Nginx Full'
    sudo ufw allow OpenSSH
    sudo ufw --force enable

    # Create Nginx server block for Jenkins
    cat <<EOL | sudo tee /etc/nginx/sites-available/jenkins
    server {
        listen 80;
        server_name jenkins.kshitijprabhu.me;

        location / {
            proxy_pass http://localhost:8080;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Connection "";
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_request_buffering off;
            client_max_body_size 0;
            chunked_transfer_encoding on;
        }
    }
    EOL

    # Enable the new Nginx configuration
    sudo ln -s /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/

    # Test Nginx configuration
    sudo nginx -t

    # Reload Nginx
    sudo systemctl reload nginx

    # Obtain an SSL certificate
    sudo certbot --nginx -d jenkins.kshitijprabhu.me --non-interactive --agree-tos -m kshitij280700@gmail.com

    # Reload Nginx to apply the changes
    sudo systemctl reload nginx

    echo "Jenkins setup is complete. Please open your web browser and navigate to https://jenkins.kshitijprabhu.me to complete the Jenkins setup wizard."

    # Output the initial Jenkins admin password
    echo "Initial Jenkins admin password:"
    sudo cat /var/lib/jenkins/secrets/initialAdminPassword
    INITIAL_ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

    # Download Jenkins CLI
    wget http://localhost:8080/jnlpJars/jenkins-cli.jar -O /tmp/jenkins-cli.jar

    # Set up the new admin user with username 'admin' and password 'admin'
    echo "jenkins.model.Jenkins.instance.securityRealm.createAccount('admin', 'admin')" | java -jar /tmp/jenkins-cli.jar -s http://localhost:8080/ -auth admin:$INITIAL_ADMIN_PASSWORD groovy =

    # Optional: Disable the initial admin user setup
    # This step will require that you enable security and create a new admin user, which can be tricky to automate fully.
    # You can skip this step if you want to retain the initial admin user.
    #echo "jenkins.model.Jenkins.instance.securityRealm.createAccount('newadmin', 'newpassword')" | java -jar /tmp/jenkins-cli.jar -s http://localhost:8080/ -auth admin:admin groovy =

    # Output the initial Jenkins admin password
    echo "Initial Jenkins admin password is set to 'admin'. Please open your web browser and navigate to https://jenkins.kshitijprabhu.me to complete the Jenkins setup wizard."

    # Clean up
    rm /tmp/jenkins-cli.jar
  EOF

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
