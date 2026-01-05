# =============================================================================
# OUTPUTS - Les informations utiles après le déploiement
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Affiche les IPs des VMs après le déploiement
# - Donne les commandes SSH prêtes à l'emploi
# - Fournit les infos nécessaires pour kubeadm
#
# COMMENT VOIR CES INFOS :
# - Après "terraform apply" : affichées automatiquement
# - Plus tard : "terraform output"
# - Une valeur spécifique : "terraform output control_plane_public_ip"
#
# =============================================================================

# -----------------------------------------------------------------------------
# IPS PUBLIQUES (pour te connecter depuis ta machine)
# -----------------------------------------------------------------------------

output "control_plane_public_ip" {
  description = "IP publique du control-plane (pour SSH et kubectl)"
  value       = openstack_networking_floatingip_v2.control_plane_ip.address
}

output "worker_public_ip" {
  description = "IP publique du worker (pour SSH)"
  value       = openstack_networking_floatingip_v2.worker_ip.address
}

# -----------------------------------------------------------------------------
# IPS PRIVÉES (pour la configuration Kubernetes)
# -----------------------------------------------------------------------------

output "control_plane_private_ip" {
  description = "IP privée du control-plane (pour kubeadm)"
  value       = local.control_plane_private_ip
}

output "worker_private_ip" {
  description = "IP privée du worker"
  value       = local.worker_private_ip
}

# -----------------------------------------------------------------------------
# COMMANDES SSH
# -----------------------------------------------------------------------------

output "ssh_control_plane" {
  description = "Commande pour se connecter au control-plane"
  value       = "ssh ubuntu@${openstack_networking_floatingip_v2.control_plane_ip.address}"
}

output "ssh_worker" {
  description = "Commande pour se connecter au worker"
  value       = "ssh ubuntu@${openstack_networking_floatingip_v2.worker_ip.address}"
}

# -----------------------------------------------------------------------------
# INFOS KUBERNETES
# -----------------------------------------------------------------------------

output "kubeadm_init_command" {
  description = "Commande kubeadm init à exécuter sur le control-plane"
  value       = <<-EOF

    # À exécuter sur le control-plane après avoir installé kubeadm :
    sudo kubeadm init \
      --apiserver-advertise-address=${local.control_plane_private_ip} \
      --apiserver-cert-extra-sans=${openstack_networking_floatingip_v2.control_plane_ip.address} \
      --pod-network-cidr=10.244.0.0/16 \
      --node-name=${local.prefix}-control-plane

    # Explications :
    # --apiserver-advertise-address : IP privée pour la communication interne
    # --apiserver-cert-extra-sans   : IP publique dans le certificat (pour kubectl depuis ta machine)
    # --pod-network-cidr            : Plage d'IPs pour les pods (compatible Cilium)
    # --node-name                   : Nom du node dans Kubernetes

  EOF
}

# -----------------------------------------------------------------------------
# RÉSUMÉ
# -----------------------------------------------------------------------------

output "summary" {
  description = "Résumé du déploiement"
  value       = <<-EOF

    ╔══════════════════════════════════════════════════════════════════╗
    ║                    CLUSTER K8S-LAB DÉPLOYÉ                       ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║                                                                  ║
    ║  CONTROL-PLANE:                                                  ║
    ║    IP Publique : ${openstack_networking_floatingip_v2.control_plane_ip.address}
    ║    IP Privée   : ${local.control_plane_private_ip}
    ║    SSH         : ssh ubuntu@${openstack_networking_floatingip_v2.control_plane_ip.address}
    ║                                                                  ║
    ║  WORKER:                                                         ║
    ║    IP Publique : ${openstack_networking_floatingip_v2.worker_ip.address}
    ║    IP Privée   : ${local.worker_private_ip}
    ║    SSH         : ssh ubuntu@${openstack_networking_floatingip_v2.worker_ip.address}
    ║                                                                  ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  PROCHAINES ÉTAPES :                                             ║
    ║  1. Attends 2-3 minutes que les VMs démarrent                    ║
    ║  2. Connecte-toi en SSH au control-plane                         ║
    ║  3. Lance le script d'installation kubeadm                       ║
    ╚══════════════════════════════════════════════════════════════════╝

  EOF
}

