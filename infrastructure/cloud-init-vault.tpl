#!/bin/bash
# Cloud-init script for HashiCorp Vault

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget gnupg2 software-properties-common

# Add HashiCorp GPG key and repository
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

# Install Vault
apt-get update && apt-get install -y vault

# Configure Vault
cat > /etc/vault.d/vault.hcl <<EOF
listener "tcp" {
  address = "10.0.1.20:8200"
  tls_disable = true
}

storage "file" {
  path = "/opt/vault/data"
}

api_addr = "http://10.0.1.20:8200"
cluster_addr = "https://10.0.1.20:8201"
ui = true
EOF

# Create Vault data directory
mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault/data

# Enable and start Vault
systemctl enable vault
systemctl start vault

# Initialize Vault with initial token
export VAULT_ADDR="http://127.0.0.1:8200"
vault operator init -key-shares=1 -key-threshold=1 > /root/vault-init.txt

# Unseal Vault
UNSEAL_KEY=$(grep "Unseal Key" /root/vault-init.txt | awk '{print $4}')
vault operator unseal $UNSEAL_KEY

# Set initial root token
echo ${vault_token} > /root/vault-token.txt
vault login token=${vault_token}

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Enable transit secrets engine for encryption
vault secrets enable transit

# Create policy for Civic Commons
vault policy write civic-commons - <<EOF
path "secret/data/civic-commons/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "transit/encrypt/*" {
  capabilities = ["create", "update"]
}
path "transit/decrypt/*" {
  capabilities = ["create", "update"]
}
EOF

echo "Vault initialized successfully"
