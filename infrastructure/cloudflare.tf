# Cloudflare CDN and DDoS Protection Configuration

# DNS Record for API Server
resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api"
  value   = hcloud_load_balancer.k8s_api.ipv4
  type    = "A"
  ttl     = 300
  proxied = true
}

# DNS Record for Application
resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  value   = hcloud_load_balancer.k8s_api.ipv4
  type    = "A"
  ttl     = 300
  proxied = true
}

# DNS Record for Vault (internal only, not proxied)
resource "cloudflare_record" "vault" {
  zone_id = var.cloudflare_zone_id
  name    = "vault"
  value   = "10.0.1.20" # Use static IP from private network
  type    = "A"
  ttl     = 300
  proxied = false
}

# DNS Record for Control Plane (internal)
resource "cloudflare_record" "control_plane" {
  zone_id = var.cloudflare_zone_id
  name    = "k8s-control"
  value   = hcloud_server.control_plane.ipv4_address
  type    = "A"
  ttl     = 300
  proxied = false
}

# Cloudflare R2 for Object Storage (optional, can be used alongside MinIO)
resource "cloudflare_r2_bucket" "civic_commons" {
  account_id = var.cloudflare_account_id
  name       = "${var.cluster_name}-storage"
  location   = "WEUR" # Western Europe
}
