#!/bin/bash
set -e

# --- Add swap space (2GB) ---
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- Install Docker and Compose ---
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin wireguard-tools

systemctl enable docker
systemctl start docker

# --- Setup WireGuard container ---
mkdir -p /opt/wireguard
cd /opt/wireguard

# Generate keypair if not present
if [ ! -f privatekey ]; then
  wg genkey | tee privatekey | wg pubkey > publickey
fi

PRIVATE_KEY=$(cat privatekey)
ADMIN_USER="admin"
ADMIN_PASS="changeme"

# Get public IP dynamically from metadata service
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "127.0.0.1")

# Download docker-compose.yml (update URL)
curl -fsSLO https://raw.githubusercontent.com/surajkumar/wireguard/main/docker-compose.yml

# Replace secrets dynamically
sed -i "s|WG_WIREGUARD_PRIVATE_KEY=.*|WG_WIREGUARD_PRIVATE_KEY=${PRIVATE_KEY}|g" docker-compose.yml
sed -i "s|WG_ADMIN_USERNAME=.*|WG_ADMIN_USERNAME=${ADMIN_USER}|g" docker-compose.yml
sed -i "s|WG_ADMIN_PASSWORD=.*|WG_ADMIN_PASSWORD=${ADMIN_PASS}|g" docker-compose.yml
sed -i "s|WG_EXTERNAL_HOST=.*|WG_EXTERNAL_HOST=${PUBLIC_IP}|g" docker-compose.yml

# Launch container
docker compose up -d
