# Consolidated Outputs

# Kubernetes Cluster Outputs
output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = hcloud_load_balancer.k8s_api.ipv4
}

output "cluster_ca_certificate" {
  description = "Kubernetes cluster CA certificate"
  value       = "" # Will be populated by cloud-init script
  sensitive   = true
}

output "cluster_token" {
  description = "Kubernetes authentication token"
  value       = "" # Will be populated by cloud-init script
  sensitive   = true
}

output "control_plane_ip" {
  description = "Control plane node IP"
  value       = hcloud_server.control_plane.ipv4_address
}

output "worker_ips" {
  description = "Worker node IPs"
  value       = hcloud_server.workers[*].ipv4_address
}

# Database Outputs
output "database_ips" {
  description = "Database node IPs"
  value       = hcloud_server.database_nodes[*].ipv4_address
}

output "database_private_network" {
  description = "Database private network ID"
  value       = hcloud_network.database_private.id
}

# MinIO Outputs
output "minio_ips" {
  description = "MinIO node IPs"
  value       = hcloud_server.minio_nodes[*].ipv4_address
}

output "minio_volumes" {
  description = "MinIO volume IDs"
  value       = hcloud_volume.minio_volumes[*].id
}

# Vault Outputs
output "vault_ip" {
  description = "Vault node IP"
  value       = hcloud_server.vault.ipv4_address
}

# Cloudflare Outputs
output "api_endpoint" {
  description = "Cloudflare proxied API endpoint"
  value       = "https://api.${var.domain_name}"
}

output "app_endpoint" {
  description = "Cloudflare proxied application endpoint"
  value       = "https://${var.domain_name}"
}

# Network Outputs
output "public_network_id" {
  description = "Public network ID"
  value       = hcloud_network.public.id
}

output "database_network_id" {
  description = "Database private network ID"
  value       = hcloud_network.database_private.id
}
