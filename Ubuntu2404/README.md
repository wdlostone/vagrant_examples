## This will bring up a Kubernetes cluster locally

## Things to know
VirtualBox only allows Ip addresses in the 192.168.56.0/21 range to be assigned to host-only adapters. VirtualBox documentation can be found [here](https://www.virtualbox.org/manual/ch06.html#network_hostonly). The cluster is using IP address from 10.0.0.10 to 10.0.0.12. To fix this, in `/etc/vbox/networks.conf` you'll need to add
```
* 10.0.0.0/8 192.168.0.0/16
* 2001::/64
```

By default it is not using a CNI, so that needs to be done. To use Calico,
ssh into the master and then run the commands
```
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml
```

## Monitoring
The Prometheus Helm chart is located here: https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus
Below is how to install Prometheus with Helm:
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```
The Helm chart will install:
- alertmanager
- kube-state-metrics
- prometheus-node-exporter
- prometheus-pushgateway