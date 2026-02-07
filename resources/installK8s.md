Resources found at this [gentleman repo](https://gitlab.com/chadmcrowell/container-security-course/-/blob/main/0-Introduction-and-Setup/Installing-Kubernetes.md)

# INSTALLING KUBERNETES

You can use the scripts, in order, or you can use the below written instructions for a more human-readable and verbose script:
1. [Initialize The Kubernetes Cluster](initializing-k11s-cluster.sh)
2. [Installing Kubernetes](installing-kubernetes.sh)

## INSTALL CONTAINERD

```bash
# update packages in apt package manager
sudo apt update

# install containerd using the apt package manager
# containerd is lightwieght, reliable and fast (CRI native)
sudo apt-get install -y containerd

# create /etc/containerd directory for containerd configuration
sudo mkdir -p /etc/containerd

# Generate the default containerd configuration
# Change the pause container to version 3.10 (pause container holds the linux ns for Kubernetes namespaces)
# Set `SystemdCgroup` to true to use same cgroup drive as kubelet
# See here for more info https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd-systemd
# See here for more info about cgroup drivers https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers
containerd config default \
| sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
| sed 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.10"|' \
| sudo tee /etc/containerd/config.toml > /dev/null

# Restart containerd to apply the configuration changes
sudo systemctl restart containerd

# Kubernetes doesn’t support swap unless explicitly configured under cgroup v2
# See here for more info https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#swap-configuration
sudo swapoff -a
```

## INSTALL KUBEADM, KUBELET, and KUBECTL

```bash
# update packages
sudo apt update

# install apt-transport-https ca-certificates curl and gpg packages using 
# apt package manager in order to fetch Kubernetes packages from 
# external HTTPS repositories
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# create a secure directory for storing GPG keyring files 
# used by APT to verify trusted repositories. 
# This is part of a newer, more secure APT repository layout that 
# keeps trusted keys isolated from system-wide GPG configurations
sudo mkdir -p -m 755 /etc/apt/keyrings

# download the k8s release gpg key FOR 1.33
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg


# Download and convert the Kubernetes APT repository's GPG public key into
# a binary format (`.gpg`) that APT can use to verify the integrity
# and authenticity of Kubernetes packages during installation. 
# This overwrites any existing configuration in 
# /etc/apt/sources.list.d/kubernetes.list FOR 1.33 
# (`tee` without `-a` (append) will **replace** the contents of the file)
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# update packages in apt 
sudo apt-get update

apt-cache madison kubelet
apt-cache madison kubectl
apt-cache madison kubeadm


KUBE_VERSION="1.33.2-1.1"

# install kubelet, kubeadm, and kubectl at version 1.33.2-1.1
sudo apt-get install -y kubelet=$KUBE_VERSION kubeadm=$KUBE_VERSION kubectl=$KUBE_VERSION

# hold these packages at version 
sudo apt-mark hold kubelet kubeadm kubectl
```

## ENABLE IP FORWARDING

```bash
# enable IP packet forwarding on the node, which allows the Linux kernel 
# to route network traffic between interfaces. 
# This is essential in Kubernetes for pod-to-pod communication 
# across nodes and for routing traffic through the control plane
# or CNI-managed networks
# See here for more info https://kubernetes.io/docs/setup/production-environment/container-runtimes/#network-configuration
sudo sysctl -w net.ipv4.ip_forward=1

# uncomment the line in /etc/sysctl.conf enabling IP forwarding after reboot
sudo sed -i '/^#net\.ipv4\.ip_forward=1/s/^#//' /etc/sysctl.conf

# Apply the changes to sysctl.conf
# Any changes made to sysctl configuration files take immediate effect without requiring a reboot
sudo sysctl -p
```

## INSTALL HELM

Helm is required later to install Cilium (CNI). Install it on the control plane node (and optionally on workers if you run Helm from there). See [Helm install docs](https://helm.sh/docs/intro/install/). Below: install via Apt (Debian/Ubuntu), courtesy of the Helm community / Buildkite.

```bash
# Dependencies and GPG key for Helm Apt repo
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Install Helm
sudo apt-get update
sudo apt-get install helm

# Verify
helm version
```

## INITIALIZE THE CLUSTER (ONLY FROM CONTROL PLANE)

```bash
########################################
# ⚠️ WARNING ONLY ON THE CONTROL PLANE #
#######################################
# Initialize the cluster specifying containerd as the container runtime, ensuring that the --cri-socket argument includes the unix:// prefix
# containerd.sock is a Unix domain socket used by containerd
# The Unix socket mechanism is a method for inter-process communication (IPC) on the same host.
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket=unix:///run/containerd/containerd.sock

# HOW TO RESET IF NEEDED
# sudo kubeadm reset --cri-socket=unix:///run/containerd/containerd.sock
# sudo rm -rf /etc/kubernetes /var/lib/etcd

# ONLY ON CONTROL PLANE (also in the output of 'kubeadm init' command)
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# ONLY FOR FLANNEL: Load `br_netfilter` and enable bridge networking
# ONLY FOR FLANNEL: echo "br_netfilter" | sudo tee /etc/modules-load.d/br_netfilter.conf

# --- Install CNI: Cilium (via Helm) ---
# Prerequisite: Helm must be installed (see INSTALL HELM section above).
# Cilium requires Linux kernel >= 5.10 (Ubuntu 22.04+ is fine).
# Docs: https://docs.cilium.io/en/stable/installation/install-helm/

# Option A: OCI registry (recommended, no repo add)
helm install cilium oci://quay.io/cilium/charts/cilium \
  --version 1.19.0 \
  --namespace kube-system

# Option B: Traditional Helm repo (if OCI fails or you prefer)
# helm repo add cilium https://helm.cilium.io/
# helm repo update
# helm install cilium cilium/cilium --version 1.19.0 --namespace kube-system

# If the cluster had pods running before Cilium (e.g. CoreDNS), restart them so Cilium manages their network:
# kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTNETWORK:.spec.hostNetwork --no-headers=true | grep '<none>' | awk '{print "-n "$1" "$2}' | xargs -L 1 -r kubectl delete pod

# Validate (install Cilium CLI from https://github.com/cilium/cilium-cli/releases, then):
# cilium status --wait
# cilium connectivity test
```

## INSTALL CERT-MANAGER (ONLY ON CONTROL PLANE)

cert-manager issues and renews TLS certificates (e.g. for Ingress, Let's Encrypt). Docs: https://cert-manager.io/docs/installation/helm/

```bash
# Option A: OCI registry (recommended)
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.19.2 \  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

# Option B: Legacy Helm repo
# helm repo add jetstack https://charts.jetstack.io --force-update
# helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.19.2 --set crds.enabled=true
```

## INSTALL EXTERNAL-SECRETS (ONLY ON CONTROL PLANE)

External Secrets syncs secrets from an external store (Vault, AWS Secrets Manager, etc.) into Kubernetes Secrets. Docs: https://external-secrets.io/latest/introduction/getting-started/

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true

# To install CRDs manually instead (then use --set installCRDs=false in the helm install above):
# kubectl apply -f "https://raw.githubusercontent.com/external-secrets/external-secrets/v0.10.0/deploy/crds/bundle.yaml" --server-side
```

## JOIN THE WORKER NODES TO THE CLUSTER

```bash
#######################################
# ⚠️ WARNING: DO NOT USE THIS COMMAND #
#######################################
# Get this command from the 'kubeadm init' output instead (above)
sudo kubeadm join x.x.x.x:6443 --token lllrj0.pystabmhlyt2svty --discovery-token-ca-cert-hash sha256:9d2fd15886eb176466640067f361ed2295de38188b057becf31d3bf5a4fb0b73
```