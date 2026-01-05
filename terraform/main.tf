# =============================================================================
# FICHIER PRINCIPAL TERRAFORM - Configuration du Provider OVH
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Configure Terraform pour utiliser le provider OVH
# - Récupère les informations de ton projet OVH Public Cloud
#
# COMMENT ÇA MARCHE :
# 1. Terraform lit ce fichier pour savoir quel "provider" utiliser
# 2. Le provider OVH est un plugin qui sait parler à l'API OVH
# 3. Les credentials sont lus depuis les variables d'environnement
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }

  # ⚠️ IMPORTANT : L'état Terraform est stocké localement dans terraform.tfstate
  # Ce fichier contient TOUTES les infos sur tes ressources (IPs, IDs, etc.)
  # NE LE SUPPRIME PAS sinon Terraform ne saura plus ce qu'il a créé !
  # NE LE COMMITE PAS car il peut contenir des infos sensibles.
}

# -----------------------------------------------------------------------------
# PROVIDER OPENSTACK (OVH utilise OpenStack en dessous)
# -----------------------------------------------------------------------------
# 
# Les credentials sont lus depuis les variables d'environnement :
# - OS_AUTH_URL         : URL d'authentification OpenStack (fourni par OVH)
# - OS_TENANT_ID        : ID du projet (= Project ID dans OVH)
# - OS_TENANT_NAME      : Nom du projet
# - OS_USERNAME         : Utilisateur OpenStack (créé dans OVH)
# - OS_PASSWORD         : Mot de passe de l'utilisateur OpenStack
# - OS_REGION_NAME      : Région (GRA11, SBG5, etc.)
#
# Tu récupères tout ça dans : OVH Manager > Public Cloud > Users & Roles
# Puis tu télécharges le fichier "openrc.sh" et tu fais "source openrc.sh"
# -----------------------------------------------------------------------------

provider "openstack" {
  # Pas de configuration ici car tout vient des variables d'environnement
  # C'est plus sécurisé que de mettre les credentials en dur dans le code
}

# -----------------------------------------------------------------------------
# DONNÉES LOCALES (variables calculées)
# -----------------------------------------------------------------------------
# 
# Ces valeurs sont calculées à partir des variables.
# Elles servent à éviter les répétitions et à centraliser la configuration.
# -----------------------------------------------------------------------------

locals {
  # Préfixe pour nommer toutes les ressources
  prefix = var.project_name

  # IPs privées fixes pour les VMs
  # On les fixe pour que kubeadm sache toujours où trouver les autres nodes
  control_plane_private_ip = "10.0.0.10"
  worker_private_ip        = "10.0.0.11"
}

