# Hetzner Cloud Provider
provider "hcloud" {
  token = var.hcloud_token
}

# Cloudflare Provider
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Kubernetes Provider (configured after cluster creation)
provider "kubernetes" {
  config_path = var.kubeconfig_path
  host                   = module.kubernetes.cluster_endpoint
  cluster_ca_certificate = base64decode(module.kubernetes.cluster_ca_certificate)
  token                  = module.kubernetes.cluster_token
}

# Helm Provider
provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
    host                   = module.kubernetes.cluster_endpoint
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_ca_certificate)
    token                  = module.kubernetes.cluster_token
  }
}
