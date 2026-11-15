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
# sudo mkdir /etc/systemd/system/kubelet.service.d
# sudo touch /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
# echo 'Environment="KUBELET_EXTRA_ARGS=--node-ip=10.0.0.10"' | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo rm /etc/default/kubelet
sudo touch /etc/default/kubelet
echo "KUBELET_EXTRA_ARGS=--node-ip=10.0.0.10" | sudo tee -a /etc/default/kubelet

# Restart the daemon
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Installing Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/custom-resources.yaml

# Installing flannel. The default install is using 10.244.0.0/16 for the IP range. This cluster is using something different so it needs to be changed. Flannel is the easier option
# wget https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
# sed -i 's/10.244/192.168/g' kube-flannel.yml
# kubectl apply -f kube-flannel.yml

# Modify kube-proxy so that Mettallb will work
# kubectl get configmap kube-proxy -n kube-system -o yaml | \
# sed -e "s/mode: \"\"/mode: \"ipvs\"/" | \
# kubectl apply --create-annotation -f - -n kube-system

# Modify kube-proxy so that Metallb will work pt2
# kubectl get configmap kube-proxy -n kube-system -o yaml | \
# sed -e "s/strictARP: false/strictARP: true/" | \
# kubectl apply -f - -n kube-system

# Install MetalLB
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Install the metallb configmap so the correct IP addresses are used
# kubectl apply -f - <<EOF
# apiVersion: metallb.io/v1beta1
# kind: IPAddressPool
# metadata:
#   name: first-pool
#   namespace: metallb-system
# spec:
#   addresses:
#   - 10.0.0.20-10.0.0.30
# ---
# apiVersion: metallb.io/v1beta1
# kind: L2Advertisement
# metadata:
#   name: example
#   namespace: metallb-system
# EOF

