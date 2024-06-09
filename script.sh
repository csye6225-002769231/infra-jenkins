#!/bin/bash

# Install Nginx
sudo apt update
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
sudo apt-get install certbot python3-certbot-nginx -y
sudo certbot --nginx -d jenkins.kshitijprabhu.me --non-interactive --agree-tos -m kshitij280700@gmail.com

# Reload Nginx to apply the changes
sudo systemctl reload nginx

echo "Jenkins setup is complete. Please open your web browser and navigate to https://jenkins.kshitijprabhu.me to complete the Jenkins setup wizard."

# Wait for Jenkins to start up
sleep 120

# Output the initial Jenkins admin password
echo "Initial Jenkins admin password:"
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
INITIAL_ADMIN_PASSWORD=$(sudo cat /var/lib/jenkins/secrets/initialAdminPassword)

# Download Jenkins CLI
wget http://localhost:8080/jnlpJars/jenkins-cli.jar -O /tmp/jenkins-cli.jar

# Set up the new admin user with username 'admin' and password 'admin'
echo "jenkins.model.Jenkins.instance.securityRealm.createAccount('admin', 'admin')" | java -jar /tmp/jenkins-cli.jar -s http://localhost:8080/ -auth admin:$INITIAL_ADMIN_PASSWORD groovy =

echo "Initial Jenkins admin password is set to 'admin'. Please open your web browser and navigate to https://jenkins.kshitijprabhu.me to complete the Jenkins setup wizard."
