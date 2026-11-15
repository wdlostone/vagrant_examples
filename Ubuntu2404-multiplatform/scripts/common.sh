#!/usr/bin/env bash
# Installed on the control plane and all workers: container runtime + kubeadm/kubelet/kubectl.
# Environment variables are passed in from the Vagrantfile.
set -euo pipefail
: "${K8S_VERSION:?K8S_VERSION must be set by the Vagrantfile}"
: "${INSTALL_DOCKER:?INSTALL_DOCKER must be set by the Vagrantfile}"
export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
echo "Provisioning for architecture: ${ARCH}"

# Disable swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Kernel modules and sysctl settings required by Kubernetes (persist across reboots)
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

apt-get update
apt-get install -y ca-certificates curl gnupg apt-transport-https

# Docker's apt repo (provides containerd.io, and Docker itself if wanted)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list

# Kubernetes apt repo (key and repo use the same version)
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update

# containerd (from Docker's repo, so it doesn't conflict with docker-ce)
apt-get install -y containerd.io
if [ "${INSTALL_DOCKER}" = "true" ]; then
  apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin
  usermod -aG docker vagrant   # takes effect on the next `vagrant ssh`
fi

# Configure containerd for Kubernetes: enable CRI and use the systemd cgroup driver
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  echo "ERROR: could not enable SystemdCgroup in /etc/containerd/config.toml" >&2
  exit 1
fi
systemctl restart containerd
systemctl enable containerd

# Kubernetes tooling
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
