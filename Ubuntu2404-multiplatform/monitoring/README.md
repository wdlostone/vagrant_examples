## Monitoring
---

## Helm
---
Helm installation is located [here](https://helm.sh/docs/intro/install/). It's essentially downloading the binary and putting it in the `/usr/local/bin/` directory.
Specific versions of Helm can be found [here](https://github.com/helm/helm/releases).
Helm will be used to install Prometheus.

## Metrics Server
---
Install instructions are located [here](https://github.com/kubernetes-sigs/metrics-server#installation).

To download the latest version:
```
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

To download a specific version:
```
wget https://github.com/kubernetes-sigs/metrics-server/releases/download/<version>/components.yaml
```

Once downloaded, add the following argument to the `metrics-server` container in `components.yaml`. The kubelets in this cluster use self-signed certificates:
```
- --kubelet-insecure-tls
```

This directory has a working `components.yaml` (metrics-server v0.9.1) with that change already made. metrics-server 0.9.x supports Kubernetes 1.34 and newer; if you set `K8S_VERSION` lower than that, use the 0.8.x manifest instead (see the [compatibility matrix](https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix)). Check the [releases page](https://github.com/kubernetes-sigs/metrics-server/releases) for a newer version.
```
kubectl apply -f components.yaml
kubectl top nodes
```

## Prometheus
---
Installation directions are located [here](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus).
First add the Prometheus Helm repository:
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Then install the latest version:
```
helm install prometheus prometheus-community/prometheus
```

To install a specific version:
```
helm install prometheus prometheus-community/prometheus --version <version>
```
