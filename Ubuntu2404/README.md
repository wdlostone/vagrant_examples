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

## Adding k8sgpt
Basic documentation for k8sgpt is located [here](https://docs.k8sgpt.ai/getting-started/installation/)
Log into the Kubernetes master
```
vagrant ssh master
```

Download the bin
```
curl -sLO https://github.com/k8sgpt-ai/k8sgpt/releases/download/v0.3.48/k8sgpt_amd64.deb
```

Install the bin. This command will be the same if you are doing an update
```
sudo dpkg -i k8sgpt_amd64.deb
```

If you want tab completion you can
```
source <(k8sgpt completion bash)
```

### On the machine that has Ollama running
You will need to update the service for the Ollama service
```
sudo systemctl edit ollama.service. You will need to add the [Service] line and the line below it. Below is what it should look like
```
### Anything between here and the comment below will become the new contents of the file

[Service]
Environment="OLLAMA_HOST=0.0.0.0"

### Lines below this comment will be discarded
```

Afte that you will need to reload the daemon
```
systemctl daemon-reload
```

You will then need to restart the ollama service
```
sudo systemctl restart ollama
```

From here you should be able to test it to see if it is responding correctly. The IP address is the IP address for the server where Ollama is running
```
curl 192.168.254.39:11434
Ollama is running
```

### Back on the K8s master where k8sgpt is running

Add the backend of the Ollama server. The IP address is the one where the Ollama server is running
```
k8sgpt auth add --backend ollama --model llama3 --baseurl http://192.168.254.39:11434
```

Then set it as the default
```
k8sgpt auth default --provider ollama
```

You should then be able to test that it is working. With a broken pod, this is the query and result that I am getting
```
k8sgpt analyze --explain
 100% |███████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████████| (1/1, 21 it/min)        
AI Provider: ollama

0: Pod default/brokenpod()
- Error: Back-off pulling image "nginx:unknown_version": ErrImagePull: rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:unknown_version": failed to resolve reference "docker.io/library/nginx:unknown_version": docker.io/library/nginx:unknown_version: not found
Error: Unable to pull nginx image with unknown version due to not found error.

Solution: 
1. Check if the image exists on Docker Hub.
2. If not, update the image tag to a valid one (e.g., "nginx:latest" or "nginx:1.20").
3. Apply the changes to your Kubernetes deployment configuration file.
```

To test to see if the K8s master can reach the Ollama server you can run
```
curl http://192.168.254.39:11434/api/generate -d '{
  "model": "llama3",
  "prompt": "Why is the sky blue?"
}'
```

### Activating Trivy with k8sgpt
```
k8sgpt integration activate trivy
```

Sample querry
```
k8sgpt analyze --filter ConfigAuditReport | head -15
```

To get the full analysis of the system
```
k8sgpt analyze --explain
```

