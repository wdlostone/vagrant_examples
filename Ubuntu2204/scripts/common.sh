#!/usr/bin/env bash

# disable swap and add kernel settings
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Reload the changes from above
sudo sysctl --system

# Installing the dependencies so containerd can be installed
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

# Install the docker repository
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository --yes "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Install containerd
sudo apt update
sudo apt install -y containerd.io

# Configure containerd to use systemd as the cgroup
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Install the Kubernetes Repos
sudo curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo apt-add-repository --yes "deb http://apt.kubernetes.io/ kubernetes-xenial main"
# sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-jammy main"
sudo apt update

# Install Kubernetes
sudo apt install -y kubelet=1.26.0-00 kubeadm=1.26.0-00 kubectl=1.26.0-00
sudo apt-mark hold kubelet=1.26.0-00 kubeadm=1.26.0-00 kubectl=1.26.0-00

# Installing Docker. This is not needed for the cluster to work correctly. This is only added if wanting to run Docker on the nodes
# Adding tools to download and install Docker
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add the GPG key for the official Docker repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Adding the Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

# Installing docker 
sudo apt install -y docker-ce=5:23.0.1-1~ubuntu.22.04~jammy

# Putting the user in the docker group so sudo isn't needed
sudo usermod -aG docker ${USER}
newgrp docker

