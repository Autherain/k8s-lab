# =============================================================================
# RÉSEAU - Configuration du réseau privé Scaleway
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Crée un VPC et un Private Network (réseau privé)
# - Configure le security group (firewall)
# - Ouvre SSH, API Kubernetes, NodePort, ICMP et le trafic interne
# =============================================================================

# -----------------------------------------------------------------------------
# VPC + PRIVATE NETWORK
# -----------------------------------------------------------------------------
# Le Private Network relie les VMs entre elles sur une plage d'IPs privées.
# Chaque VM gardera une IP privée fixe (utile pour kubeadm).
# -----------------------------------------------------------------------------

resource "scaleway_vpc" "k8s_vpc" {
  name   = "${local.prefix}-vpc"
  region = var.scaleway_region
}

resource "scaleway_vpc_private_network" "k8s_network" {
  name   = "${local.prefix}-pn"
  vpc_id = scaleway_vpc.k8s_vpc.id
  region = var.scaleway_region

  ipv4_subnet {
    subnet = var.private_network_cidr
  }
}

# -----------------------------------------------------------------------------
# SECURITY GROUP (FIREWALL)
# -----------------------------------------------------------------------------
# Par défaut, on bloque l'entrant et on autorise le sortant.
# -----------------------------------------------------------------------------

resource "scaleway_instance_security_group" "k8s_secgroup" {
  name                    = "${local.prefix}-secgroup"
  description             = "Security group pour le cluster Kubernetes"
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  stateful                = true
}

resource "scaleway_instance_security_group_rules" "k8s_rules" {
  security_group_id = scaleway_instance_security_group.k8s_secgroup.id

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
    ip_range = var.allowed_ssh_cidr
  }

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 6443
    ip_range = var.allowed_ssh_cidr
  }

  inbound_rule {
    action   = "accept"
    protocol = "ANY"
    ip_range = var.private_network_cidr
  }

  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }

  inbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "30000-32767"
    ip_range   = "0.0.0.0/0"
  }
}
