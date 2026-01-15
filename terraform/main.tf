# =============================================================================
# FICHIER PRINCIPAL TERRAFORM - Configuration du Provider Scaleway
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Configure Terraform pour utiliser le provider Scaleway
# - Définit le backend S3 compatible (Scaleway Object Storage)
#
# COMMENT ÇA MARCHE :
# 1. Terraform lit ce fichier pour savoir quel "provider" utiliser
# 2. Le provider Scaleway est un plugin qui sait parler à l'API Scaleway
# 3. Les credentials sont lus depuis les variables d'environnement
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.53"
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
  # BACKEND - Stockage distant du tfstate dans Scaleway Object Storage
  # =============================================================================
  #
  # L'état Terraform est stocké dans Scaleway Object Storage (compatible S3).
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
  #   export AWS_SECRET_ACCESS_KEY="ton-secret-key"  # pragma: allowlist secret
  #   terraform init
  #
  # MÉTHODE 2 : Fichier backend.json (format JSON)
  #   terraform init -backend-config=backend.json
  #
  # MÉTHODE 3 : Fichier backend.hcl (format HCL)
  #   terraform init -backend-config=backend.hcl
  #
  # Pour créer les credentials S3 :
  #   1. Scaleway Console > Object Storage > Credentials
  #   2. Crée des credentials (Access Key + Secret Key)
  #
  # =============================================================================

  backend "s3" {
    # Nom du bucket créé dans Scaleway Object Storage
    bucket = "k8s-lab-terraform"

    # Chemin du fichier tfstate dans le bucket
    key = "k8s-lab/terraform.tfstate"

    # Région Scaleway (ex: fr-par, nl-ams, pl-waw)
    region = "fr-par"

    # Endpoint Scaleway Object Storage (syntaxe Terraform 1.6+)
    # pragma: allowlist secret
    endpoints = { s3 = "https://s3.fr-par.scw.cloud" }

    # Options nécessaires pour Scaleway (compatible S3 mais pas AWS)
    # Ces options désactivent les appels aux services AWS (STS, IAM, etc.)
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    skip_metadata_api_check     = true

    # Les credentials sont lus depuis :
    # - Variables d'environnement : AWS_ACCESS_KEY_ID et AWS_SECRET_ACCESS_KEY
    # - Ou fichier backend-config (voir backend.hcl.example)
  }
}

# -----------------------------------------------------------------------------
# PROVIDER SCALEWAY
# -----------------------------------------------------------------------------
#
# Les credentials sont lus depuis les variables d'environnement :
# - SCW_ACCESS_KEY   : Access key Scaleway
# - SCW_SECRET_KEY   : Secret key Scaleway
# - SCW_PROJECT_ID   : Project ID Scaleway
#
# ⚠️ IMPORTANT : La région/zone doit être cohérente avec le backend Object Storage
#    Si ton bucket est en fr-par, garde scaleway_region = "fr-par"
# -----------------------------------------------------------------------------

provider "scaleway" {
  region = var.scaleway_region
  zone   = var.scaleway_zone
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

