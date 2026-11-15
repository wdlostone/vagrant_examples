#!/usr/bin/env bash
# Check that the versions pinned in the repo still exist upstream and are supported:
#   - Kubernetes (K8S_VERSION) pkgs.k8s.io repo exists and the minor version is not end of life
#   - Calico (CALICO_VERSION) manifests exist
#   - Every container image in */monitoring/*.yaml exists in its registry
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

exit "$status"
