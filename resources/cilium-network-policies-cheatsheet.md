# Cilium Lab — Résumé

## L'environnement

Namespace `cilium-lab` avec 3 pods :

- **web** : serveur nginx sur le port 80
- **api** : serveur http-echo sur le port 5678
- **client** : pod curl qui envoie des requêtes

```bash
k run web --image=nginx --port=80 -n cilium-lab --labels="app=web"
k expose pod web --port=80 -n cilium-lab

k run api --image=hashicorp/http-echo --port=5678 -n cilium-lab -- -text="hello from api" -listen=:5678
k expose pod api --port=5678 -n cilium-lab

k run client --image=curlimages/curl -n cilium-lab --labels="app=client" -- sleep 3600
```

---

## Default Deny — tout bloquer par défaut

**Principe** : sans policy, tous les pods peuvent se parler. On pose un default deny pour tout couper, puis on ouvre chirurgicalement.

**Attention** : ne PAS utiliser `ingressDeny`/`egressDeny` dans une CiliumNetworkPolicy pour le default deny. Les règles Deny ont **toujours priorité** sur les Allow dans Cilium, donc les allow qu'on pose ensuite ne marcheront jamais.

→ Utiliser une **NetworkPolicy Kubernetes standard** pour le default deny :

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: cilium-lab
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Résultat** : tout le trafic est bloqué (exit code 28 = timeout sur les curl).

---

## Microsegmentation L3/L4 — ouvrir uniquement ce qui est nécessaire

On autorise `client → web` sur le port 80, mais `client → api` reste bloqué.

**Ingress sur web** (qui peut lui parler) :

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-client-to-web
  namespace: cilium-lab
spec:
  endpointSelector:
    matchLabels:
      app: web
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: client
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

**Egress sur client** (où il peut aller + DNS) :

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-client-egress
  namespace: cilium-lab
spec:
  endpointSelector:
    matchLabels:
      app: client
  egress:
  - toEndpoints:
    - matchLabels:
        app: web
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
  - toEndpoints:
    - matchLabels:
        io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
```

**Résultat** :

- `curl web` → page nginx ✅
- `curl api:5678` → timeout ❌

**Pourquoi c'est important** : si le pod `client` est compromis, l'attaquant ne peut pas pivoter vers `api`. C'est le principe du **blast radius** limité.

---

## Policies L7 HTTP — contrôler au niveau de l'API

C'est ce qui différencie Cilium des NetworkPolicy K8s standard (qui ne voient que IP + port).

Quand on pose une règle L7, Cilium insère **Envoy** comme proxy transparent dans le chemin du trafic. Ça permet de filtrer par méthode HTTP, path, headers...

**Autoriser uniquement GET sur web** :

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-client-to-web-l7
  namespace: cilium-lab
spec:
  endpointSelector:
    matchLabels:
      app: web
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: client
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: GET
```

**Résultat** :

- `curl web` (GET) → page nginx ✅
- `curl -X POST web` → "Access denied" ❌
- `curl -X DELETE web` → "Access denied" ❌

**On peut aussi filtrer par path** : `method: GET` + `path: "/index.html"` pour n'autoriser qu'une URL précise.

---

## Hubble UI — observer le trafic

Accès via `cilium hubble ui` (port-forward depuis la machine locale avec `ssh -L 12000:localhost:12000`).

**Ce qu'on voit** :

| Élément | Signification |
|---|---|
| Ligne pleine grise | Trafic autorisé (forwarded) |
| Pointillés rouges | Trafic bloqué récemment (dropped) |
| Label "TCP" seul | Inspection L3/L4 uniquement |
| Label "TCP • HTTP" | Inspection L7 active (Envoy injecté) |
| Colonne "L7 info" | Détails HTTP : méthode, path, code retour |

Les logs en bas de l'UI montrent chaque flux avec le verdict `forwarded` (vert) ou `dropped` (rouge).

---

## Règles à retenir

1. **Deny > Allow** toujours dans Cilium → utiliser les NetworkPolicy K8s pour le default deny
2. **Il faut penser ingress ET egress** : autoriser l'entrée sur web ne suffit pas, il faut aussi autoriser la sortie du client (+ le DNS)
3. **Les règles L7 activent automatiquement Envoy** : dès qu'on met un bloc `rules: http:`, Cilium proxy le trafic
4. **Hubble montre tout en temps réel** : pas besoin de tcpdump, on voit les policies en action directement

---

## Commandes utiles

```bash
# Lister les CiliumNetworkPolicies
k get cnp -n cilium-lab

# Décrire une policy (vérifier si Valid)
k describe cnp <nom> -n cilium-lab

# Observer le trafic en CLI
hubble observe -n cilium-lab

# Tester la connectivité
k exec -n cilium-lab client -- curl -s --max-time 3 web
k exec -n cilium-lab client -- curl -s --max-time 3 -X POST web

# Nettoyage
k delete ns cilium-lab
```