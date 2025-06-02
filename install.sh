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
read -p "Enter your domain or subdomain: " DOMAIN

# Kiểm tra domain
if check_domain $DOMAIN; then
    echo "Domain $DOMAIN has been correctly pointed to this server. Continuing installation"
else
    echo "Domain $DOMAIN has not been pointed to this server."
    echo "Please update your DNS record to point $DOMAIN to IP $(curl -s https://api.ipify.org)"
    echo "After updating the DNS, run this script again"
    exit 1
fi

# Sử dụng thư mục /home trực tiếp
N8N_DIR="/home/n8n"

# Cài đặt Docker, Docker Compose và Nginx
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common nginx
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

# Tạo thư mục cho n8n
mkdir -p $N8N_DIR

# Tạo file docker-compose.yml
cat << EOF > $N8N_DIR/docker-compose.yml
version: "3"
services:
  n8n:
    image: n8nio/n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - $N8N_DIR:/home/node/.n8n
EOF

# Cấu hình Nginx
NGINX_CONF="/etc/nginx/sites-available/n8n"
NGINX_LINK="/etc/nginx/sites-enabled/n8n"
cat << EOF > $NGINX_CONF
server {
    listen 80;
    server_name ${DOMAIN};

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

# Kích hoạt cấu hình Nginx
ln -s $NGINX_CONF $NGINX_LINK
systemctl restart nginx

# Đặt quyền cho thư mục n8n
chown -R 1000:1000 $N8N_DIR
chmod -R 755 $N8N_DIR

# Khởi động container n8n
cd $N8N_DIR
docker-compose up -d

# Thêm alias để cập nhật nhanh n8n
echo "alias update-n8n='cd $N8N_DIR && docker-compose down && docker-compose pull && docker-compose up -d'" >> ~/.bashrc
source ~/.bashrc

echo "N8n đã được cài đặt và cấu hình với Nginx. Truy cập http://${DOMAIN} để sử dụng."
echo "Các file cấu hình và dữ liệu được lưu trong $N8N_DIR"
echo "Alias 'update-n8n' đã được thêm. Sử dụng lệnh 'update-n8n' để cập nhật n8n lên phiên bản mới nhất."
