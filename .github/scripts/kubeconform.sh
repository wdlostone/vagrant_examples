#!/usr/bin/env bash
# Validate each directory's Kubernetes manifests (e.g. monitoring/components.yaml)
# against the Kubernetes version that directory's Vagrantfile installs.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Kubernetes minor version (e.g. "1.37") a directory installs, or empty if unknown
k8s_minor() {
  local dir=$1 v=""
  # Multiplatform style: K8S_VERSION = ENV.fetch("K8S_VERSION", "1.37")
  if [ -f "$dir/Vagrantfile" ]; then
    v=$(grep -oE 'ENV\.fetch\("K8S_VERSION", "[0-9]+\.[0-9]+"\)' "$dir/Vagrantfile" \
      | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)
  fi
  # Older style: hardcoded pkgs.k8s.io repo line in scripts/common.sh
  if [ -z "$v" ] && [ -f "$dir/scripts/common.sh" ]; then
    v=$(grep -oE 'pkgs\.k8s\.io/core:/stable:/v[0-9]+\.[0-9]+/deb/ /' "$dir/scripts/common.sh" \
      | grep -oE '[0-9]+\.[0-9]+' | tail -n1 || true)
  fi
  echo "$v"
}

status=0
found=0
for dir in */; do
  dir=${dir%/}
  mapfile -t manifests < <(find "$dir" -path '*/monitoring/*' \( -name '*.yaml' -o -name '*.yml' \) | sort)
  [ "${#manifests[@]}" -eq 0 ] && continue
  found=1

  minor=$(k8s_minor "$dir")
  if [ -z "$minor" ]; then
    echo "::error::Could not determine the Kubernetes version for ${dir}"
    status=1
    continue
  fi

  echo "== ${dir}: Kubernetes ${minor}"
  if ! kubeconform -strict -summary -kubernetes-version "${minor}.0" "${manifests[@]}"; then
    status=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "No manifests found"
fi
exit "$status"
