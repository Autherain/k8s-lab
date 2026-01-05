# =============================================================================
# RÉSEAU - Configuration du réseau privé OpenStack
# =============================================================================
#
# CE QUE FAIT CE FICHIER :
# - Crée un réseau privé pour la communication entre les VMs
# - Crée un sous-réseau avec des IPs privées
# - Crée un routeur pour connecter le réseau privé à Internet
# - Configure les règles de firewall (security groups)
#
# =============================================================================
# 📚 CONCEPTS DE BASE - Si tu es perdu, lis ça d'abord !
# =============================================================================
#
# 1. ADRESSE IP (Internet Protocol)
#    ───────────────────────────────
#    Une adresse IP est comme l'adresse postale d'un ordinateur.
#    Exemple : 10.0.0.10
#    - Chaque VM a une adresse IP unique sur le réseau
#    - Il y a deux types d'IPs :
#      * IP privée : 10.0.0.10 (visible uniquement dans ton réseau privé)
#      * IP publique : 185.123.45.67 (visible depuis Internet)
#
# 2. CIDR (Classless Inter-Domain Routing)
#    ──────────────────────────────────────
#    C'est une notation pour définir une PLAGE d'adresses IP.
#    Format : X.X.X.X/Y
#    Exemple : 10.0.0.0/24
#    - 10.0.0.0 = l'adresse de base du réseau
#    - /24 = les 24 premiers bits sont fixes (le réseau)
#    - Résultat : 256 IPs possibles (10.0.0.0 à 10.0.0.255)
#    
#    Autres exemples :
#    - 10.0.0.0/16 = 65,536 IPs (10.0.0.0 à 10.0.255.255)
#    - 192.168.1.0/24 = 256 IPs (192.168.1.0 à 192.168.1.255)
#    - 0.0.0.0/0 = TOUTES les IPs d'Internet (utilisé pour "tout le monde")
#
# 3. DHCP (Dynamic Host Configuration Protocol)
#    ───────────────────────────────────────────
#    C'est un service qui attribue AUTOMATIQUEMENT une IP à une VM quand elle démarre.
#    Comme un serveur qui dit : "Tu es nouveau ? Voici ton IP : 10.0.0.100"
#    - enable_dhcp = true : Active le DHCP
#    - allocation_pool : Définit la plage d'IPs que le DHCP peut donner
#      Exemple : start = "10.0.0.100", end = "10.0.0.200"
#      → Le DHCP peut donner les IPs de 10.0.0.100 à 10.0.0.200
#      → Les autres IPs (10.0.0.1-99, 10.0.0.201-255) sont réservées
#
# 4. DNS (Domain Name System)
#    ─────────────────────────
#    C'est le service qui traduit les noms de domaines en IPs.
#    Exemple : Quand tu tapes "google.com", le DNS te dit "c'est 142.250.185.14"
#    - dns_nameservers = ["8.8.8.8", "8.8.4.4"] : Utilise les serveurs DNS de Google
#    - 8.8.8.8 et 8.8.4.4 sont les DNS publics de Google (gratuits et rapides)
#
# 5. ROUTEUR
#    ────────
#    C'est comme un "pont" entre deux réseaux.
#    Dans ton cas : il connecte ton réseau privé (10.0.0.0/24) à Internet.
#    - Sans routeur : Tes VMs peuvent se parler entre elles, mais pas accéder à Internet
#    - Avec routeur : Tes VMs peuvent se parler ET accéder à Internet
#    - external_network_id : Le réseau "Ext-Net" = Internet (fourni par OVH)
#
# 6. SECURITY GROUP (Groupe de sécurité / Firewall)
#    ───────────────────────────────────────────────
#    C'est comme un garde de sécurité qui contrôle qui peut entrer/sortir.
#    Par défaut : TOUT EST BLOQUÉ (sécurité maximale)
#    Tu dois créer des règles pour autoriser le trafic.
#
# 7. RÈGLES DE FIREWALL - Les paramètres importants :
#    ─────────────────────────────────────────────────
#    
#    direction = "ingress" ou "egress"
#    ──────────────────────────────────
#    - ingress = TRAFIC ENTRANT (quelqu'un essaie de se connecter à ta VM)
#      Exemple : Tu te connectes en SSH depuis ton PC vers la VM
#    - egress = TRAFIC SORTANT (ta VM essaie de se connecter ailleurs)
#      Exemple : Ta VM télécharge un package depuis Internet
#    
#    remote_ip_prefix = "X.X.X.X/Y"
#    ────────────────────────────────
#    C'est l'adresse IP (ou la plage d'IPs) de CELUI QUI INITIE LA CONNEXION.
#    Exemples :
#    - "0.0.0.0/0" = N'IMPORTE QUI sur Internet peut se connecter
#    - "192.168.1.100/32" = Seulement l'IP 192.168.1.100 peut se connecter
#    - "10.0.0.0/24" = N'importe quelle IP entre 10.0.0.0 et 10.0.0.255
#    
#    Dans le contexte d'une règle ingress :
#    - remote_ip_prefix = l'IP de CELUI QUI SE CONNECTE (ton PC, un autre serveur, etc.)
#    - security_group_id = le firewall de la VM QUI REÇOIT la connexion
#    
#    protocol = "tcp", "udp", ou "icmp"
#    ───────────────────────────────────
#    - tcp = Transmission Control Protocol (connexions fiables, comme HTTP, SSH)
#    - udp = User Datagram Protocol (connexions rapides mais moins fiables, comme DNS)
#    - icmp = Internet Control Message Protocol (ping, utilisé pour tester la connectivité)
#    
#    port_range_min / port_range_max
#    ────────────────────────────────
#    Les ports sont comme des "portes" sur une VM.
#    Chaque service écoute sur un port spécifique :
#    - Port 22 = SSH (connexion à distance)
#    - Port 80 = HTTP (web)
#    - Port 443 = HTTPS (web sécurisé)
#    - Port 6443 = API Kubernetes
#    - Ports 30000-32767 = NodePort Kubernetes (services exposés)
#    
#    remote_group_id
#    ────────────────
#    Au lieu de spécifier une IP, tu peux dire "toutes les VMs qui ont ce security group".
#    Exemple : Si tu mets le même security_group_id dans remote_group_id,
#              toutes les VMs avec ce security group peuvent se parler entre elles.
#
# =============================================================================
# 🤔 "MAIS COMMENT ON SAIT QU'IL FAUT UTILISER ÇA ?"
# =============================================================================
#
# Excellente question ! Voici comment découvrir les ressources Terraform :
#
# 1. DOCUMENTATION OFFICIELLE DU PROVIDER
#    → https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs
#    → Cherche "security group" ou "firewall" dans la barre de recherche
#    → Tu trouveras : openstack_networking_secgroup_v2
#
# 2. RECHERCHES GOOGLE UTILES :
#    - "terraform openstack open port firewall"
#    - "terraform openstack security group rule"
#    - "terraform openstack allow ssh"
#    - "terraform openstack networking documentation"
#
# 3. LE PROCESSUS DE DÉCOUVERTE :
#    a) Tu sais ce que tu veux faire : "ouvrir le port 22 pour SSH"
#    b) Tu cherches : "terraform openstack ssh port 22"
#    c) Tu tombes sur des exemples avec "openstack_networking_secgroup_rule_v2"
#    d) Tu vas sur la doc officielle pour voir tous les paramètres
#    e) Tu adaptes l'exemple à ton cas
#
# 4. ASTUCE : Les noms de ressources suivent un pattern
#    - openstack_<service>_<ressource>_<version>
#    - Exemple : openstack_networking_secgroup_v2
#                └─ networking = service réseau
#                └─ secgroup = security group
#                └─ v2 = version de l'API
#
# 5. SI TU ES PERDU :
#    - Va sur registry.terraform.io
#    - Cherche "openstack" dans les providers
#    - Clique sur "Documentation"
#    - Explore la section "Resources" (pas "Data Sources")
#    - Cherche par mot-clé (network, security, firewall, etc.)
#
# ARCHITECTURE :
#
#   Internet
#       │
#       ▼
#   ┌───────────────┐
#   │    Routeur    │  ← Connecte le réseau privé à Internet
#   └───────────────┘
#       │
#       ▼
#   ┌───────────────────────────────────────┐
#   │         Réseau Privé (10.0.0.0/24)    │
#   │                                        │
#   │  ┌─────────────┐    ┌─────────────┐   │
#   │  │Control Plane│    │   Worker    │   │
#   │  │  10.0.0.10  │    │  10.0.0.11  │   │
#   │  │ + IP Pub A  │    │ + IP Pub B  │   │
#   │  └─────────────┘    └─────────────┘   │
#   └───────────────────────────────────────┘
#
# =============================================================================

# -----------------------------------------------------------------------------
# RÉSEAU PRIVÉ
# -----------------------------------------------------------------------------
# 
# C'est le "câble virtuel" qui relie tes VMs entre elles.
# Le trafic sur ce réseau ne passe pas par Internet.
#
# ANALOGIE : Imagine un réseau local (LAN) dans une entreprise.
#            Tous les ordinateurs sont branchés sur le même switch.
#            Ils peuvent se parler directement sans passer par Internet.
# -----------------------------------------------------------------------------

resource "openstack_networking_network_v2" "k8s_network" {
  name = "${local.prefix}-network"
  # name = Le nom du réseau (ex: "k8s-lab-network")
  # C'est juste un label pour t'aider à identifier le réseau dans l'interface OVH

  admin_state_up = true
  # admin_state_up = true : Active le réseau (il fonctionne)
  # admin_state_up = false : Désactive le réseau (il ne fonctionne pas)
  # C'est comme un interrupteur ON/OFF

  # Les tags aident à identifier les ressources dans l'interface OVH
  # Tu peux filtrer par tag pour voir toutes tes ressources d'un coup
  tags = [
    "project:${var.project_name}", # Ex: "project:k8s-lab"
    "managed_by:terraform"         # Indique que c'est géré par Terraform
  ]
}

# -----------------------------------------------------------------------------
# SOUS-RÉSEAU (SUBNET)
# -----------------------------------------------------------------------------
# 
# Définit la plage d'IPs disponibles dans le réseau privé.
# DHCP est activé mais on va quand même fixer les IPs des VMs.
#
# ANALOGIE : Si le réseau est une rue, le subnet définit les numéros de maison
#            disponibles dans cette rue (ex: numéros 100 à 200).
# -----------------------------------------------------------------------------

resource "openstack_networking_subnet_v2" "k8s_subnet" {
  name = "${local.prefix}-subnet"
  # name = Le nom du sous-réseau (ex: "k8s-lab-subnet")

  network_id = openstack_networking_network_v2.k8s_network.id
  # network_id = À quel réseau appartient ce subnet ?
  # On utilise l'ID du réseau qu'on vient de créer juste au-dessus

  cidr = var.private_network_cidr
  # cidr = La plage d'IPs complète (ex: "10.0.0.0/24")
  # Cela définit que les IPs vont de 10.0.0.0 à 10.0.0.255 (256 IPs au total)

  ip_version = 4
  # ip_version = 4 signifie IPv4 (les adresses classiques comme 10.0.0.10)
  # ip_version = 6 serait IPv6 (les nouvelles adresses comme 2001:db8::1)
  # On reste en IPv4 pour la simplicité

  dns_nameservers = ["8.8.8.8", "8.8.4.4"] # DNS Google
  # dns_nameservers = Les serveurs DNS que les VMs utiliseront
  # Quand une VM veut résoudre "google.com", elle demande à 8.8.8.8 ou 8.8.4.4
  # 8.8.8.8 et 8.8.4.4 sont les DNS publics de Google (gratuits et fiables)

  # Plage d'allocation DHCP (on réserve .1-.9 et .10-.11 pour nos VMs)
  allocation_pool {
    start = "10.0.0.100"
    end   = "10.0.0.200"
  }
  # allocation_pool = La plage d'IPs que le DHCP peut attribuer AUTOMATIQUEMENT
  # - start = "10.0.0.100" : Le DHCP peut donner des IPs à partir de 10.0.0.100
  # - end = "10.0.0.200" : Le DHCP peut donner des IPs jusqu'à 10.0.0.200
  # 
  # Pourquoi cette plage ?
  # - 10.0.0.1 à 10.0.0.9 : Réservées (gateway, services système)
  # - 10.0.0.10 à 10.0.0.11 : On va fixer ces IPs pour nos VMs Kubernetes
  # - 10.0.0.100 à 10.0.0.200 : Le DHCP peut les donner automatiquement
  # - 10.0.0.201 à 10.0.0.255 : Réservées pour plus tard

  # Pas besoin de gateway dans le subnet, le routeur s'en charge
  enable_dhcp = true
  # enable_dhcp = true : Active le service DHCP
  # Le DHCP attribuera automatiquement une IP aux VMs qui en ont besoin
  # (même si on va fixer les IPs de nos VMs Kubernetes manuellement)

}

# -----------------------------------------------------------------------------
# ROUTEUR
# -----------------------------------------------------------------------------
# 
# Le routeur connecte le réseau privé à Internet.
# Sans routeur, les VMs ne pourraient pas sortir sur Internet.
#
# ANALOGIE : Le routeur est comme la box Internet de ta maison.
#            Il connecte ton réseau local (privé) à Internet (public).
#            Sans routeur, tes VMs peuvent se parler mais ne peuvent pas
#            accéder à Internet (pas de mise à jour, pas de téléchargement, etc.)
# -----------------------------------------------------------------------------

# Récupère le réseau externe (Internet) fourni par OVH
data "openstack_networking_network_v2" "external" {
  name = "Ext-Net" # Nom du réseau externe chez OVH
}
# data = On ne CRÉE PAS ce réseau, on le RÉCUPÈRE (il existe déjà)
# "Ext-Net" est le nom du réseau Internet public fourni par OVH
# C'est comme si tu disais "donne-moi l'accès à Internet"

resource "openstack_networking_router_v2" "k8s_router" {
  name = "${local.prefix}-router"
  # name = Le nom du routeur (ex: "k8s-lab-router")

  admin_state_up = true
  # admin_state_up = true : Active le routeur (il fonctionne)

  external_network_id = data.openstack_networking_network_v2.external.id
  # external_network_id = Connecte le routeur au réseau Internet (Ext-Net)
  # C'est comme brancher ta box Internet à la prise téléphonique
}

# Connecte le routeur au sous-réseau privé
resource "openstack_networking_router_interface_v2" "k8s_router_interface" {
  router_id = openstack_networking_router_v2.k8s_router.id
  # router_id = Le routeur qu'on vient de créer

  subnet_id = openstack_networking_subnet_v2.k8s_subnet.id
  # subnet_id = Le sous-réseau privé qu'on a créé
  # 
  # Cette ressource "branche" le routeur au réseau privé.
  # Maintenant le routeur peut faire le pont entre :
  # - Le réseau privé (10.0.0.0/24) ←→ Internet (Ext-Net)
}

# -----------------------------------------------------------------------------
# SECURITY GROUP (FIREWALL)
# -----------------------------------------------------------------------------
# 
# Les security groups sont des règles de firewall appliquées aux VMs.
# Par défaut, tout est bloqué. On ouvre uniquement ce qui est nécessaire.
#
# ANALOGIE : C'est comme un garde de sécurité à l'entrée d'un bâtiment.
#            Par défaut, personne ne peut entrer (tout est bloqué).
#            Tu dois créer des règles pour dire "les personnes avec un badge
#            peuvent entrer par la porte A, les livreurs peuvent entrer par
#            la porte B, etc."
#
# COMMENT J'AI TROUVÉ CETTE RESSOURCE :
# 1. Recherche Google : "terraform openstack firewall security group"
# 2. Résultat : Documentation Terraform Registry
#    → https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2
# 3. Pattern : openstack_<service>_<ressource>_<version>
#    → networking = service réseau
#    → secgroup = security group
#    → v2 = version de l'API OpenStack
# -----------------------------------------------------------------------------

resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name = "${local.prefix}-secgroup"
  # name = Le nom du security group (ex: "k8s-lab-secgroup")

  description = "Security group pour le cluster Kubernetes"
  # description = Une description pour t'aider à comprendre à quoi sert ce firewall
}
# ⚠️ IMPORTANT : Ce security group est vide pour l'instant !
# Il bloque TOUT le trafic. On va ajouter des règles juste en dessous.

# Règle : SSH depuis l'extérieur (pour te connecter)
# 
# Cette règle permet de se connecter en SSH aux VMs depuis ton PC.
# SSH = Secure Shell, c'est le protocole pour se connecter à distance à une VM.
# 
# COMMENT J'AI TROUVÉ CETTE RESSOURCE :
# - Recherche : "terraform openstack security group rule allow port"
# - Doc : https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2
# - Pattern : secgroup_rule = règle pour un security group
#
resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction = "ingress"
  # direction = "ingress" = TRAFIC ENTRANT
  # Quelqu'un (ton PC) essaie de se connecter À la VM
  # direction = "egress" serait pour le trafic SORTANT (la VM vers Internet)

  ethertype = "IPv4"
  # ethertype = "IPv4" = On utilise IPv4 (les adresses classiques)
  # ethertype = "IPv6" serait pour IPv6 (les nouvelles adresses)

  protocol = "tcp"
  # protocol = "tcp" = Transmission Control Protocol
  # TCP est utilisé pour SSH, HTTP, HTTPS (connexions fiables)
  # protocol = "udp" serait pour DNS, streaming (connexions rapides mais moins fiables)

  port_range_min = 22
  port_range_max = 22
  # port_range_min/max = Le port à ouvrir
  # Port 22 = Le port standard pour SSH
  # C'est comme dire "ouvre la porte numéro 22"

  remote_ip_prefix = var.allowed_ssh_cidr
  # remote_ip_prefix = QUI peut se connecter ?
  # var.allowed_ssh_cidr = Probablement "0.0.0.0/0" (tout le monde) ou ton IP
  # 
  # Exemples :
  # - "0.0.0.0/0" = N'importe qui sur Internet peut essayer de se connecter
  # - "192.168.1.100/32" = Seulement l'IP 192.168.1.100 peut se connecter
  # - "10.0.0.0/24" = N'importe quelle IP entre 10.0.0.0 et 10.0.0.255
  #
  # Dans le contexte d'une règle ingress :
  # remote_ip_prefix = l'IP de CELUI QUI SE CONNECTE (ton PC)

  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
  # security_group_id = À quel firewall on applique cette règle ?
  # On applique cette règle au security group qu'on a créé juste au-dessus

  description = "SSH - Administration"
  # description = Une description pour t'aider à comprendre cette règle
}
# RÉSUMÉ DE CETTE RÈGLE :
# "Autorise les connexions TCP sur le port 22 (SSH) depuis les IPs définies
#  dans var.allowed_ssh_cidr vers toutes les VMs qui ont ce security group"

# Règle : API Kubernetes depuis l'extérieur (pour kubectl)
# 
# Cette règle permet d'utiliser kubectl depuis ton PC pour gérer le cluster.
# kubectl est l'outil en ligne de commande pour Kubernetes.
# L'API Kubernetes écoute sur le port 6443.
resource "openstack_networking_secgroup_rule_v2" "k8s_api" {
  direction = "ingress"
  # direction = "ingress" = TRAFIC ENTRANT
  # Ton PC essaie de se connecter à l'API Kubernetes de la VM

  ethertype = "IPv4"
  # ethertype = "IPv4" = On utilise IPv4

  protocol = "tcp"
  # protocol = "tcp" = Transmission Control Protocol (connexion fiable)

  port_range_min = 6443
  port_range_max = 6443
  # port_range_min/max = Le port à ouvrir
  # Port 6443 = Le port standard pour l'API Kubernetes
  # C'est comme dire "ouvre la porte numéro 6443"

  remote_ip_prefix = var.allowed_ssh_cidr # Même restriction que SSH
  # remote_ip_prefix = QUI peut se connecter ?
  # On utilise la même restriction que SSH (probablement ton IP ou 0.0.0.0/0)
  # C'est logique : si tu peux te connecter en SSH, tu peux aussi utiliser kubectl

  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
  # security_group_id = À quel firewall on applique cette règle ?

  description = "API Kubernetes"
  # description = Une description pour t'aider à comprendre cette règle
}
# RÉSUMÉ DE CETTE RÈGLE :
# "Autorise les connexions TCP sur le port 6443 (API Kubernetes) depuis les IPs
#  définies dans var.allowed_ssh_cidr vers toutes les VMs qui ont ce security group"

# Règle : Tout le trafic entre les VMs du même security group
# C'est nécessaire pour que les composants Kubernetes communiquent
#
# Cette règle permet à toutes les VMs qui ont ce security group de se parler
# entre elles, sur TOUS les ports et TOUS les protocoles.
# C'est essentiel pour Kubernetes : les nodes doivent pouvoir communiquer.
resource "openstack_networking_secgroup_rule_v2" "internal_all" {
  direction = "ingress"
  # direction = "ingress" = TRAFIC ENTRANT
  # Une VM essaie de se connecter à une autre VM

  ethertype = "IPv4"
  # ethertype = "IPv4" = On utilise IPv4

  remote_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
  # remote_group_id = QUI peut se connecter ?
  # Au lieu de spécifier une IP (remote_ip_prefix), on dit :
  # "Toutes les VMs qui ont CE security group peuvent se connecter"
  # 
  # C'est différent de remote_ip_prefix :
  # - remote_ip_prefix = "10.0.0.10/32" = Seulement cette IP précise
  # - remote_group_id = Le même security group = Toutes les VMs avec ce security group
  #
  # Ici, on met le même security_group_id dans remote_group_id ET security_group_id.
  # Cela signifie : "Les VMs avec ce security group peuvent se parler entre elles"

  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
  # security_group_id = À quel firewall on applique cette règle ?
  # On applique cette règle au security group qu'on a créé

  description = "Tout le trafic interne entre les nodes"
  # description = Une description pour t'aider à comprendre cette règle
}
# RÉSUMÉ DE CETTE RÈGLE :
# "Autorise TOUT le trafic (tous les ports, tous les protocoles) entre toutes
#  les VMs qui ont ce security group. C'est nécessaire pour que Kubernetes
#  fonctionne (les nodes doivent pouvoir communiquer entre eux)."
#
# ⚠️ NOTE : On ne spécifie pas de port ni de protocol ici.
#           Cela signifie "tous les ports et tous les protocoles".

# Règle : ICMP (ping) pour le debug
# 
# Cette règle permet d'utiliser ping pour tester la connectivité.
# ping est un outil de diagnostic réseau très utile.
# Exemple : ping 10.0.0.10 pour vérifier si la VM répond.
resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction = "ingress"
  # direction = "ingress" = TRAFIC ENTRANT
  # Quelqu'un (ton PC, une autre VM) envoie un ping vers la VM

  ethertype = "IPv4"
  # ethertype = "IPv4" = On utilise IPv4

  protocol = "icmp"
  # protocol = "icmp" = Internet Control Message Protocol
  # ICMP est utilisé pour ping (tester la connectivité)
  # C'est différent de TCP/UDP, c'est un protocole de contrôle

  remote_ip_prefix = "0.0.0.0/0"
  # remote_ip_prefix = "0.0.0.0/0" = N'IMPORTE QUI peut envoyer un ping
  # C'est moins sécurisé mais utile pour le debug
  # En production, tu pourrais restreindre à "10.0.0.0/24" (seulement le réseau privé)

  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
  # security_group_id = À quel firewall on applique cette règle ?

  description = "ICMP - Ping"
  # description = Une description pour t'aider à comprendre cette règle
}
# RÉSUMÉ DE CETTE RÈGLE :
# "Autorise les pings (ICMP) depuis n'importe où (0.0.0.0/0) vers toutes
#  les VMs qui ont ce security group. Utile pour le debug réseau."
#
# ⚠️ NOTE : On ne spécifie pas de port pour ICMP (ping n'utilise pas de port).

# Règle : NodePort services (30000-32767) - optionnel mais utile pour tester
# 
# Cette règle permet d'accéder aux services Kubernetes de type NodePort.
# NodePort est un type de service Kubernetes qui expose une application
# sur un port spécifique (entre 30000 et 32767) de tous les nodes.
# 
# Exemple : Si tu déploies une app web en NodePort sur le port 30080,
#            tu pourras y accéder via http://IP_PUBLIQUE_VM:30080
resource "openstack_networking_secgroup_rule_v2" "nodeport" {
  direction = "ingress"
  # direction = "ingress" = TRAFIC ENTRANT
  # Quelqu'un (ton navigateur, un autre service) essaie d'accéder à un service NodePort

  ethertype = "IPv4"
  # ethertype = "IPv4" = On utilise IPv4

  protocol = "tcp"
  # protocol = "tcp" = Transmission Control Protocol (connexion fiable)
  # TCP est utilisé pour HTTP, HTTPS, et la plupart des services web

  port_range_min = 30000
  port_range_max = 32767
  # port_range_min/max = La plage de ports à ouvrir
  # Ports 30000-32767 = La plage standard pour les services NodePort Kubernetes
  # C'est comme dire "ouvre les portes numérotées de 30000 à 32767"
  # 
  # Pourquoi cette plage ?
  # - Kubernetes réserve automatiquement les ports 30000-32767 pour NodePort
  # - Quand tu crées un service NodePort, Kubernetes choisit un port dans cette plage
  # - Exemple : Un service NodePort pourrait être accessible sur le port 30080

  remote_ip_prefix = "0.0.0.0/0"
  # remote_ip_prefix = "0.0.0.0/0" = N'IMPORTE QUI peut accéder aux services NodePort
  # C'est pratique pour tester, mais en production tu pourrais restreindre
  # à ton IP ou à un réseau spécifique

  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
  # security_group_id = À quel firewall on applique cette règle ?

  description = "NodePort services"
  # description = Une description pour t'aider à comprendre cette règle
}
# RÉSUMÉ DE CETTE RÈGLE :
# "Autorise les connexions TCP sur les ports 30000-32767 (NodePort Kubernetes)
#  depuis n'importe où (0.0.0.0/0) vers toutes les VMs qui ont ce security group.
#  Utile pour exposer des applications Kubernetes à Internet."
#
# ⚠️ NOTE : Cette règle est optionnelle. Si tu n'utilises pas NodePort,
#            tu peux la supprimer pour plus de sécurité.

