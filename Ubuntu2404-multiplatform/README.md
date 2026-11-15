## Kubernetes cluster on Ubuntu 24.04 (Linux and macOS hosts)

This Vagrantfile brings up a local Kubernetes cluster with one master and two workers (by default). It runs on **Linux and macOS** hosts, on **amd64 (Intel/AMD)** and **arm64 (Apple Silicon)**, with **VirtualBox** or **VMware**.

It replaces the separate Linux ([`../Ubuntu2404`](../Ubuntu2404)) and macOS versions with one file.

| Node    | IP         |
|---------|------------|
| master  | 10.0.0.10  |
| worker1 | 10.0.0.11  |
| worker2 | 10.0.0.12  |

### What's installed
- `containerd.io` from Docker's apt repo, using the systemd cgroup driver
- `kubeadm`, `kubelet` and `kubectl` from pkgs.k8s.io (held at the installed version)
- [Calico](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises) as the CNI, pinned to the private network so it doesn't use the hypervisor's NAT interface
- Docker for development (optional, see `INSTALL_DOCKER`). See the [Docker install docs](https://docs.docker.com/engine/install/ubuntu/) and [post-install docs](https://docs.docker.com/engine/install/linux-postinstall/)

### Changes from the old `Ubuntu2404` Vagrantfile
- **Architecture-aware.** Detects `arm64`/`amd64` instead of hardcoding amd64.
- **Public box.** Uses `bento/ubuntu-24.04` (amd64 and arm64, VirtualBox and VMware). Set `K8S_BOX` to use a different box, e.g. `m_boxes/ubuntu_2404_server`.
- **Bridged network is optional.** Set `BRIDGE_IFACE` (e.g. `eno1`) instead of editing the file.
- **No containerd package conflict.** Only `containerd.io` is installed, not Ubuntu's `containerd` as well.
- **Matching Kubernetes repo versions.** The repo key and repo URL both use `K8S_VERSION`.
- **Settings survive a reboot.** Kernel modules are written to `/etc/modules-load.d/`.
- **The kubelet node IP is set before `kubeadm init`.**
- **Fails fast.** Scripts run with `set -euo pipefail`.
- **Safer worker joins.** Workers wait for the master's `join.sh`, so parallel `vagrant up` is safe. `join.sh` is deleted when the master is destroyed.

## Prerequisites
---
1. Install [Vagrant](https://developer.hashicorp.com/vagrant/install).
   - **macOS** (Homebrew):
     ```
     brew tap hashicorp/tap
     brew trust hashicorp/tap      # newer Homebrew versions require trusting third-party taps
     brew install --cask hashicorp/tap/hashicorp-vagrant
     ```
   - **Linux**: use HashiCorp's apt/dnf repo or the package from the install page.
2. Install a hypervisor (pick one):
   - **Recommended on macOS: VMware Fusion 13+ (free) with the `vagrant-vmware-desktop` plugin.** See the setup steps below.
   - **VirtualBox 7.1 or newer.** On macOS, 7.1 is the first version that supports Apple Silicon (`brew install --cask virtualbox`).
   - **VMware Workstation (Linux) or VMware Fusion 13+ (macOS).** You'll also need the [Vagrant VMware Utility](https://developer.hashicorp.com/vagrant/install/vmware) and the plugin:
     ```
     vagrant plugin install vagrant-vmware-desktop
     ```
     On macOS the utility can be installed with `brew install --cask vagrant-vmware-utility`.

### VirtualBox only: allow the 10.0.0.x range
By default, VirtualBox only allows host-only addresses in `192.168.56.0/21` ([docs](https://www.virtualbox.org/manual/ch06.html#network_hostonly)). To allow this cluster's addresses, create `/etc/vbox/networks.conf` with:
```
* 10.0.0.0/8 192.168.0.0/16
* 2001::/64
```
For example:
```
sudo mkdir -p /etc/vbox
printf '* 10.0.0.0/8 192.168.0.0/16\n* 2001::/64\n' | sudo tee /etc/vbox/networks.conf
```
VMware doesn't need this.

## Usage
---
```
cd Ubuntu2404-multiplatform

# VirtualBox
vagrant up --provider virtualbox

# or VMware (recommended on macOS: Fusion + vagrant-vmware-desktop)
vagrant up --provider vmware_desktop

# Linux host, with the master also bridged to the LAN on eno1
BRIDGE_IFACE=eno1 vagrant up --provider virtualbox

vagrant ssh master
kubectl get nodes -o wide
```

Tear down:
```
vagrant destroy -f
```

## Configuration
---
Set any of these as environment variables before running `vagrant up`, e.g. `WORKER_COUNT=1 NODE_MEMORY=3072 vagrant up`.

| Variable          | Default               | Notes |
|-------------------|-----------------------|-------|
| `WORKER_COUNT`    | `2`                   | Number of worker nodes |
| `NODE_MEMORY`     | `4096`                | MB per VM. Three VMs at 4 GB need 12 GB free |
| `NODE_CPUS`       | `2`                   | vCPUs per VM. kubeadm needs at least 2 |
| `K8S_BOX`         | `bento/ubuntu-24.04`  | Must have a build for your CPU and provider |
| `K8S_BOX_VERSION` | latest                | Pin a box version |
| `NETWORK_PREFIX`  | `10.0.0`              | Master is `.10`, workers `.11`, `.12`, … |
| `BRIDGE_IFACE`    | unset                 | Adds a bridged NIC on the master. Linux: e.g. `eno1` (see `ip link`). macOS: e.g. `"en0: Wi-Fi"` (see `networksetup -listallhardwareports`) |
| `K8S_VERSION`     | `1.37`                | Kubernetes minor version from pkgs.k8s.io. The latest patch for that minor version is installed |
| `CALICO_VERSION`  | `v3.33.0`             | Tested by Calico with Kubernetes 1.35–1.37. Check the [Calico requirements](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements) if you change `K8S_VERSION` |
| `POD_CIDR`        | `192.168.0.0/16`      | Must not overlap `NETWORK_PREFIX` or your LAN |
| `INSTALL_DOCKER`  | `true`                | Install Docker on the nodes for development. Not needed for Kubernetes |

Use the same variables for every `vagrant` command in a session (e.g. `export WORKER_COUNT=1`). Otherwise Vagrant may not see machines you created earlier.

## Troubleshooting
---
- **"The box ... doesn't support the provider / architecture".** Pick a different box with `K8S_BOX` that has a build for your CPU and provider.
- **VirtualBox IP range error.** See the `networks.conf` step above.
- **"Specified host network could not be found" with `BRIDGE_IFACE`.** The interface name must match the host's exactly.
- **A worker added more than 24 hours after the cluster was created can't join.** The kubeadm token has expired. Generate a new join command:
  ```
  vagrant ssh master -c "sudo kubeadm token create --print-join-command | sudo tee /vagrant/join.sh"
  vagrant provision worker3
  ```
- **Nodes stay `NotReady`.** Check Calico with `kubectl get pods -n calico-system` on the master.
- **Calico's Whisker UI** (flow logs) is installed by default. To open it, run `kubectl port-forward -n calico-system service/whisker 8081:8081 --address 0.0.0.0` on the master, then browse to http://10.0.0.10:8081.

## Monitoring
---
Metrics Server and Prometheus setup is in [`monitoring/README.md`](monitoring/README.md).

## Adding k8sgpt
---
Basic documentation for k8sgpt is located [here](https://docs.k8sgpt.ai/getting-started/installation/).

Log into the Kubernetes master:
```
vagrant ssh master
```

Download and install the package for the VM's architecture. Check the [releases page](https://github.com/k8sgpt-ai/k8sgpt/releases) for the latest version. The same commands work for upgrades:
```
K8SGPT_VERSION=v0.3.48
ARCH=$(dpkg --print-architecture)
curl -sLO "https://github.com/k8sgpt-ai/k8sgpt/releases/download/${K8SGPT_VERSION}/k8sgpt_${ARCH}.deb"
sudo dpkg -i "k8sgpt_${ARCH}.deb"
```

For tab completion:
```
source <(k8sgpt completion bash)
```

### Making Ollama reachable from the cluster
In the examples below, replace `<OLLAMA_HOST_IP>` with the address of the machine running Ollama. If Ollama runs on the host machine itself, that's usually `10.0.0.1` (the host's address on the private network).

**Ollama on Linux (systemd).** Edit the service:
```
sudo systemctl edit ollama.service
```
Add these lines between the comments in the editor:
```
### Anything between here and the comment below will become the new contents of the file

[Service]
Environment="OLLAMA_HOST=0.0.0.0"

### Lines below this comment will be discarded
```
Then reload and restart:
```
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

**Ollama on macOS (the app).** Don't use `systemctl`. Run this, then quit and reopen the Ollama app:
```
launchctl setenv OLLAMA_HOST "0.0.0.0"
```

Test it from the master:
```
curl http://<OLLAMA_HOST_IP>:11434
Ollama is running
```
```
curl http://<OLLAMA_HOST_IP>:11434/api/generate -d '{
  "model": "llama3",
  "prompt": "Why is the sky blue?"
}'
```

### Configuring k8sgpt to use Ollama
On the master, add the Ollama backend and make it the default:
```
k8sgpt auth add --backend ollama --model llama3 --baseurl http://<OLLAMA_HOST_IP>:11434
k8sgpt auth default --provider ollama
```

Test it. With a broken pod, the output looks like this:
```
k8sgpt analyze --explain
AI Provider: ollama

0: Pod default/brokenpod()
- Error: Back-off pulling image "nginx:unknown_version": ErrImagePull: ... docker.io/library/nginx:unknown_version: not found
Error: Unable to pull nginx image with unknown version due to not found error.

Solution:
1. Check if the image exists on Docker Hub.
2. If not, update the image tag to a valid one (e.g., "nginx:latest" or "nginx:1.20").
3. Apply the changes to your Kubernetes deployment configuration file.
```

### Activating Trivy with k8sgpt
```
k8sgpt integration activate trivy
```

Sample query:
```
k8sgpt analyze --filter ConfigAuditReport | head -15
```

Full analysis of the cluster:
```
k8sgpt analyze --explain
```

## Using Kubescape
---
Kubescape scans the cluster for vulnerabilities and misconfigurations. Documentation is located [here](https://kubescape.io/docs/install-cli/).

```
sudo add-apt-repository ppa:kubescape/kubescape
sudo apt-get update
sudo apt-get install -y kubescape
```

## ArgoCD
---
Installation directions are located [here](https://argo-cd.readthedocs.io/en/stable/getting_started/).
```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Allow external access with a NodePort:
```
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
```

Find the port:
```
kubectl -n argocd get svc argocd-server
NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
argocd-server   NodePort   10.103.31.196   <none>        80:31373/TCP,443:30455/TCP   66m
```
In this example the HTTPS port is `30455`.

Get the initial `admin` password:
```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Browse to `https://10.0.0.10:<port>/` from the host. If you set `BRIDGE_IFACE`, you can also use the master's LAN address (find it with `ip addr show` on the master).
