#!/usr/bin/env bash
OUTPUT_FILE=/vagrant/join.sh
rm -rf $OUTPUT_FILE

# Start cluster
sudo kubeadm init --apiserver-advertise-address=10.0.0.10 --pod-network-cidr=192.168.0.0/16 | grep -E -- "kubeadm join|--discovery-token-ca-cert-hash" > ${OUTPUT_FILE}
chmod +x $OUTPUT_FILE

# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Fix kubelet IP
echo 'Environment="KUBELET_EXTRA_ARGS=--node-ip=10.0.0.10"' | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Restart the daemon
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Installing Calico
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
#kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml

# Installing flannel. The default install is using 10.244.0.0/16 for the IP range. This cluster is using something different so it needs to be changed. Flannel is the easier option
# wget https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# sed -i 's/10.244/192.168/g' kube-flannel.yml
# kubectl apply -f kube-flannel.yml

