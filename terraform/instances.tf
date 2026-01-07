# =============================================================================
# INSTANCES - Les VMs du cluster Kubernetes
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Crée 2 VMs : 1 control-plane et 1 worker
# - Configure les IPs (publiques + privées)
# - Injecte la clé SSH
# - Lance un script d'initialisation basique
#
# =============================================================================

# -----------------------------------------------------------------------------
# CLÉ SSH
# -----------------------------------------------------------------------------
# 
# On importe ta clé SSH publique dans OpenStack.
# Elle sera injectée dans les VMs pour te permettre de te connecter.
# -----------------------------------------------------------------------------

resource "openstack_compute_keypair_v2" "k8s_keypair" {
  name       = "${local.prefix}-keypair"
  public_key = file(pathexpand(var.ssh_public_key_path))
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

resource "openstack_compute_instance_v2" "nodes" {
  for_each = local.nodes

  name            = "${local.prefix}-${each.key}"
  flavor_name     = each.value.flavor
  image_name      = var.image_name
  key_pair        = openstack_compute_keypair_v2.k8s_keypair.name
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  # Réseau privé avec IP fixe
  network {
    uuid        = openstack_networking_network_v2.k8s_network.id
    fixed_ip_v4 = each.value.private_ip
  }

  # Script d'initialisation (user-data)
  # Ce script est exécuté au premier démarrage de la VM
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Met à jour le système
    apt-get update
    apt-get upgrade -y

    # Installe des outils utiles
    apt-get install -y curl wget vim htop net-tools

    # Configure le hostname
    hostnamectl set-hostname ${local.prefix}-${each.key}

    # Crée un fichier pour indiquer que l'init est terminée
    touch /var/log/cloud-init-done
  EOF

  # Attend que le réseau soit prêt avant de créer l'instance
  depends_on = [
    openstack_networking_router_interface_v2.k8s_router_interface
  ]

  # Métadonnées pour identifier la VM
  metadata = {
    role       = each.value.role
    project    = var.project_name
    managed_by = "terraform"
  }
}

# -----------------------------------------------------------------------------
# IPs FLOTTANTES (publiques)
# -----------------------------------------------------------------------------
# 
# Crée une IP publique pour chaque node
# -----------------------------------------------------------------------------

resource "openstack_networking_floatingip_v2" "nodes_ips" {
  for_each = local.nodes
  pool     = "Ext-Net" # Pool d'IPs publiques chez OVH
}

# -----------------------------------------------------------------------------
# ASSOCIATION DES IPs FLOTTANTES
# -----------------------------------------------------------------------------
# 
# Associe chaque IP flottante à son instance correspondante
# -----------------------------------------------------------------------------

resource "openstack_compute_floatingip_associate_v2" "nodes_ips_assoc" {
  for_each    = local.nodes
  floating_ip = openstack_networking_floatingip_v2.nodes_ips[each.key].address
  instance_id = openstack_compute_instance_v2.nodes[each.key].id
}

