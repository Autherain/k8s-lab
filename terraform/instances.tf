# =============================================================================
# INSTANCES - Les VMs du cluster Kubernetes
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Crée 2 VMs : 1 control-plane et 1 worker
# - Configure les IPs (publiques + privées)
# - Injecte la clé SSH (via account SSH keys)
# - Lance un script d'initialisation basique
#
# =============================================================================

# -----------------------------------------------------------------------------
# CLÉ SSH GÉNÉRÉE PAR TERRAFORM
# -----------------------------------------------------------------------------
# 
# On génère la clé SSH directement dans Terraform.
# Avantages :
# - La clé privée est stockée dans le tfstate (dans S3) → récupérable même si on perd le repo
# - Pas besoin de gérer des clés SSH manuellement
# - Compatible avec le backend S3 distant
# -----------------------------------------------------------------------------

resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

# Sauvegarde la clé privée localement avec un nom unique
# Le nom inclut le projet et un suffixe aléatoire pour éviter les collisions
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/.ssh/${local.ssh_key_name}"
  file_permission = "0600"
}

# Enregistre la clé publique dans le compte Scaleway
resource "scaleway_account_ssh_key" "k8s_keypair" {
  name       = "${local.prefix}-keypair"
  public_key = tls_private_key.ssh.public_key_openssh
}

# -----------------------------------------------------------------------------
# CONFIGURATION DES NODES
# -----------------------------------------------------------------------------
# 
# Définition centralisée des nodes du cluster.
# Cela permet d'éviter la répétition et facilite l'ajout de nouveaux nodes.
# -----------------------------------------------------------------------------

locals {
  nodes = {
    control-plane = {
      role        = "control-plane"
      flavor      = var.control_plane_flavor
      private_ip  = local.control_plane_private_ip
      description = "Le control-plane héberge les composants de gestion du cluster : API Server, etcd, Scheduler, Controller Manager"
    }
    worker = {
      role        = "worker"
      flavor      = var.worker_flavor
      private_ip  = local.worker_private_ip
      description = "Le worker exécute les pods applicatifs et reçoit les instructions du control-plane via kubelet"
    }
  }
}

# -----------------------------------------------------------------------------
# INSTANCES (VMs)
# -----------------------------------------------------------------------------
# 
# Crée les instances pour chaque node défini dans local.nodes
# -----------------------------------------------------------------------------

data "scaleway_marketplace_image" "ubuntu" {
  label = var.image_name
  zone  = var.scaleway_zone
}

resource "scaleway_instance_server" "nodes" {
  for_each = local.nodes

  name              = "${local.prefix}-${each.key}"
  type              = each.value.flavor
  image             = data.scaleway_marketplace_image.ubuntu.id
  security_group_id = scaleway_instance_security_group.k8s_secgroup.id
  ip_id             = scaleway_instance_ip.nodes_ips[each.key].id

  # Script d'initialisation (cloud-init)
  user_data = {
    cloud-init = <<-EOF
      #cloud-config
      package_update: true
      package_upgrade: true
      packages:
        - curl
        - wget
        - vim
        - htop
        - net-tools
      runcmd:
        - hostnamectl set-hostname ${local.prefix}-${each.key}
        - touch /var/log/cloud-init-done
    EOF
  }

  depends_on = [scaleway_account_ssh_key.k8s_keypair]

  tags = [
    "project:${var.project_name}",
    "role:${each.value.role}",
    "managed_by:terraform"
  ]
}

# -----------------------------------------------------------------------------
# IPs FLOTTANTES (publiques)
# -----------------------------------------------------------------------------
# 
# Crée une IP publique pour chaque node
# -----------------------------------------------------------------------------

resource "scaleway_instance_ip" "nodes_ips" {
  for_each = local.nodes
}

# -----------------------------------------------------------------------------
# INTERFACES PRIVÉES (IPs fixes)
# -----------------------------------------------------------------------------

resource "scaleway_instance_private_nic" "nodes_private_nic" {
  for_each = local.nodes

  server_id          = scaleway_instance_server.nodes[each.key].id
  private_network_id = scaleway_vpc_private_network.k8s_network.id
  ipam_ip_ids        = [scaleway_ipam_ip.nodes_private_ips[each.key].id]
  zone               = var.scaleway_zone
}

resource "scaleway_ipam_ip" "nodes_private_ips" {
  for_each = local.nodes

  address = each.value.private_ip

  source {
    private_network_id = scaleway_vpc_private_network.k8s_network.id
  }
}

