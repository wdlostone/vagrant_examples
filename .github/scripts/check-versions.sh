#!/usr/bin/env bash
# Check that the versions pinned in the repo still exist upstream and are supported:
#   - Kubernetes (K8S_VERSION) pkgs.k8s.io repo exists and the minor version is not end of life
#   - Calico (CALICO_VERSION) manifests exist
#   - Every container image in */monitoring/*.yaml exists in its registry
#   - Add-on scripts (addons/*.sh): Argo CD, cert-manager and Kargo versions exist,
#     Argo CD is tested with K8S_VERSION, and the pinned download checksums match
#
# Only Ubuntu2404-multiplatform is checked for Kubernetes and Calico; the older
# directories pin versions that are known to be past end of life.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

VAGRANTFILE=Ubuntu2404-multiplatform/Vagrantfile
WARN_DAYS=${WARN_DAYS:-60} # warn this many days before end of life
status=0

fail() { echo "::error::$*"; status=1; }
warn() { echo "::warning::$*"; }
ok()   { echo "ok       $*"; }

url_exists() { curl -fsSL --retry 3 --retry-all-errors -o /dev/null "$1"; }

# GitHub API GET, authenticated when GITHUB_TOKEN is set (avoids the low anonymous rate limit)
gh_api() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsSL --retry 3 -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/$1"
  else
    curl -fsSL --retry 3 "https://api.github.com/$1"
  fi
}

# Default value of ENV.fetch("NAME", "value") in the Vagrantfile
vagrant_default() {
  grep -oE "ENV\.fetch\(\"$1\", \"[^\"]+\"\)" "$VAGRANTFILE" | head -n1 | cut -d'"' -f4
}

# --- Kubernetes ---------------------------------------------------------------
K8S_VERSION=$(vagrant_default K8S_VERSION)
[ -n "$K8S_VERSION" ] || { fail "K8S_VERSION default not found in $VAGRANTFILE"; exit 1; }

repo="https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key"
if url_exists "$repo"; then ok "Kubernetes ${K8S_VERSION} apt repo"; else fail "Kubernetes ${K8S_VERSION} apt repo not found: $repo"; fi

# End-of-life data from https://endoflife.date (warn only if the service is unreachable)
if eol_json=$(curl -fsSL --retry 3 --retry-all-errors https://endoflife.date/api/kubernetes.json); then
  eol=$(jq -r --arg c "$K8S_VERSION" '.[] | select(.cycle == $c) | .eol' <<<"$eol_json")
  latest=$(jq -r '[.[].cycle] | sort_by(split(".") | map(tonumber)) | last' <<<"$eol_json")
  today=$(date -u +%F)
  if [ -z "$eol" ]; then
    warn "Kubernetes ${K8S_VERSION} not listed on endoflife.date yet"
  elif [[ "$eol" < "$today" || "$eol" == "$today" ]]; then
    fail "Kubernetes ${K8S_VERSION} reached end of life on ${eol}. Update K8S_VERSION in ${VAGRANTFILE}"
  elif [[ "$eol" < "$(date -u -d "+${WARN_DAYS} days" +%F)" ]]; then
    warn "Kubernetes ${K8S_VERSION} reaches end of life on ${eol}"
  else
    ok "Kubernetes ${K8S_VERSION} supported until ${eol}"
  fi
  if [ "$latest" != "$K8S_VERSION" ]; then
    echo "::notice::Kubernetes ${latest} is available (pinned: ${K8S_VERSION})"
  fi
else
  warn "Could not reach endoflife.date; skipping the Kubernetes end-of-life check"
fi

# --- Calico -------------------------------------------------------------------
CALICO_VERSION=$(vagrant_default CALICO_VERSION)
[ -n "$CALICO_VERSION" ] || { fail "CALICO_VERSION default not found in $VAGRANTFILE"; exit 1; }

calico="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests"
for m in tigera-operator.yaml operator-crds.yaml; do
  if url_exists "${calico}/${m}"; then ok "Calico ${CALICO_VERSION} ${m}"; else fail "Calico ${CALICO_VERSION} manifest not found: ${calico}/${m}"; fi
done

# --- Container images ---------------------------------------------------------
mapfile -t images < <(grep -hoE '^[[:space:]]*image:[[:space:]]*[^[:space:]]+' */monitoring/*.y*ml 2>/dev/null \
  | awk '{print $2}' | tr -d '"'"'" | sort -u)
for img in "${images[@]}"; do
  if docker manifest inspect "$img" >/dev/null 2>&1; then ok "image $img"; else fail "image not found: $img"; fi
done

# --- Add-on scripts -----------------------------------------------------------
ADDONS=Ubuntu2404-multiplatform/addons

# Default value of NAME="${NAME:-value}" in an add-on script
addon_default() {
  grep -oE "^$1=\"\\\$\{$1:-[^}]+\}\"" "$2" | head -n1 | sed -E 's/.*:-([^}]+)\}"/\1/'
}
# Value of NAME=value in an add-on script
addon_value() { grep -oE "^$1=[0-9a-f]+" "$2" | head -n1 | cut -d= -f2; }

ARGOCD_VERSION=$(addon_default ARGOCD_VERSION "$ADDONS/install-argocd.sh")
KARGO_VERSION=$(addon_default KARGO_VERSION "$ADDONS/install-kargo.sh")
CERT_MANAGER_VERSION=$(addon_default CERT_MANAGER_VERSION "$ADDONS/install-kargo.sh")
HELM_VERSION=$(addon_default HELM_VERSION "$ADDONS/install-kargo.sh")
for v in ARGOCD_VERSION KARGO_VERSION CERT_MANAGER_VERSION HELM_VERSION; do
  [ -n "${!v}" ] || fail "$v not found in $ADDONS"
done

argocd="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}"
if url_exists "${argocd}/manifests/install.yaml"; then ok "Argo CD ${ARGOCD_VERSION} install.yaml"; else fail "Argo CD ${ARGOCD_VERSION} install.yaml not found"; fi

# Argo CD publishes the Kubernetes versions each release is tested with
if tested=$(curl -fsSL --retry 3 "${argocd}/docs/operator-manual/tested-kubernetes-versions.md"); then
  argocd_minor=$(echo "${ARGOCD_VERSION#v}" | cut -d. -f1,2)
  row=$(grep -E "^\| *${argocd_minor//./\\.} *\|" <<<"$tested" || true)
  if grep -qE "v${K8S_VERSION//./\\.}([^0-9]|$)" <<<"$row"; then
    ok "Argo CD ${argocd_minor} is tested with Kubernetes ${K8S_VERSION}"
  else
    warn "Argo CD ${argocd_minor} is not listed as tested with Kubernetes ${K8S_VERSION} (${row:-no entry})"
  fi
else
  warn "Could not fetch Argo CD's tested Kubernetes versions"
fi

cm="https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
if url_exists "$cm"; then ok "cert-manager ${CERT_MANAGER_VERSION} manifest"; else fail "cert-manager manifest not found: $cm"; fi

# Kargo chart tag on ghcr.io (anonymous pull token)
if token=$(curl -fsSL "https://ghcr.io/token?scope=repository:akuity/kargo-charts/kargo:pull" | jq -r .token) \
  && curl -fsSL -o /dev/null -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://ghcr.io/v2/akuity/kargo-charts/kargo/manifests/${KARGO_VERSION#v}"; then
  ok "Kargo chart ${KARGO_VERSION#v}"
else
  fail "Kargo chart ${KARGO_VERSION#v} not found on ghcr.io"
fi

# Pinned checksums must match the official ones, so a version bump without a
# checksum update fails here rather than on someone's cluster
for arch in amd64 arm64; do
  want=$(addon_value "HELM_SHA256_${arch}" "$ADDONS/install-kargo.sh")
  got=$(curl -fsSL --retry 3 "https://get.helm.sh/helm-${HELM_VERSION}-linux-${arch}.tar.gz.sha256sum" | awk '{print $1}' || true)
  if [ -n "$got" ] && [ "$want" = "$got" ]; then ok "Helm ${HELM_VERSION} ${arch} checksum"; else fail "Helm ${HELM_VERSION} ${arch}: HELM_SHA256_${arch} in install-kargo.sh should be ${got:-unknown}"; fi

  want=$(addon_value "KARGO_CLI_SHA256_${arch}" "$ADDONS/install-kargo.sh")
  got=$(gh_api "repos/akuity/kargo/releases/tags/${KARGO_VERSION}" \
    | jq -r --arg n "kargo-linux-${arch}" '.assets[] | select(.name == $n) | .digest // empty' | sed 's/^sha256://' || true)
  if [ -n "$got" ] && [ "$want" = "$got" ]; then ok "Kargo CLI ${KARGO_VERSION} ${arch} checksum"; else fail "Kargo CLI ${KARGO_VERSION} ${arch}: KARGO_CLI_SHA256_${arch} in install-kargo.sh should be ${got:-unknown}"; fi
done

exit "$status"
