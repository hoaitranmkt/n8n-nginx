#!/bin/bash

# Kiểm tra xem script có được chạy với quyền root không
if [[ $EUID -ne 0 ]]; then
   echo "This script needs to be run with root privileges" 
   exit 1
fi

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0  # Domain đã trỏ đúng
    else
        return 1  # Domain chưa trỏ đúng
    fi
}

# Nhận input domain từ người dùng
read -p "Enter your main domain or subdomain for n8n: " N8N_DOMAIN
read -p "Enter your subdomain for Portainer: " PORTAINER_DOMAIN

# Kiểm tra domain
if check_domain $N8N_DOMAIN && check_domain $PORTAINER_DOMAIN; then
    echo "Domains are correctly pointed to this server. Continuing installation."
else
    echo "One or more domains have not been pointed to this server."
    echo "Please update your DNS records to point the domains to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again."
    exit 1
fi

# Thư mục cấu hình
N8N_DIR="/home/n8n"
PORTAINER_DIR="/home/portainer"

# Cài đặt Docker, Docker Compose và Nginx
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common nginx ufw
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Mở cổng trên tường lửa
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 5678/tcp
ufw reload

# Cài đặt Portainer
docker volume create portainer_data
docker run -d -p 9443:9443 --name portainer \
    --restart always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest

# Tạo file docker-compose.yml cho n8n
mkdir -p $N8N_DIR
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${N8N_DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - $N8N_DIR:/home/node/.n8n
EOF

# Cấu hình Nginx cho n8n
NGINX_CONF_N8N="/etc/nginx/sites-available/n8n"
NGINX_CONF_PORTAINER="/etc/nginx/sites-available/portainer"
NGINX_LINK_N8N="/etc/nginx/sites-enabled/n8n"
NGINX_LINK_PORTAINER="/etc/nginx/sites-enabled/portainer"

cat << EOF > $NGINX_CONF_N8N
server {
    listen 80;
    server_name ${N8N_DOMAIN};

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

cat << EOF > $NGINX_CONF_PORTAINER
server {
    listen 80;
    server_name ${PORTAINER_DOMAIN};

    location / {
        proxy_pass https://localhost:9443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# Kích hoạt cấu hình Nginx
ln -s $NGINX_CONF_N8N $NGINX_LINK_N8N
ln -s $NGINX_CONF_PORTAINER $NGINX_LINK_PORTAINER
systemctl restart nginx

# Cài đặt Let's Encrypt SSL cho cả hai domain
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d $N8N_DOMAIN -d $PORTAINER_DOMAIN --non-interactive --agree-tos -m admin@$N8N_DOMAIN

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động container n8n
cd $N8N_DIR
docker-compose up -d

# Thông báo hoàn tất
echo "N8n và Portainer đã được cài đặt và cấu hình với Nginx."
echo "Truy cập n8n tại: https://${N8N_DOMAIN}"
echo "Truy cập Portainer tại: https://${PORTAINER_DOMAIN}"
