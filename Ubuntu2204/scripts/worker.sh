#!/usr/bin/env bash
# NODE_IP is passed in from the Vagrantfile
sudo /vagrant/join.sh
# echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" | sudo tee /etc/sysconfig/kubelet
echo "Environment=\"KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}\"" | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

sudo systemctl daemon-reload
sudo systemctl restart kubelet
