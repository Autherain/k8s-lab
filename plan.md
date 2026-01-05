# Contexte

Je suis développeur backend Go. Dans 2 mois, je commence un poste de platform engineer junior. Je veux me préparer.

## Ce que je vais faire au boulot

Stack de l'entreprise (confirmé par ma future boss) :

- Cluster API pour provisionner des clusters k8s sur OpenStack (OVH)
- kubeadm avec Ubuntu
- Cilium comme CNI
- CoreDNS + NodeLocalDNS
- cert-manager, external-dns, external-secrets

## Ce que je sais faire

- Go (mon métier actuel)
- Kubernetes en tant qu'utilisateur (déployer des apps, debug basique)
- Bidouillé des serveurs Linux quand ça cassait

## Ce que je ne maîtrise pas encore

- Installer un cluster k8s from scratch (kubeadm)
- Terraform / Infrastructure as Code
- Administration Linux sérieuse (RAID, LVM, réseau)
- Cilium
- Cluster API

## Mon matériel

- Accès à OVH Public Cloud pour créer des VMs

---

# Plan de bataille

## Phase 1 : Cluster kubeadm manuel

Objectif : comprendre comment un cluster k8s se monte à la main.

1. Provisionner 2 VMs Ubuntu sur OVH (via Terraform si possible, sinon via l'interface)
2. Configurer le réseau entre les VMs (IPs statiques, SSH)
3. Installer kubeadm sur les 2 machines
4. Initialiser le control-plane sur la première VM
5. Joindre la deuxième VM comme worker
6. Vérifier que le cluster fonctionne (kubectl get nodes)

## Phase 2 : Installer Cilium

Objectif : remplacer le CNI par défaut par Cilium.

1. Supprimer le CNI par défaut (si installé)
2. Installer Cilium via Helm ou CLI
3. Vérifier que les pods se parlent
4. Tester une NetworkPolicy basique

## Phase 3 : Ajouter cert-manager

Objectif : comprendre la gestion automatique des certificats TLS.

1. Installer cert-manager via Helm
2. Créer un ClusterIssuer (Let's Encrypt staging)
3. Déployer une app avec un Ingress + TLS automatique

## Phase 4 : Découvrir Cluster API (lecture + expérimentation)

Objectif : comprendre comment Cluster API automatise ce que j'ai fait en phase 1.

1. Lire la doc officielle de Cluster API
2. Comprendre les concepts : Management Cluster, Workload Cluster, Providers
3. Si possible, monter un petit management cluster et créer un workload cluster

## En parallèle

- Préparer le CKA (pratique sur killer.sh)
- Lire "How Linux Works" (en complément)

---

# Comment m'aider

- Guide-moi étape par étape
- Donne-moi les commandes concrètes à exécuter
- Explique ce que chaque commande fait
- Préviens-moi des erreurs courantes
- Si je suis bloqué, aide-moi à débugger

Je suis débutant sur ces sujets, donc sois pédagogue.
