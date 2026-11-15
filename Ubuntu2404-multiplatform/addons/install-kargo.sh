#!/usr/bin/env bash
# Install Kargo (and what it needs: Argo CD, cert-manager, Helm and the Kargo CLI).
#
# Run on the control plane as the vagrant user:
#   vagrant ssh control-plane -c /vagrant/addons/install-kargo.sh
# or automatically with `INSTALL_KARGO=true vagrant up` (see README.md).
#
# LAB USE ONLY. This uses Kargo's built-in admin account and a self-signed
# certificate. See https://docs.kargo.io/operator-guide/security/secure-configuration
#
# Safe to re-run: existing installs are upgraded in place and the admin
# password is kept.
set -euo pipefail

# renovate: datasource=github-releases depName=akuity/kargo
KARGO_VERSION="${KARGO_VERSION:-v1.12.5}"
# renovate: datasource=github-releases depName=cert-manager/cert-manager
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.5}"
# renovate: datasource=github-releases depName=helm/helm
HELM_VERSION="${HELM_VERSION:-v3.22.1}"
KARGO_NODEPORT="${KARGO_NODEPORT:-31444}"

# SHA-256 of each download. Update these whenever the versions above change
# (the "Version checks" workflow fails until they match).
# The variables below are read indirectly by checksum_for(), which shellcheck can't follow
# shellcheck disable=SC2034
HELM_SHA256_amd64=896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea
# shellcheck disable=SC2034
HELM_SHA256_arm64=4c29e286b279d170fa048ddfc3e4e83dcd069ca9c52102766ba672d7149e694d
# shellcheck disable=SC2034
KARGO_CLI_SHA256_amd64=18b2e313b646a3d2f54bef1f1dca14e209d8199d3fc5b94ce125d76df49b3b67
# shellcheck disable=SC2034
KARGO_CLI_SHA256_arm64=8efa60de964e95e56484c96ab7b848def9735b0281b63a715bccc125ae5e9122

ADMIN_SECRET=kargo-admin-account            # holds the password hash and token signing key
PASSWORD_FILE="${HOME}/.kargo-admin-password" # never under /vagrant: that's the host's git checkout

ARCH="$(dpkg --print-architecture)"         # amd64 or arm64
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

log() { echo "==> $*"; }

# Download $1 to $2 and check it against the SHA-256 in $3
download_verified() {
  curl -fsSL -o "$2" "$1"
  echo "$3  $2" | sha256sum -c --quiet - || { echo "ERROR: checksum mismatch for $1" >&2; exit 1; }
}

# Value of the variable named "<prefix>_<arch>"
checksum_for() { local var="$1_${ARCH}"; echo "${!var:?no checksum for ${ARCH}}"; }

# 32 random letters and digits
random_string() { local raw; raw=$(openssl rand -base64 48 | tr -d "=+/"); echo "${raw:0:32}"; }

# --- Argo CD ------------------------------------------------------------------
# Kargo works best with Argo CD; install it first if it isn't there yet
if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
  log "Argo CD is already installed"
else
  "${SCRIPT_DIR}/install-argocd.sh"
fi

# --- Helm ---------------------------------------------------------------------
if helm version --short 2>/dev/null | grep -q "^${HELM_VERSION}+"; then
  log "Helm ${HELM_VERSION} is already installed"
else
  log "Installing Helm ${HELM_VERSION}"
  download_verified "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" \
    "${WORK_DIR}/helm.tar.gz" "$(checksum_for HELM_SHA256)"
  tar -xzf "${WORK_DIR}/helm.tar.gz" -C "${WORK_DIR}"
  sudo install -m 0755 "${WORK_DIR}/linux-${ARCH}/helm" /usr/local/bin/helm
fi

# --- Kargo CLI ----------------------------------------------------------------
if kargo version --client 2>/dev/null | grep -q "${KARGO_VERSION}"; then
  log "Kargo CLI ${KARGO_VERSION} is already installed"
else
  log "Installing the Kargo CLI ${KARGO_VERSION}"
  download_verified "https://github.com/akuity/kargo/releases/download/${KARGO_VERSION}/kargo-linux-${ARCH}" \
    "${WORK_DIR}/kargo" "$(checksum_for KARGO_CLI_SHA256)"
  sudo install -m 0755 "${WORK_DIR}/kargo" /usr/local/bin/kargo
fi

# --- cert-manager -------------------------------------------------------------
log "Installing cert-manager ${CERT_MANAGER_VERSION}"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
kubectl -n cert-manager wait --for=condition=Available deployment --all --timeout=300s

# --- Admin account secret -----------------------------------------------------
# The password hash and signing key go in a Secret (not on the helm command line),
# as Kargo's secure configuration guide recommends.
kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f -
if kubectl -n kargo get secret "${ADMIN_SECRET}" >/dev/null 2>&1; then
  log "Keeping the existing Kargo admin password"
else
  log "Generating the Kargo admin password and token signing key"
  password=$(random_string)
  signing_key=$(random_string)
  password_hash=$(kargo hash-password --password "${password}")
  # Passed on stdin so the values don't appear in the process list
  kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ADMIN_SECRET}
  namespace: kargo
type: Opaque
stringData:
  ADMIN_ACCOUNT_PASSWORD_HASH: '${password_hash}'
  ADMIN_ACCOUNT_TOKEN_SIGNING_KEY: '${signing_key}'
EOF
  (umask 077 && printf '%s\n' "${password}" > "${PASSWORD_FILE}")
  unset password signing_key password_hash
fi

# --- Kargo --------------------------------------------------------------------
log "Installing Kargo ${KARGO_VERSION} (this can take a few minutes)"
helm upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version "${KARGO_VERSION#v}" \
  --namespace kargo \
  --set api.secret.name="${ADMIN_SECRET}" \
  --set api.service.type=NodePort \
  --set api.service.nodePort="${KARGO_NODEPORT}" \
  --wait --timeout 10m

# --- Done ---------------------------------------------------------------------
cp_ip=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

if [ -f "${PASSWORD_FILE}" ]; then
  password_hint="saved in ${PASSWORD_FILE} on the control plane (readable only by the vagrant user)"
else
  password_hint="set when Kargo was first installed (${PASSWORD_FILE} was not found)"
fi

cat <<EOF

Kargo ${KARGO_VERSION} is ready. LAB USE ONLY: see the warning in README.md.
  URL:       https://${cp_ip}:${KARGO_NODEPORT}/   (self-signed certificate)
  Login:     admin account
  Password:  ${password_hint}
  CLI:       kargo login https://${cp_ip}:${KARGO_NODEPORT} --admin --insecure-skip-tls-verify
EOF
