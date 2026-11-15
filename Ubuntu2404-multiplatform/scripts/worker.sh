#!/usr/bin/env bash
# Runs on each worker as root: waits for join.sh from the master and joins the cluster.
# Environment variables are passed in from the Vagrantfile.
set -euo pipefail
: "${NODE_IP:?NODE_IP must be set by the Vagrantfile}"
JOIN_FILE=/vagrant/join.sh

# Wait for the master to publish the join command (covers parallel `vagrant up`)
for _ in $(seq 1 90); do
  [ -x "${JOIN_FILE}" ] && break
  echo "Waiting for ${JOIN_FILE} from the master..."
  sleep 10
done
if [ ! -x "${JOIN_FILE}" ]; then
  echo "ERROR: ${JOIN_FILE} not found. Bring up the master first: vagrant up master" >&2
  exit 1
fi

echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl daemon-reload
systemctl restart kubelet

bash "${JOIN_FILE}"
