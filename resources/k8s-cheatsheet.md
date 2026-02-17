# Kubernetes Configuration & Debugging Cheatsheet

> **When you're panicking:** Start with "WHERE IS THE PROBLEM?" section, then follow the breadcrumbs.

---

## The Mental Model

```
/etc/        = Configuration (editable text config)
/var/lib/    = Runtime data & state
/var/log/    = Logs
/run/        = Temporary sockets/PIDs (cleared on reboot)
```

---

## Who Manages What?

```
┌─────────────────────────────────────────────────────────────────┐
│                         SYSTEMD                                 │
│                            │                                    │
│                            ▼                                    │
│                        kubelet ◄─── the ONLY systemd service    │
│                            │                                    │
│              ┌─────────────┼─────────────┐                      │
│              ▼             ▼             ▼                      │
│         static pods   regular pods   node management            │
│              │                                                  │
│    ┌─────────┼─────────┬─────────────┐                          │
│    ▼         ▼         ▼             ▼                          │
│  etcd   api-server  scheduler  controller-manager               │
│                                                                 │
│  ▲ These are NOT systemd services!                              │
│    They are pods managed by kubelet via /etc/kubernetes/manifests/ │
└─────────────────────────────────────────────────────────────────┘
```

| Process | Managed By | Config Location |
|---------|------------|-----------------|
| kubelet | systemd | `/etc/default/kubelet` + systemd units |
| kube-apiserver | kubelet (static pod) | `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| kube-scheduler | kubelet (static pod) | `/etc/kubernetes/manifests/kube-scheduler.yaml` |
| kube-controller-manager | kubelet (static pod) | `/etc/kubernetes/manifests/kube-controller-manager.yaml` |
| etcd | kubelet (static pod) | `/etc/kubernetes/manifests/etcd.yaml` |
| containerd | systemd | `/etc/containerd/config.toml` |

---

## Directory Map

### The Big Picture

```
/etc/kubernetes/          ← Control plane config & certs
/var/lib/kubelet/         ← Kubelet runtime data
/var/lib/etcd/            ← etcd database (all cluster state!)
/etc/default/kubelet      ← YOUR kubelet overrides (optional)
/etc/systemd/system/      ← Systemd service customizations
/etc/containerd/          ← Container runtime config
```

### `/etc/kubernetes/` (Control Plane Only)

```
/etc/kubernetes/
├── admin.conf                 ← kubectl config for root/admin
├── kubelet.conf               ← kubelet's credentials to talk to API
├── controller-manager.conf    ← controller-manager credentials
├── scheduler.conf             ← scheduler credentials
│
├── manifests/                 ← Static pod definitions (control plane)
│   ├── etcd.yaml              ← Edit this to change etcd config
│   ├── kube-apiserver.yaml    ← Edit this to change API server flags
│   ├── kube-controller-manager.yaml
│   └── kube-scheduler.yaml
│
└── pki/                       ← ALL THE CERTIFICATES
    ├── ca.crt / ca.key                    ← Cluster CA (signs everything)
    ├── apiserver.crt / apiserver.key      ← API server cert
    ├── apiserver-kubelet-client.crt       ← API → kubelet auth
    ├── front-proxy-ca.crt                 ← Aggregation layer CA
    ├── sa.key / sa.pub                    ← Service account signing
    └── etcd/                              ← etcd's own PKI
        ├── ca.crt
        ├── server.crt
        └── ...
```

### `/var/lib/kubelet/` (Every Node)

```
/var/lib/kubelet/
├── config.yaml            ← Kubelet's MAIN config file
├── kubeadm-flags.env      ← Auto-generated flags from kubeadm
├── pki/                   ← This node's certs
│   └── kubelet.crt
└── pods/                  ← Running pod data
```

### Systemd Files (Kubelet Only)

```
/lib/systemd/system/kubelet.service              ← Base service (DON'T EDIT)
/etc/systemd/system/kubelet.service.d/
└── 10-kubeadm.conf                              ← kubeadm's drop-in config

/etc/default/kubelet                             ← YOUR overrides (create if needed)
```

### Container Runtime

```
/etc/containerd/
└── config.toml            ← containerd config (cgroup driver, pause image)

/run/containerd/
└── containerd.sock        ← Socket kubelet talks to
```

---

## Quick Reference Table

| Question | Location |
|----------|----------|
| Where are cluster certs? | `/etc/kubernetes/pki/` |
| Where's all cluster data stored? | `/var/lib/etcd/` |
| How do I add kubelet flags? | `/etc/default/kubelet` |
| Where are control plane pod configs? | `/etc/kubernetes/manifests/` |
| What's kubelet's current config? | `/var/lib/kubelet/config.yaml` |
| Where's my kubeconfig? | `~/.kube/config` |
| What flags did kubeadm set? | `/var/lib/kubelet/kubeadm-flags.env` |

---

## WHERE IS THE PROBLEM? (Debug Decision Tree)

```
Is the cluster reachable? (kubectl get nodes)
│
├─ NO → Is kubelet running?
│       │
│       ├─ NO → systemctl status kubelet
│       │       journalctl -u kubelet -f
│       │       Check: /etc/default/kubelet, /var/lib/kubelet/config.yaml
│       │
│       └─ YES → Is API server running?
│                │
│                ├─ NO → Check static pod manifest:
│                │       cat /etc/kubernetes/manifests/kube-apiserver.yaml
│                │       crictl ps -a | grep apiserver
│                │       crictl logs <container_id>
│                │
│                └─ YES → Certificate issue?
│                         kubeadm certs check-expiration
│                         openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout
│
└─ YES → Which component is failing?
         │
         ├─ Pods not scheduling → Check scheduler
         │   kubectl logs -n kube-system kube-scheduler-<node>
         │   cat /etc/kubernetes/manifests/kube-scheduler.yaml
         │
         ├─ Pods not starting → Check kubelet on that node
         │   journalctl -u kubelet -f
         │   crictl ps -a
         │   crictl logs <container_id>
         │
         └─ Networking issues → Check CNI
             ls /etc/cni/net.d/
             kubectl get pods -n kube-system | grep -E 'cilium|flannel|calico'
```

---

## Essential Debug Commands

### Kubelet Debugging

```bash
# See kubelet status
sudo systemctl status kubelet

# See kubelet logs (live)
sudo journalctl -u kubelet -f

# See kubelet logs (last 100 lines)
sudo journalctl -u kubelet -n 100 --no-pager

# See ALL kubelet config (systemd + drop-ins)
sudo systemctl cat kubelet

# See the ACTUAL running command with all flags
ps aux | grep kubelet

# See kubelet's config file
cat /var/lib/kubelet/config.yaml

# See kubeadm-generated flags
cat /var/lib/kubelet/kubeadm-flags.env

# See your custom overrides (if any)
cat /etc/default/kubelet
```

### Control Plane Debugging

```bash
# See control plane pod manifests
ls /etc/kubernetes/manifests/

# Check a specific component's config
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# See running containers (bypasses API server)
sudo crictl ps

# See ALL containers including stopped
sudo crictl ps -a

# Get container logs directly
sudo crictl logs <container_id>

# See what's happening with static pods
sudo crictl ps -a | grep -E 'etcd|apiserver|scheduler|controller'
```

### Certificate Debugging

```bash
# Check ALL cert expirations at once
sudo kubeadm certs check-expiration

# View a specific certificate's details
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout

# Check just expiration date
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate

# Renew all certificates
sudo kubeadm certs renew all
sudo systemctl restart kubelet
```

### Node & Networking

```bash
# See node IPs (check INTERNAL-IP is correct)
kubectl get nodes -o wide

# Check CNI config
ls -la /etc/cni/net.d/

# Check CNI pods
kubectl get pods -n kube-system | grep -E 'cni|cilium|flannel|calico|weave'

# Check if IP forwarding is enabled
sysctl net.ipv4.ip_forward

# Check containerd
sudo systemctl status containerd
cat /etc/containerd/config.toml
```

---

## How Kubelet Args Work (The Confusing Part)

The `systemctl cat kubelet` output shows this chain:

```
┌─────────────────────────────────────────────────────────────────────┐
│  ExecStart=/usr/bin/kubelet                                         │
│      $KUBELET_KUBECONFIG_ARGS   ← hardcoded in 10-kubeadm.conf     │
│      $KUBELET_CONFIG_ARGS       ← hardcoded in 10-kubeadm.conf     │
│      $KUBELET_KUBEADM_ARGS      ← from /var/lib/kubelet/kubeadm-flags.env │
│      $KUBELET_EXTRA_ARGS        ← from /etc/default/kubelet (YOURS) │
└─────────────────────────────────────────────────────────────────────┘
```

### To Add Custom Kubelet Flags:

```bash
# Create/edit the file
echo 'KUBELET_EXTRA_ARGS=--node-ip=10.0.0.5' | sudo tee /etc/default/kubelet

# Restart kubelet
sudo systemctl restart kubelet

# Verify it's using your flag
ps aux | grep kubelet | grep node-ip
```

The `-` in `EnvironmentFile=-/etc/default/kubelet` means **optional** — if the file doesn't exist, it's not an error.

---

## Modifying Control Plane Components

Control plane components are **static pods**, not systemd services!

```bash
# To change API server flags:
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml

# Kubelet automatically detects the change and restarts the pod
# No systemctl restart needed!

# Watch it restart
sudo crictl ps -a | grep apiserver
```

---

## Two Types of Certificates

| Type | Location | Managed By | Renewal |
|------|----------|------------|---------|
| Cluster PKI (internal) | `/etc/kubernetes/pki/` | kubeadm | `kubeadm certs renew all` |
| App TLS (ingress/HTTPS) | Kubernetes Secrets | cert-manager | Automatic |

```bash
# Cluster certs: Check expiration
sudo kubeadm certs check-expiration

# App certs: List TLS secrets
kubectl get secrets -A --field-selector type=kubernetes.io/tls
```

---

## Common Scenarios

### Scenario: Kubelet Won't Start

```bash
# 1. Check status
sudo systemctl status kubelet

# 2. Check logs
sudo journalctl -u kubelet -n 50 --no-pager

# 3. Common causes:
#    - Swap enabled: sudo swapoff -a
#    - containerd not running: sudo systemctl start containerd
#    - Bad config: cat /var/lib/kubelet/config.yaml
#    - Certificate expired: sudo kubeadm certs check-expiration
```

### Scenario: API Server Not Responding

```bash
# 1. Check if container is running
sudo crictl ps -a | grep apiserver

# 2. Check container logs
sudo crictl logs <container_id>

# 3. Check manifest
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# 4. Check certs
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate
```

### Scenario: Node Shows Wrong IP

```bash
# 1. Check current IP
kubectl get nodes -o wide

# 2. Set correct IP
echo "KUBELET_EXTRA_ARGS=--node-ip=10.0.0.X" | sudo tee /etc/default/kubelet

# 3. Restart kubelet
sudo systemctl restart kubelet

# 4. Verify
kubectl get nodes -o wide
```

### Scenario: Need to Reset Everything

```bash
# Nuclear option - reset cluster
sudo kubeadm reset --cri-socket=unix:///run/containerd/containerd.sock
sudo rm -rf /etc/kubernetes /var/lib/etcd ~/.kube

# Then re-run kubeadm init
```

---

## Remember

1. **kubelet is the only systemd service** — everything else is pods
2. **Static pods live in `/etc/kubernetes/manifests/`** — edit YAML, kubelet auto-restarts
3. **Your kubelet overrides go in `/etc/default/kubelet`** — create it if needed
4. **`ps aux | grep <process>`** shows the ACTUAL running command
5. **`systemctl cat <service>`** shows WHERE config comes from
6. **Follow the breadcrumbs** — each file points to others

---

*Last updated: 2025*
