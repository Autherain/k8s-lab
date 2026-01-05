# =============================================================================
# VARIABLES TERRAFORM - Les paramètres configurables
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Définit toutes les variables que tu peux personnaliser
# - Donne des valeurs par défaut raisonnables
#
# COMMENT ÇA MARCHE :
# 1. Tu copies terraform.tfvars.example vers terraform.tfvars
# 2. Tu modifies les valeurs dans terraform.tfvars
# 3. Terraform lit automatiquement terraform.tfvars
# =============================================================================

# -----------------------------------------------------------------------------
# CONFIGURATION DES VMS
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Préfixe pour nommer les ressources (ex: k8s-lab)"
  type        = string
  default     = "k8s-lab"
}

variable "control_plane_flavor" {
  description = "Type d'instance pour le control-plane"
  type        = string
  default     = "s1-4"

  # Flavors OVH (Public Cloud) :
  # - s1-2  : 1 vCPU, 2 GB RAM   (~3€/mois) - Trop petit pour le control-plane
  # - s1-4  : 2 vCPU, 4 GB RAM   (~6€/mois) - Minimum recommandé
  # - s1-8  : 2 vCPU, 8 GB RAM   (~12€/mois) - Confortable
  # - b2-7  : 2 vCPU, 7 GB RAM   (~15€/mois) - Compute optimized
  #
  # Pour un lab, s1-4 est suffisant pour le control-plane
}

variable "worker_flavor" {
  description = "Type d'instance pour les workers"
  type        = string
  default     = "s1-4"

  # Pour un lab, s1-4 est suffisant pour un worker
  # En production, on met souvent des workers plus gros
}

variable "image_name" {
  description = "Nom de l'image Ubuntu à utiliser"
  type        = string
  default     = "Ubuntu 22.04"

  # Ubuntu 22.04 LTS est la version recommandée pour Kubernetes
  # Elle sera supportée jusqu'en 2027
}

# -----------------------------------------------------------------------------
# CONFIGURATION SSH
# -----------------------------------------------------------------------------

variable "ssh_public_key_path" {
  description = "Chemin vers ta clé SSH publique (ex: ~/.ssh/id_rsa.pub)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"

  # Cette clé sera injectée dans les VMs pour te permettre de te connecter
  # Si tu n'as pas de clé SSH, génère-en une avec : ssh-keygen -t ed25519
}

# -----------------------------------------------------------------------------
# CONFIGURATION RÉSEAU
# -----------------------------------------------------------------------------

variable "private_network_cidr" {
  description = "CIDR du réseau privé (plage d'IPs privées)"
  type        = string
  default     = "10.0.0.0/24"

  # 10.0.0.0/24 = 256 IPs de 10.0.0.0 à 10.0.0.255
  # Suffisant pour un lab avec quelques VMs
  #
  # Attention : ne pas chevaucher avec les CIDRs de Kubernetes :
  # - Pod CIDR par défaut : 10.244.0.0/16 (Flannel) ou 10.0.0.0/8 (Cilium)
  # - Service CIDR par défaut : 10.96.0.0/12
  #
  # On utilise 10.0.0.0/24 qui est différent, pas de souci
}

variable "allowed_ssh_cidr" {
  description = "CIDR autorisé pour SSH (ton IP publique, ou 0.0.0.0/0 pour tout le monde)"
  type        = string
  default     = "0.0.0.0/0"

  # ⚠️ SÉCURITÉ :
  # - 0.0.0.0/0 = tout Internet peut essayer de se connecter en SSH
  # - C'est OK pour un lab car tu as une clé SSH (pas de mot de passe)
  # - En production, tu mettrais ton IP : "1.2.3.4/32"
  #
  # Pour trouver ton IP : curl ifconfig.me
}

