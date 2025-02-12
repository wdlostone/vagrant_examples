## This Vagrantfile will bring up a Kubernetes cluster locally

## Things to know
---
VirtualBox only allows Ip addresses in the 192.168.56.0/21 range to be assigned to host-only adapters. VirtualBox documentation can be found [here](https://www.virtualbox.org/manual/ch06.html#network_hostonly). The cluster is using IP address from 10.0.0.10 to 10.0.0.12. To fix this, in `/etc/vbox/networks.conf` you'll need to add
```
* 10.0.0.0/8 192.168.0.0/16
* 2001::/64
```

## CNI
By default the Vagrantfile is using Calico as the CNI. 
Calico quickstart documentation can be located [here](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart)
The onprem documentation is located [here](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

## Docker
Docker is being installed for development
Docker install documentation for Ubuntu 24.04 is located [here](https://docs.docker.com/engine/install/ubuntu/)
Post installation documentation is located [here](https://docs.docker.com/engine/install/linux-postinstall/). This will allow Docker to run without root priviledges