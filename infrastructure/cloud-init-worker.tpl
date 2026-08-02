#!/bin/bash
# Cloud-init script for Kubernetes worker nodes

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io

# Install k3s agent
curl -sfL https://get.k3s.io | K3S_URL=https://${api_lb_ip}:6443 K3S_TOKEN=${cluster_name}-token sh -s - agent \
  --node-name worker-$(hostname) \
  --node-label k8s-role=worker

echo "Worker node initialized successfully"
