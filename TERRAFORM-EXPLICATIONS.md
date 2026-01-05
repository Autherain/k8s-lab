# Comprendre Terraform - Guide pour ne rien casser

## Le fichier le plus important : `terraform.tfstate`

### C'est quoi ?

`terraform.tfstate` est la **mémoire de Terraform**. Ce fichier JSON contient :

- L'ID de chaque ressource créée (VMs, IPs, réseau, etc.)
- Les attributs actuels de chaque ressource
- Les dépendances entre ressources

### Pourquoi c'est crucial ?

```
Sans terraform.tfstate, Terraform ne sait pas ce qu'il a créé.

Exemple :
1. Tu lances "terraform apply" → 2 VMs sont créées
2. Tu supprimes terraform.tfstate
3. Tu relances "terraform apply" → Terraform croit qu'il n'y a rien
4. Résultat : 2 NOUVELLES VMs sont créées (= 4 VMs au total)
   Et tu paies pour les 4 !
```

### Les règles d'or

1. **NE JAMAIS supprimer** `terraform.tfstate`
2. **NE JAMAIS le modifier** à la main
3. **NE JAMAIS le commiter** sur Git (il contient des infos sensibles)
4. **TOUJOURS le sauvegarder** avant des opérations risquées (`make backup`)

---

## Comment Terraform fonctionne

### Le cycle de vie

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│    1. terraform init                                            │
│       └── Télécharge les plugins (provider OpenStack)           │
│                                                                 │
│    2. terraform plan                                            │
│       └── Compare l'état actuel avec la configuration           │
│       └── Affiche ce qui SERAIT créé/modifié/supprimé           │
│       └── NE FAIT RIEN                                          │
│                                                                 │
│    3. terraform apply                                           │
│       └── Exécute le plan                                       │
│       └── Crée/modifie/supprime les ressources                  │
│       └── Met à jour terraform.tfstate                          │
│                                                                 │
│    4. terraform destroy                                         │
│       └── Supprime TOUTES les ressources                        │
│       └── Met à jour terraform.tfstate (vide)                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Idempotence

Terraform est **idempotent** : tu peux relancer `terraform apply` plusieurs fois, ça ne recrée pas les ressources.

```
# Première fois : crée 2 VMs
terraform apply
→ openstack_compute_instance_v2.control_plane: Creating...
→ openstack_compute_instance_v2.worker: Creating...

# Deuxième fois : ne fait rien (les VMs existent déjà)
terraform apply
→ No changes. Your infrastructure matches the configuration.
```

**C'est safe de relancer `terraform apply` !**

---

## Les IPs statiques

### Comment ça marche ?

1. Terraform crée une "IP flottante" (floating IP) chez OVH
2. Cette IP est **réservée** et **persistante**
3. L'IP est **associée** à une VM
4. Si tu refais `terraform apply`, l'IP reste la même

### Pourquoi l'IP reste stable ?

```hcl
# Dans terraform.tfstate, Terraform stocke :
{
  "type": "openstack_networking_floatingip_v2",
  "attributes": {
    "address": "51.xxx.xxx.xxx",   ← L'IP est stockée
    "id": "abc-123-def",           ← L'ID de la ressource
    ...
  }
}
```

Tant que tu ne supprimes pas cette ressource (ou le tfstate), l'IP reste la même.

---

## Les certificats Kubernetes

### Où sont-ils ?

Les certificats Kubernetes sont **générés par kubeadm** (pas par Terraform).

Ils sont stockés sur le control-plane dans `/etc/kubernetes/pki/` :

```
/etc/kubernetes/pki/
├── ca.crt                 # Autorité de certification du cluster
├── ca.key                 # Clé privée de la CA
├── apiserver.crt          # Certificat de l'API server
├── apiserver.key          # Clé privée de l'API server
├── apiserver-kubelet-client.crt
├── apiserver-kubelet-client.key
├── front-proxy-ca.crt
├── front-proxy-ca.key
├── front-proxy-client.crt
├── front-proxy-client.key
├── etcd/
│   ├── ca.crt
│   ├── ca.key
│   └── ...
└── sa.key / sa.pub        # Service Account keys
```

### Comment ne pas les perdre ?

1. **Ne pas recréer la VM control-plane** sans raison
2. **Sauvegarder `/etc/kubernetes/pki/`** si tu veux recréer le cluster
3. **Ne pas rejouer `kubeadm init`** (ça régénère les certificats)

### Si tu casses les certificats

Option 1 : Regénérer (perd l'état du cluster)
```bash
sudo kubeadm reset
sudo kubeadm init ...
```

Option 2 : Restaurer depuis une sauvegarde
```bash
# Si tu as sauvegardé /etc/kubernetes/pki/
sudo cp -r /backup/pki /etc/kubernetes/pki
sudo systemctl restart kubelet
```

---

## Scénarios courants

### "J'ai modifié terraform.tfvars, que se passe-t-il ?"

```bash
# 1. Vérifie ce qui va changer
make plan

# 2. Applique si ça te convient
make apply
```

Terraform va adapter l'infrastructure à la nouvelle configuration.

### "J'ai supprimé terraform.tfstate par erreur"

**Situation critique !** Terraform ne sait plus ce qu'il a créé.

Solutions :
1. **Restaurer depuis une sauvegarde** (`terraform.tfstate.backup.*`)
2. **Importer les ressources** manuellement (complexe)
3. **Supprimer tout à la main** sur OVH et recommencer

### "Je veux changer la taille d'une VM"

```bash
# 1. Modifie terraform.tfvars
control_plane_flavor = "s1-8"  # Au lieu de s1-4

# 2. Vérifie ce qui va changer
make plan
# → Terraform va dire : "destroy + recreate" la VM

# 3. Applique
make apply
```

⚠️ **Attention** : changer le flavor = recréer la VM = perdre les données !

### "Je veux juste redémarrer une VM"

Ne passe pas par Terraform ! Connecte-toi en SSH :

```bash
make ssh-cp
sudo reboot
```

Ou via l'interface OVH.

---

## Commandes de secours

### Voir l'état actuel

```bash
cd terraform

# Liste toutes les ressources
terraform state list

# Détails d'une ressource
terraform state show openstack_compute_instance_v2.control_plane
```

### Rafraîchir l'état

Si l'état est désynchronisé (ressource modifiée à la main) :

```bash
terraform refresh
```

### Forcer la suppression d'une ressource de l'état

Si une ressource a été supprimée à la main mais est encore dans le tfstate :

```bash
terraform state rm openstack_compute_instance_v2.worker
```

---

## Workflow safe

```
┌──────────────────────────────────────────────────────────────┐
│                    WORKFLOW RECOMMANDÉ                       │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  1. AVANT de modifier quoi que ce soit :                     │
│     make backup                                              │
│                                                              │
│  2. TOUJOURS prévisualiser les changements :                 │
│     make plan                                                │
│                                                              │
│  3. Lire attentivement le plan :                             │
│     - "create" = nouvelle ressource                          │
│     - "update" = modification sur place                      │
│     - "destroy" = suppression (⚠️)                           │
│     - "replace" = destroy + create (⚠️⚠️)                    │
│                                                              │
│  4. Appliquer seulement si le plan est OK :                  │
│     make apply                                               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## Résumé des fichiers

| Fichier | À commiter ? | À sauvegarder ? | Peut être regénéré ? |
|---------|--------------|-----------------|----------------------|
| `*.tf` | ✅ Oui | - | Non |
| `terraform.tfvars` | ❌ Non | ✅ Oui | Non |
| `terraform.tfstate` | ❌ Non | ✅✅ OUI ! | Non |
| `.terraform/` | ❌ Non | ❌ Non | ✅ Oui (`terraform init`) |
| `tfplan` | ❌ Non | ❌ Non | ✅ Oui (`terraform plan`) |

