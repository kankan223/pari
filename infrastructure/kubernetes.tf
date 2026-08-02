# Kubernetes Cluster Configuration
# Creates Hetzner Kubernetes cluster using k3s or similar lightweight distribution

# Load Balancer for Kubernetes API Server
resource "hcloud_load_balancer" "k8s_api" {
  name               = "${var.cluster_name}-api-lb"
  load_balancer_type = "lb11"
  location           = var.region
  network_zone       = "eu-central"
}

# Load Balancer Target for API Server
resource "hcloud_load_balancer_target" "k8s_api_targets" {
  type             = "label_selector"
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  label_selector   = "k8s-role=control-plane"
  use_private_ip   = false
}

# Load Balancer Service for API Server
resource "hcloud_load_balancer_service" "k8s_api_service" {
  load_balancer_id = hcloud_load_balancer.k8s_api.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 10
    timeout  = 5
    retries  = 3
  }
}

# Control Plane Node
resource "hcloud_server" "control_plane" {
  name         = "${var.cluster_name}-control-plane"
  server_type  = var.server_type
  image        = "ubuntu-22.04"
  location     = var.region
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.application.id]

  network {
    network_id = hcloud_network.public.id
    ip         = "10.0.0.10"
  }

  user_data = templatefile("${path.module}/cloud-init-control-plane.tpl", {
    cluster_name    = var.cluster_name
    kubernetes_version = var.kubernetes_version
    api_lb_ip       = hcloud_load_balancer.k8s_api.ipv4
  })

  labels = {
    k8s-role = "control-plane"
  }
}

# Worker Nodes
resource "hcloud_server" "workers" {
  count = var.node_count

  name         = "${var.cluster_name}-worker-${count.index}"
  server_type  = var.server_type
  image        = "ubuntu-22.04"
  location     = var.region
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.application.id]

  network {
    network_id = hcloud_network.public.id
  }

  user_data = templatefile("${path.module}/cloud-init-worker.tpl", {
    cluster_name    = var.cluster_name
    kubernetes_version = var.kubernetes_version
    api_lb_ip       = hcloud_load_balancer.k8s_api.ipv4
  })

  labels = {
    k8s-role = "worker"
  }
}

# Database Nodes (PostgreSQL cluster)
resource "hcloud_server" "database_nodes" {
  count = 3

  name         = "${var.cluster_name}-db-${count.index}"
  server_type  = var.database_node_type
  image        = "ubuntu-22.04"
  location     = var.region
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.database.id]

  network {
    network_id = hcloud_network.database_private.id
    ip         = "10.0.1.${10 + count.index}"
  }

  user_data = templatefile("${path.module}/cloud-init-db.tpl", {
    node_index = count.index
  })

  labels = {
    role = "database"
  }
}

# MinIO Storage Nodes
resource "hcloud_server" "minio_nodes" {
  count = var.minio_node_count

  name         = "${var.cluster_name}-minio-${count.index}"
  server_type  = var.server_type
  image        = "ubuntu-22.04"
  location     = var.region
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.application.id]

  network {
    network_id = hcloud_network.public.id
  }

  user_data = templatefile("${path.module}/cloud-init-minio.tpl", {
    node_index = count.index
    drives_count = var.minio_drives_per_node
  })

  labels = {
    role = "minio"
  }
}

# Additional volumes for MinIO nodes
resource "hcloud_volume" "minio_volumes" {
  count = var.minio_node_count * var.minio_drives_per_node

  name     = "${var.cluster_name}-minio-vol-${count.index}"
  size     = 100 # 100GB per drive
  server_id = hcloud_server.minio_nodes[floor(count.index / var.minio_drives_per_node)].id
  automount = false
}

# HashiCorp Vault Node
resource "hcloud_server" "vault" {
  name         = "${var.cluster_name}-vault"
  server_type  = "cpx11" # 2 vCPU, 2GB RAM
  image        = "ubuntu-22.04"
  location     = var.region
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.database.id]

  network {
    network_id = hcloud_network.database_private.id
    ip         = "10.0.1.20"
  }

  user_data = templatefile("${path.module}/cloud-init-vault.tpl", {
    vault_token = var.vault_token_initial
  })

  labels = {
    role = "vault"
  }
}

