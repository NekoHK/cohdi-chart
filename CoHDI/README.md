# CoHDI Helm Chart

# Introduction

The **CoHDI Helm chart** deploys the CoHDI system - an integration
layer for CDI management and device configuration in Kubernetes.

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

## Creating Certificates (for webhook)

These steps show how to create CA and server certificates for webhook
with OpenSSL.

1. Create a CA Private Key and Certificate

```bash
openssl req -x509 -newkey rsa:2048 -days 365 \
    -keyout ca.key -out ca.crt -config openssl.conf -nodes
```

2. Create a Server Private Key and CSR

```bash
openssl req -new -newkey rsa:2048 -keyout server.key \
    -out server.csr -config openssl.conf -nodes
```

3. Sign the Server Certificate with the CA

```bash
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out server.crt -days 365 -extensions v3_ca \
    -extfile openssl.conf
```

## Installing the GPU driver

The GPU driver installation process depends on your environment.

- [SLES Instructions](./docs/GPU_DRIVER_SLES.md)
- [RHEL Instructions](./docs/GPU_DRIVER_RHEL.md) (in preparation)

### Check installation

```bash
sudo reboot
sudo nvidia-smi
```

Note: At this point, if you attach a suitable GPU to the agent node
      from LCC, the GPU will be visible in /sbin/lspci | grep NVIDIA
      and nvidia-smi.

## Configure values.yaml

There are some pieces of information that need to be entered by the
user.  Update `values.yaml` with the settings.

The `values.yaml` that needs to be updated is below.

```
CoHDI/
  values.yaml (common to all components)
  charts/
    cdi_dra/
      values.yaml (for cdi_dra)
    cdi_operator/
      values.yaml (for cdi_operator)
    dds/
      values.yaml (for dds)
```

Below is a list of items that should be updated in `values.yaml`.

### Common `values.yaml` for all components

| Key                           | Description                                | Get  | Initial value                |
|:------------------------------|:-------------------------------------------|:----:|:-----------------------------|
| deviceInfo                    | Definition information for each device     | *7   |                              |
| fabricIdRange                 | CDI Fabric ID Range                        | *7   | "[0]"                        |
| username                      | Tenant administrator username              | *2   | "username"                   |
| password                      | Tenant administrator password              | *2   | "password"                   |
| realm                         | relm for token acquisition                 | *2   | ""                           |
| client_id                     | client_id for token acquisition            | *1   | "cdi"                        |
| client_secret                 | client_secret for token acquisition        | *1   | ""                           |
| CDI_ENDPOINT                  | CDI API server URL                         | *1   | "https://cdimgr.localdomain" |
| CLUSTER_ID                    | Cluster UUID                               | *6   | ""                           |
| TENANT_ID                     | Tenant UUID                                | *2   | ""                           |
| certificate                   | PEM-encoded CA certificate                 | *1   |                              |
| ip                            | CDI management IP address                  | *1   | 111.111.111.111              |
| hostnames                     | CDI admin hostname                         | *1   | cdimgr.localdomain           |

### `values.yaml` for cdi_dra

| Key                           | Description                                | Get  | Initial value                |
|:------------------------------|:-------------------------------------------|:----:|:-----------------------------|
| name                          | Container name                             | *5   | cdi-dra                      |
| image                         | Container image                            | *4   | ""                           |
| imagePullPolicy               | Container image fetch policy               | *4   | IfNotPresent                 |
| SCAN_INTERVAL                 | Loop processing interval (sec)             | *4   | "5s"                         |
| USE_CAPI_BMH                  | Availability of ClusterAPI and BMH         | *5   | "false"                      |
| USE_CM                        | Availability of CM (Cluster Manager)       | *5   | "false"                      |

### `values.yaml` for dds

| Key                           | Description                                | Get  | Initial value                |
|:------------------------------|:-------------------------------------------|:----:|:-----------------------------|
| name                          | Container name                             | *5   | dynamic-device-scaler        |
| image                         | Container image                            | *4   | ""                           |
| imagePullPolicy               | Container image fetch policy               | *4   | IfNotPresent                 |
| SCAN_INTERVAL                 | Interval (sec) of periodic timer events    | *4   | "10"                         |
| DEVICE_NO_REMOVAL_DURATION    | Time from last use of device until it can be detached | *4 | "10"                |
| DEVICE_NO_ALLOCATION_DURATION | Time from last use of device to reschedule | *4   | "10"                         |

### `values.yaml` for cdi_operator

| Key                           | Description                                | Get  | Initial value                |
|:------------------------------|:-------------------------------------------|:----:|:-----------------------------|
| name                          | Container name                             | *5   | composable-resource-operator |
| image                         | Container image                            | *4   | ""                           |
| imagePullPolicy               | Container image fetch policy               | *4   | IfNotPresent                 |
| caBundle                      | Webhook server CA certificate bundle       | *3   |                              |
| crt                           | TLS crt                                    | *3   |                              |
| key                           | TLS key                                    | *3   |                              |
| DEVICE_RESOURCE_TYPE          | Device resource type                       | *5   | "DRA"                        |
| CDI_PROVIDER_TYPE             | CDI provider type                          | *5   | "FTI_CDI"                    |
| FTI_CDI_API_TYPE              | FTI CDI API type                           | *5   | "FM"                         |

```
*1: Check with the CDI system administrator
*2: Issued by the system administrator
*3: User-created
*4: User can set it arbitrarily
*5: Cannot be changed
*6: Not required in RKE2 environment
*7: TBD
```

# Build and Test

## Install/Upgrade CoHDI

```bash
helm upgrade --install cohdi . -n cohdi --create-namespace
```

## Check status

```bash
kubectl get pods -A
```

## Uninstall

```bash
helm uninstall cohdi -n cohdi
```

# Contribute

## Issues

### Errors during CoHDI installation such as:

```
Error: Unable to continue with install: ClusterRole "cdi-dra" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata;
label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm";
annotation validation error: missing key "meta.helm.sh/release-name": must be set to "cohdi";
annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "cohdi"
helm.go:84: [debug] ClusterRole "cdi-dra" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata;
label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm";
annotation validation error: missing key "meta.helm.sh/release-name": must be set to "cohdi";
annotation validation error: missing key "meta.helm.sh/release-namespace": must be set to "cohdi"
Unable to continue with install
```

Invalid ownership metadata; annotation validation error
Helm refuses to "adopt" pre-existing resources unless they already carry Helm ownership metadata that matches the release which is being installed.

### Current fix (using kubectl CLI):

There is a need to run the code below before CoHDI installation.

```bash
PREFIXES='^(composable-resource-operator-|cdi-|dynamic-device-scaler-)'
for kind in clusterrole clusterrolebinding validatingwebhookconfiguration \
    mutatingwebhookconfiguration ; do
  kubectl get "$kind" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | \
      grep -E "$PREFIXES" | while read -r name ; do
    echo "Adopting $kind/$name"
    kubectl label "$kind" "$name" app.kubernetes.io/managed-by=Helm \
        --overwrite
    kubectl annotate "$kind" "$name" \
        meta.helm.sh/release-name=cohdi \
        meta.helm.sh/release-namespace=cohdi \
        --overwrite
  done
done
```

### An idea for a better solution

Maybe there is a possibility to embed this fix inside CoHDI `.yaml`
files.
