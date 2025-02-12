##Monitoring
---

## Helm
---
Helm installation is located [here](https://helm.sh/docs/intro/install/). It's essentially downloading the binary and putting it in the `/usr/local/bin/` directory.
Specific versions of Helm can be found [here](https://github.com/helm/helm/releases)
Helm will be used to install Prometheus

##Metrics Server
---
Install instructions are located here https://resources.realtheory.io/docs/how-to-install-or-upgrade-the-metrics-server

To download the latest version
```
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

To download a specific version
```
wget https://github.com/kubernetes-sigs/metrics-server/releases/download/<version>/components.yaml
```

Once downloaded you will need to modify the `components.yaml` file. The following will need to be added:
```
- --kubelet-insecure-tls
```

In this directory is a working version of the components.yaml file

## Prometheus
---
Installation directions are located [here](https://resources.realtheory.io/docs/how-to-install-or-upgrade-prometheus)
First add the Prometheus Helm repository
```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
```

Then install the latest version
```
helm install prometheus prometheus-community/prometheus
```

To install a specific version
```
helm install prometheus prometheus-community/prometheus --version <version>
```
