#!/usr/bin/env bash
# Runs on the master as the vagrant user: kubeadm init, kubectl config, Calico, join.sh.
# Environment variables are passed in from the Vagrantfile.
set -euo pipefail
: "${MASTER_IP:?MASTER_IP must be set by the Vagrantfile}"
: "${POD_CIDR:?POD_CIDR must be set by the Vagrantfile}"
: "${NODE_CIDR:?NODE_CIDR must be set by the Vagrantfile}"
: "${CALICO_VERSION:?CALICO_VERSION must be set by the Vagrantfile}"
JOIN_FILE=/vagrant/join.sh
rm -f "${JOIN_FILE}"

# Pin the kubelet to the private network address (not the NAT interface)
echo "KUBELET_EXTRA_ARGS=--node-ip=${MASTER_IP}" | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Start the cluster
sudo kubeadm init \
  --apiserver-advertise-address="${MASTER_IP}" \
  --pod-network-cidr="${POD_CIDR}" \
  --node-name master

# Configure kubectl for the vagrant user
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# Install Calico. Node address autodetection is pinned to the private network
# so Calico doesn't pick the hypervisor's NAT interface (same IP on every node).
# Calico 3.30+ ships the operator CRDs in a separate manifest.
CALICO_MANIFESTS="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests"
if curl -fsI "${CALICO_MANIFESTS}/operator-crds.yaml" >/dev/null; then
  kubectl create -f "${CALICO_MANIFESTS}/operator-crds.yaml"
fi
kubectl create -f "${CALICO_MANIFESTS}/tigera-operator.yaml"
kubectl wait --for=condition=Established --timeout=120s crd/installations.operator.tigera.io crd/apiservers.operator.tigera.io
kubectl create -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - name: default-ipv4-ippool
      blockSize: 26
      cidr: ${POD_CIDR}
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
    nodeAddressAutodetectionV4:
      cidrs:
      - ${NODE_CIDR}
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

# Calico 3.30+ observability components (flow aggregator + Whisker UI),
# matching upstream's default custom-resources.yaml
if kubectl get crd goldmanes.operator.tigera.io whiskers.operator.tigera.io >/dev/null 2>&1; then
  kubectl create -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Goldmane
metadata:
  name: default
---
apiVersion: operator.tigera.io/v1
kind: Whisker
metadata:
  name: default
EOF
fi

# Write the join command last, so workers only see it once the master is ready
sudo kubeadm token create --print-join-command | tee "${JOIN_FILE}.tmp" > /dev/null
chmod +x "${JOIN_FILE}.tmp"
mv "${JOIN_FILE}.tmp" "${JOIN_FILE}"
echo "Join command written to ${JOIN_FILE}"
