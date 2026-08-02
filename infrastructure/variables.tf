variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the domain"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID for R2 storage"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the Civic Commons platform"
  type        = string
  default     = "civiccommons.example.com"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "./kubeconfig"
}

variable "region" {
  description = "Hetzner Cloud region"
  type        = string
  default     = "fsn1" # Falkenstein, Germany (eu-central)
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "civic-commons"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29.0"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "server_type" {
  description = "Hetzner server type for worker nodes"
  type        = string
  default     = "cpx21" # 4 vCPU, 8GB RAM
}

variable "database_node_type" {
  description = "Hetzner server type for database nodes"
  type        = string
  default     = "cpx31" # 8 vCPU, 16GB RAM
}

variable "minio_node_count" {
  description = "Number of MinIO nodes"
  type        = number
  default     = 4
}

variable "minio_drives_per_node" {
  description = "Number of drives per MinIO node"
  type        = number
  default     = 2
}

variable "ssh_public_key" {
  description = "SSH public key for server access"
  type        = string
}

variable "vault_token_initial" {
  description = "Initial Vault root token"
  type        = string
  sensitive   = true
}
