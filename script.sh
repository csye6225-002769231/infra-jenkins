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


# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx

# Configure firewall
sudo ufw allow 'Nginx Full'
sudo ufw allow OpenSSH
sudo ufw --force enable

# Create Nginx server block for Jenkins
cat <<EOF | sudo tee /etc/nginx/sites-available/jenkins
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
EOF

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

# Wait for Jenkins to initialize
sleep 30

# Unlock Jenkins and set the initial password
INITIAL_ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)
JENKINS_CLI_JAR=/tmp/jenkins-cli.jar

# Download Jenkins CLI
wget http://localhost:8080/jnlpJars/jenkins-cli.jar -O $JENKINS_CLI_JAR

# Configure Jenkins user with CLI
echo "jenkins.model.Jenkins.instance.securityRealm.createAccount('admin', 'admin')" | java -jar $JENKINS_CLI_JAR -s http://localhost:8080/ -auth admin:$INITIAL_ADMIN_PASSWORD groovy =

# Output the initial Jenkins admin password
echo "Initial Jenkins admin password is set to 'admin'. Please open your web browser and navigate to https://jenkins.kshitijprabhu.me to complete the Jenkins setup wizard."
