# vagrant_examples

Vagrant files for local Kubernetes clusters.

| Directory | Description |
|---|---|
| [`Ubuntu2404-multiplatform`](Ubuntu2404-multiplatform) | Recommended. Linux and macOS hosts, amd64 and arm64, VirtualBox or VMware |
| [`Ubuntu2404`](Ubuntu2404) | Older Linux/VirtualBox version (Kubernetes 1.32) |
| [`Ubuntu2204`](Ubuntu2204) | Older Linux/VirtualBox version (Kubernetes 1.26). No longer provisions: it installs from the legacy `apt.kubernetes.io` repository, which has been shut down |

Each directory's provisioning scripts are in its `scripts/` folder (`common.sh` runs on every node, `master.sh` on the master, `worker.sh` on the workers) and are loaded by the Vagrantfile with `config.vm.provision :shell, path: ...`.

## Checks
---
GitHub Actions runs these on every pull request:

- **Lint** (`.github/workflows/lint.yml`)
  - Vagrantfile syntax (`ruby -c`) and that every provisioning script it references exists
  - `bash -n` and `shellcheck` on all provisioning scripts
  - `actionlint` on the workflows
  - `kubeconform` on the manifests in each `monitoring/` folder, using that directory's Kubernetes version
  - `markdownlint` and a link check (`lychee`) on the README files. Configured in `.markdownlint-cli2.jsonc` and `.github/lychee.toml`
- **Version checks** (`.github/workflows/versions.yml`). Runs when versions may have changed, and every Monday:
  - The Kubernetes apt repo for `K8S_VERSION` exists and that version is not end of life
  - The Calico manifests for `CALICO_VERSION` exist
  - Every container image in the `monitoring/` manifests exists
  - `renovate.json` is valid

To run the main checks locally:
```
brew install shellcheck actionlint kubeconform   # or your package manager
for f in */Vagrantfile; do ruby -c "$f"; done
shellcheck --severity=warning */scripts/*.sh .github/scripts/*.sh
actionlint
.github/scripts/kubeconform.sh
```

## Dependency updates
---
[Renovate](https://docs.renovatebot.com/) (`renovate.json`) opens pull requests when new versions are released for:
- Kubernetes (`K8S_VERSION`), Calico (`CALICO_VERSION`) and metrics-server, grouped into one pull request because they depend on each other
- k8sgpt in the README install instructions
- The GitHub Actions used by the workflows

Only `Ubuntu2404-multiplatform` is updated. The older directories are left as they are.

Renovate needs the [Renovate GitHub app](https://github.com/apps/renovate) installed on the repository by the repository owner.
