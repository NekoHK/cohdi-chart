# CoHDI Helm Chart

# Introduction

The **CoHDI Helm chart** deploys the CoHDI system — an integration layer for CDI management and device configuration in Kubernetes.

# Getting Started

## Obtain the Chart

Add the CoHDI Helm repository:

```bash
helm repo add cohdi_helm <link>
helm repo update
```

Or clone directly:
```bash
git clone <link>
cd cohdi_helm
```

## Creating Certificates (Mock Environment)

These steps show how to create mock CA and server certificates with OpenSSL for testing.

1. Create an OpenSSL Config File
   Save as `openssl.conf`:
   ```
   [ req ]
   default_bits       = 2048
   distinguished_name = req_distinguished_name
   x509_extensions    = v3_ca
   prompt             = no

   [ req_distinguished_name ]
   C  = JP
   ST = Tokyo
   L  = Default City
   O  = Default Company Ltd
   CN = cdimgr.localdomain

   [ v3_ca ]
   subjectAltName = @alt_names

   [ alt_names ]
   DNS.1 = cdimgr.localdomain
   IP.1  = 192.168.1.101
   ```

2. Create a CA Private Key and Certificate
   ```bash
   openssl req -x509 -newkey rsa:2048 -days 365      -keyout ca.key -out ca.crt -config openssl.conf -nodes
   ```

3. Create a Server Private Key and CSR
   ```bash
   openssl req -new -newkey rsa:2048 -keyout server.key      -out server.csr -config openssl.conf -nodes
   ```

4. Sign the Server Certificate with the CA
   ```bash
   openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key      -CAcreateserial -out server.crt -days 365 -extensions v3_ca      -extfile openssl.conf
   ```

## Configure values.yaml
Update `./values.yaml` with your settings.


## Installing the GPU driver
* add repo

```bash
sudo zypper ar https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sle15
sudo zypper --gpg-auto-import-keys refresh
```

* install Open Kernel driver KMP

```bash
sudo zypper install -y --auto-agree-with-licenses nv-prefer-signed-open-driver
```

* utilities&ext install

```bash
version=`rpm -qa --queryformat '%{VERSION}\n' nv-prefer-signed-open-driver | cut -d_ -f1 | sort -u | tail -n1`
sudo zypper install -y --auto-agree-with-licenses nvidia-compute-utils-G06=$version nvidia-persistenced=$version
```

* check

```bash
sudo reboot
nvidia-smi
```

Note: At this point, if you attach a suitable GPU to the agent node
      from LCC, the GPU will be visible in lspc | grep NVI and
      nvidia-smi.

* Configure nvidia-smi to run without sudo

```bash
sudo usermod -aG video,render $USER
```

* Add the path to lspci

```bash
echo 'export PATH="$PATH:/sbin"' >> ~/.bashrc
source ~/.bashrc
```



## Deploying the NVIDIA GPU Operator (server node)
Deploy the GPU Operator by referring to the following document.
```
https://docs.rke2.io/advanced#deploy-nvidia-operator
```

```bash
kubectl -n kube-system edit helmchart gpu-operator
```

After all the created Pods are Running, edit the yaml using the above
command as follows to turn off components other than GFD.
```
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: gpu-operator
  namespace: kube-system
spec:
  repo: https://helm.ngc.nvidia.com/nvidia
  chart: gpu-operator
  targetNamespace: gpu-operator
  createNamespace: true
  valuesContent: |-
    toolkit:
      enabled: false
      env:
      - name: CONTAINERD_SOCKET
        value: /run/k3s/containerd/containerd.sock
    driver:
      enabled: false
    devicePlugin:
      enabled: false
    dcgm:
      enabled: false
    dcgmExporter:
      enabled: false
    nodeStatusExporter:
      enabled: false
    migManager:
      enabled: false
    cdi:
      enabled: false
    ccManager:
      enabled: false
    gdrcopy:
      enabled: false
    kataManager:
      enabled: false
    psa:
      enabled: false
    sandboxDevicePlugin:
      enabled: false
    sandboxWorkloads:
      enabled: false
    vfioManager:
      enabled: false
    vgpuDeviceManager:
      enabled: false
    vgpuManager:
      enabled: false
```

# Build and Test

## Install/Upgrade CoHDI
```bash
helm upgrade --install cohdi . -n cohdi --create-namespace
```

## Check status:
```bash
kubectl get pods -A
```

## Uninstall:
```bash
helm uninstall cohdi -n cohdi
```

# Contribute

## Issues:
### Errors during CoHDI installation such as:

```
Error: Unable to continue with install: ClusterRole "cdi-dra" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "cohdi"; annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "cohdi"
helm.go:84: [debug] ClusterRole "cdi-dra" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "cohdi"; annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "cohdi"
Unable to continue with install
```

Invalid ownership metadata; annotation validation error
Helm refuses to “adopt” pre-existing resources unless they already carry Helm ownership metadata that matches the release which is being installed.

### Current fix (using kubectl CLI):
There is a need to run the code below before CoHDI installation:
```bash
PREFIXES='^(composable-resource-operator-|cdi-|dynamic-device-scaler-)'
for kind in clusterrole clusterrolebinding validatingwebhookconfiguration mutatingwebhookconfiguration; do
  kubectl get "$kind" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'   | grep -E "$PREFIXES"   | while read -r name; do
      echo "Adopting $kind/$name"
      kubectl label "$kind" "$name" app.kubernetes.io/managed-by=Helm --overwrite
      kubectl annotate "$kind" "$name"         meta.helm.sh/release-name=cohdi         meta.helm.sh/release-namespace=cohdi         --overwrite
    done
done
```

### An idea for a better solution:

Maybe there is a possibility to embed this fix inside CoHDI `.yaml` files.
