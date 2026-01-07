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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  # =============================================================================
  # BACKEND - Stockage distant du tfstate dans OVH Object Storage
  # =============================================================================
  #
  # L'état Terraform est maintenant stocké dans OVH Object Storage (compatible S3).
  # Avantages :
  # - Partageable entre plusieurs machines/équipes
  # - Sauvegarde automatique avec versioning
  # - Verrouillage (state locking) pour éviter les conflits
  #
  # ⚠️ IMPORTANT : Les credentials (access_key/secret_key) ne doivent PAS être
  #    dans ce fichier. Utilise une des méthodes suivantes :
  #
  # MÉTHODE 1 : Variables d'environnement (recommandé)
  #   export AWS_ACCESS_KEY_ID="ton-access-key"
  #   export AWS_SECRET_ACCESS_KEY="ton-secret-key"
  #   terraform init
  #
  # MÉTHODE 2 : Fichier backend.json (format JSON, pratique si OVH te donne du JSON)
  #   terraform init -backend-config=backend.json
  #
  # MÉTHODE 3 : Fichier backend.hcl (format HCL)
  #   terraform init -backend-config=backend.hcl
  #
  # Pour créer les credentials S3 :
  #   1. OVH Manager > Public Cloud > Users & Roles
  #   2. Crée un utilisateur avec rôle "Object Storage Operator"
  #   3. Télécharge les credentials (Access Key + Secret Key)
  #
  # =============================================================================

  backend "s3" {
    # Endpoint OVH Object Storage (région Roubaix)
    # Note: endpoints.s3 est la nouvelle syntaxe, mais on garde endpoint pour compatibilité
    endpoint = "https://s3.rbx.io.cloud.ovh.net"

    # Nom du bucket créé dans OVH Object Storage
    bucket = "k8s-lab-terraform"

    # Chemin du fichier tfstate dans le bucket
    key = "k8s-lab/terraform.tfstate"

    # Région : valeur factice requise par Terraform (ignorée car on force l'endpoint OVH)
    # 
    # ⚠️ EXPLICATION : Le paramètre "region" est OBLIGATOIRE dans Terraform, même si on utilise
    #    un endpoint personnalisé. On met une région AWS valide (n'importe laquelle) car :
    # - On force l'endpoint OVH avec "endpoint = ..." (ligne 59) → cette valeur est utilisée
    # - On a "skip_region_validation = true" (ligne 82) → la région n'est pas validée
    # → La valeur de "region" ci-dessous est donc ignorée, c'est juste pour que Terraform accepte la config
    region = "us-east-1"

    # Options nécessaires pour OVH (compatible S3 mais pas AWS)
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true

    # Les credentials sont lus depuis :
    # - Variables d'environnement : AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY
    # - Ou fichier backend-config (voir backend.hcl.example)
  }
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
#
# ⚠️ IMPORTANT : La région est configurée directement ici (RBX1 = Roubaix)
#    Elle doit correspondre à la région du backend Object Storage (rbx)
#    Si RBX1 n'est pas disponible dans ton projet, change pour RBX2
#
# Tu récupères les credentials dans : OVH Manager > Public Cloud > Users & Roles
# Puis tu télécharges le fichier "openrc.sh" et tu fais "source openrc.sh"
# -----------------------------------------------------------------------------

provider "openstack" {
  # Région OpenStack (RBX1 = Roubaix, correspond au backend Object Storage)
  # Si RBX1 n'est pas disponible dans ton projet, change pour RBX2
  region = "RBX1"

  # Les autres paramètres (auth_url, tenant_id, username, password) sont lus
  # depuis les variables d'environnement (plus sécurisé que de les mettre en dur)
}

# -----------------------------------------------------------------------------
# DONNÉES LOCALES (variables calculées)
# -----------------------------------------------------------------------------
# 
# Ces valeurs sont calculées à partir des variables.
# Elles servent à éviter les répétitions et à centraliser la configuration.
# -----------------------------------------------------------------------------

# Suffixe unique pour éviter les conflits de noms de clés
# ⚠️ IMPORTANT : Pas de keeper ici ! Le suffixe doit rester stable même si on change project_name
# Sinon, on régénère une nouvelle clé et on ne peut plus se connecter aux VMs existantes
resource "random_id" "key_suffix" {
  byte_length = 4
}

locals {
  # Préfixe pour nommer toutes les ressources
  prefix = var.project_name

  # Nom unique pour la clé SSH (basé sur le projet + suffixe aléatoire)
  # Exemple: k8s-lab_3f2a1b4c
  # Le suffixe reste stable (pas de keeper) pour pouvoir se connecter même si project_name change
  ssh_key_name = "${var.project_name}_${random_id.key_suffix.hex}"

  # IPs privées fixes pour les VMs
  # On les fixe pour que kubeadm sache toujours où trouver les autres nodes
  control_plane_private_ip = "10.0.0.10"
  worker_private_ip        = "10.0.0.11"
}

