#!/usr/bin/env bash
# Install Argo CD on the cluster and expose it on fixed NodePorts.
#
# Run on the control plane as the vagrant user:
#   vagrant ssh control-plane -c /vagrant/addons/install-argocd.sh
# or automatically with `INSTALL_ARGOCD=true vagrant up` (see README.md).
#
# Safe to re-run: it re-applies the pinned version.
set -euo pipefail

# renovate: datasource=github-releases depName=argoproj/argo-cd
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.6.1}"
ARGOCD_HTTP_NODEPORT="${ARGOCD_HTTP_NODEPORT:-30080}"
ARGOCD_HTTPS_NODEPORT="${ARGOCD_HTTPS_NODEPORT:-30443}"

log() { echo "==> $*"; }

# --- Preflight ----------------------------------------------------------------
if ! kubectl get nodes >/dev/null 2>&1; then
  echo "ERROR: kubectl can't reach the cluster. Run this on the control plane as the vagrant user." >&2
  exit 1
fi

# Argo CD's pods can't run on the control plane (it's tainted), so wait for a Ready worker
log "Waiting for at least one Ready worker node"
for _ in $(seq 1 60); do
  ready_workers=$( { kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null || true; } \
    | awk '$2 == "Ready"' | wc -l)
  [ "${ready_workers}" -gt 0 ] && break
  sleep 10
done
if [ "${ready_workers}" -eq 0 ]; then
  echo "ERROR: no Ready worker nodes. Bring the workers up first: vagrant up" >&2
  exit 1
fi

# --- Install ------------------------------------------------------------------
log "Installing Argo CD ${ARGOCD_VERSION}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side is required: some Argo CD CRDs are too large for client-side apply
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

log "Exposing the Argo CD server on NodePorts ${ARGOCD_HTTP_NODEPORT} (http) and ${ARGOCD_HTTPS_NODEPORT} (https)"
kubectl -n argocd patch svc argocd-server -p "{\"spec\":{\"type\":\"NodePort\",\"ports\":[
  {\"port\":80,\"nodePort\":${ARGOCD_HTTP_NODEPORT}},
  {\"port\":443,\"nodePort\":${ARGOCD_HTTPS_NODEPORT}}]}}"

log "Waiting for Argo CD to be ready (this can take a few minutes)"
kubectl -n argocd wait --for=condition=Available deployment --all --timeout=600s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=600s

# --- Done ---------------------------------------------------------------------
cp_ip=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

cat <<EOF

Argo CD ${ARGOCD_VERSION} is ready.
  URL:       https://${cp_ip}:${ARGOCD_HTTPS_NODEPORT}/   (self-signed certificate)
  Username:  admin
  Password:  on the control plane, run:
             kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
EOF
