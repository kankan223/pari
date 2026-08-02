#!/bin/bash
# Cloud-init script for Kubernetes control plane node

set -e

# Update system
apt-get update && apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io

# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | K3S_KUBECONFIG_MODE="644" sh -s - server \
  --tls-san ${api_lb_ip} \
  --tls-san ${cluster_name}.local \
  --node-name control-plane \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644

# Wait for k3s to be ready
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  echo "Waiting for k3s to initialize..."
  sleep 5
done

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install ArgoCD
kubectl create namespace argocd --kubeconfig /etc/rancher/k3s/k3s.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --kubeconfig /etc/rancher/k3s/k3s.yaml

# Get kubeconfig and make it available
cp /etc/rancher/k3s/k3s.yaml /root/kubeconfig
chown root:root /root/kubeconfig
chmod 600 /root/kubeconfig

echo "Control plane node initialized successfully"
