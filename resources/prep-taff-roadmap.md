# Préparer ton taff — CDN Cloudflare, stack Wiremind, Terraform

Ce doc résume ce qu’est un CDN / Cloudflare dans ton contexte, et ce que tu peux pratiquer en priorité (cert-manager, external-dns, external-secrets, Terraform) pour être à l’aise au démarrage.

---

## 1. CDN et Cloudflare — en bref

### CDN (Content Delivery Network)

- **Idée** : au lieu que tout le monde tape directement sur ton serveur (ou ton Ingress k8s), le trafic passe par des **points de présence (PoP)** proches des utilisateurs. Le contenu (pages, images, APIs) est servi depuis ces PoP → moins de latence, moins de charge sur ton cluster.
- **En pratique** : tu pointes ton **nom de domaine** (ex. `api.mondomaine.com`) vers le CDN. Le CDN :
  - reçoit les requêtes,
  - les met en cache quand c’est possible,
  - et “origine” (forward) vers ton vrai serveur (ici souvent un **Ingress** dans ton cluster k8s) quand il faut.

Donc : **CDN = couche devant ton cluster** pour performance, cache et souvent sécurité (DDoS, WAF).

### Cloudflare en particulier

Cloudflare est un **CDN + DNS + sécurité** très utilisé :

- **DNS** : ils hébergent les enregistrements DNS de ton domaine (A, CNAME, etc.). C’est souvent là qu’on pointe `api.mondomaine.com` → IP ou CNAME de ton Ingress / Load Balancer.
- **Proxy / CDN** : quand le trafic passe “à travers” Cloudflare (proxy activé, nuage orange), ils font cache, DDoS, WAF, et renvoient vers ton origine (ton cluster).
- **TLS** : ils peuvent terminer le SSL (HTTPS) côté Cloudflare et parler en HTTP ou HTTPS vers ton cluster (flexible / full / full strict).

**Lien avec Kubernetes** :

- Ton **Ingress** (ou un LoadBalancer) expose ton app sur une IP ou un hostname.
- Dans Cloudflare, tu crées un enregistrement (A ou CNAME) qui pointe ton domaine vers cette IP/hostname.
- **external-dns** (voir plus bas) peut **créer/mettre à jour ces enregistrements DNS automatiquement** quand tu crées des Ingress ou des Services dans k8s — y compris vers Cloudflare (provider Cloudflare).

Donc quand ils parlent de “CDN Cloudflare” en entretien, ça recouvre en général : **DNS chez Cloudflare + proxy/CDN devant le cluster + souvent external-dns pour lier k8s et Cloudflare**.

---

## 2. Stack mentionnée par Lola — où tu peux t’entraîner

Récap de ce qu’elle a cité et comment le mettre en pratique dans ton lab.

| Composant | Rôle | Où tu en es / à faire |
|-----------|------|------------------------|
| **Cilium** (CNI) | Réseau + policies | Déjà en place ✅ |
| **coredns + nodelocaldns** | DNS interne cluster | Tu peux laisser coredns par défaut ; nodelocaldns = cache DNS sur chaque nœud (optionnel en lab). |
| **cert-manager** | Certificats TLS (ex. Let’s Encrypt) pour Ingress | Déjà dans `installK8s.md` — **à installer et utiliser** sur un Ingress. |
| **external-dns** | Crée/met à jour les enregistrements DNS (ex. Cloudflare) à partir des Ingress/Services | Pas encore dans tes ressources — **priorité pour “CDN Cloudflare”**. |
| **external-secrets** | Sync secrets (Vault, AWS Secrets Manager, etc.) → Secrets k8s | Déjà dans `installK8s.md` — **à installer et faire un PoC** (même avec un backend simple). |
| **Cluster API + OpenStack + kubeadm** | Provisioning des clusters | Plus “platform” ; en lab tu peux juste lire la doc / concepts, pas obligé de tout reproduire. |

Conseil : **cert-manager + external-dns + external-secrets** sur ton cluster actuel, c’est le meilleur retour pour le taff. Si tu ajoutes un domaine (même un sous-domaine gratuit ou un NIP.io) et Cloudflare (compte gratuit), tu peux faire **cert-manager + external-dns avec Cloudflare** et voir tout le lien CDN/DNS/k8s.

---

## 3. Ce que tu peux faire concrètement (ordre suggéré)

### 3.1 cert-manager

- Installer comme dans `installK8s.md`.
- Créer un **ClusterIssuer** Let’s Encrypt (staging puis prod).
- Exposer une app avec un **Ingress** (TLS) et une ressource **Certificate** (ou annotation `cert-manager.io/cluster-issuer`).
- Vérifier que le certificat est délivré et renouvelé (`kubectl get certificate`, logs cert-manager).

→ Ça te donne le schéma TLS “classique” qu’ils utilisent sûrement.

### 3.2 external-dns

- Comprendre le principe : external-dns lit les Ingress/Services (hostnames, annotations) et crée/met à jour les enregistrements dans un fournisseur DNS (Cloudflare, AWS Route53, etc.).
- Avec **Cloudflare** : compte gratuit, créer une zone (ou sous-domaine), récupérer un **API Token** (Zone → DNS → Edit).
- Installer external-dns (Helm ou manifest) avec le provider **Cloudflare**.
- Créer un Ingress avec un host (ex. `echo.tondomaine.com`) et voir l’enregistrement apparaître dans Cloudflare.

→ Là tu vois le lien **k8s ↔ DNS ↔ CDN** dont ils parlaient.

### 3.3 external-secrets

- Installer comme dans `installK8s.md`.
- Faire un **petit backend** (ex. Vault en dev, ou même un SecretStore “fake” avec un secret local pour comprendre les CRD).
- Créer un **ExternalSecret** qui sync vers un Secret k8s et monter ce secret dans un Pod.
- Plus tard : connecter un vrai backend (Vault, AWS Secrets Manager) si tu en as un.

→ C’est exactement “les classiques” qu’elle cite.

### 3.4 Terraform

- Tu as déjà Scaleway (instances, réseau, etc.) — bien pour comprendre providers, state, variables.
- Pour coller au taff : **Terraform + Kubernetes provider** pour déclarer des ressources k8s (namespaces, Ingress, voire Helm release) si tu veux tout en IaC.
- Optionnel : lire la doc **Cluster API** (concepts : MachineDeployment, KubeadmControlPlane, etc.) pour comprendre comment ils provisionnent les clusters ; pas besoin de tout refaire en lab.

---

## 4. Résumé

- **CDN Cloudflare** = DNS + proxy/cache devant ton cluster ; en k8s on branche souvent **external-dns** (provider Cloudflare) pour que les Ingress créent les DNS automatiquement.
- Pour préparer le taff : **cert-manager** (TLS), **external-dns** (DNS/Cloudflare), **external-secrets** (secrets), puis **Terraform** (déjà commencé). Ton lab Cilium + ces briques te met très bien dans le même monde qu’eux.

Si tu veux, on peut détailler la config exacte d’external-dns avec Cloudflare (Helm values, annotations Ingress) dans un prochain fichier ou directement dans ce repo.
