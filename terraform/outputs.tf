# =============================================================================
# OUTPUTS - Informations du déploiement
# =============================================================================
#
# Ces outputs sont optimisés pour un workflow CI/CD :
# - Seules les infos essentielles sont exposées dans les logs
# - La clé SSH est marquée "sensitive" (masquée dans les logs)
# - Récupère les infos localement avec : ./scripts/get-cluster-info.sh
#
# =============================================================================

# -----------------------------------------------------------------------------
# IPS (pour scripts d'automation)
# -----------------------------------------------------------------------------

output "control_plane_public_ip" {
  description = "IP publique du control-plane"
  value       = openstack_networking_floatingip_v2.nodes_ips["control-plane"].address
}

output "worker_public_ip" {
  description = "IP publique du worker"
  value       = openstack_networking_floatingip_v2.nodes_ips["worker"].address
}

output "control_plane_private_ip" {
  description = "IP privée du control-plane (pour kubeadm)"
  value       = local.control_plane_private_ip
}

output "worker_private_ip" {
  description = "IP privée du worker"
  value       = local.worker_private_ip
}

# -----------------------------------------------------------------------------
# CLÉ SSH (récupérable via: terraform output -raw ssh_private_key)
# -----------------------------------------------------------------------------
#
# La clé est stockée dans le tfstate (S3), récupérable même si on perd le repo.
# Utilise le script ./scripts/get-cluster-info.sh pour tout récupérer d'un coup.
# -----------------------------------------------------------------------------

output "ssh_private_key" {
  description = "Clé SSH privée (utilise ./scripts/get-cluster-info.sh pour la récupérer)"
  value       = tls_private_key.ssh.private_key_openssh
  sensitive   = true
}

