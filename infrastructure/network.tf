# VPC Networking Configuration
# Creates private network for database cluster and public network for application servers

# Private Network for Database Cluster
resource "hcloud_network" "database_private" {
  name     = "${var.cluster_name}-db-private"
  ip_range = "10.0.1.0/24"
}

# Public Network for Application Servers
resource "hcloud_network" "public" {
  name     = "${var.cluster_name}-public"
  ip_range = "10.0.0.0/16"
}

# Private Subnet for Database Cluster
resource "hcloud_network_subnet" "database_subnet" {
  network_id   = hcloud_network.database_private.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# Public Subnet for Application Servers
resource "hcloud_network_subnet" "public_subnet" {
  network_id   = hcloud_network.public.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.0.0/24"
}

# SSH Key for Server Access
resource "hcloud_ssh_key" "default" {
  name       = "${var.cluster_name}-ssh-key"
  public_key = var.ssh_public_key
}

# Firewall for Database Nodes (restrictive)
resource "hcloud_firewall" "database" {
  name = "${var.cluster_name}-database-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "5432"
    source_ips = [
      "10.0.0.0/16", # Only allow from internal network
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "10.0.0.0/16", # Kubernetes API server access
    ]
  }

  rule {
    direction = "out"
    protocol  = "tcp"
    port      = "any"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}

# Firewall for Application Servers (public-facing but protected)
resource "hcloud_firewall" "application" {
  name = "${var.cluster_name}-application-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "6443"
    source_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }

  rule {
    direction = "out"
    protocol  = "tcp"
    port      = "any"
    destination_ips = [
      "0.0.0.0/0",
      "::/0"
    ]
  }
}
