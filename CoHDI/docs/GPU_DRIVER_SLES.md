# Installing the GPU Driver on SLES

## RKE2 Environment Setup Prerequisites

- The RKE2 environment must be ready and running properly.
- A SUSE subscription must be attached to the target worker node.
- A compatible NVIDIA GPU must be attached to the target worker node.

Refer to the following documentation to install the GPU driver and container
toolkit on the worker node.

```
https://documentation.suse.com/suse-ai/1.0/html/NVIDIA-GPU-driver-on-SLES/index.html
```

The following steps are required.

- Add the NVIDIA package repository
- Install the NVIDIA driver and various dependencies
- Install the NVIDIA container toolkit
- Generate the CDI configuration YAML file (/etc/cdi/nvidia.yaml)

[reference]

## Add NVIDIA CUDA repository

```bash
sudo zypper ar https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sle15
sudo zypper --gpg-auto-import-keys refresh
```

## Install Open Kernel driver KMP

```bash
sudo zypper install -y --auto-agree-with-licenses nv-prefer-signed-open-driver
```

## Install utilities and extensions

```bash
version=$(rpm -qa --queryformat '%{VERSION}\n' nv-prefer-signed-open-driver | cut -d_ -f1 | sort -u | tail -n1)
sudo zypper install -y --auto-agree-with-licenses nvidia-compute-utils-G06=$version nvidia-persistenced=$version
```

## Deploying the NVIDIA GPU Operator

Deploy the GPU Operator in the Control Plane by referring to the following
document.

```
https://docs.rke2.io/add-ons/gpu_operators#operator-installation
```

After all the created Pods are Running, edit the ClusterPolicy using
`kubectl edit clusterpolicy` command as follows to turn off components other
than GFD.

```
apiVersion: v1
items:
  spec:
    ccManager:
      enabled: true -> false
    cdi:
      enabled: true -> false
    dcgm:
      enabled: true -> false
    dcgmExporter:
      enabled: true -> false
      serviceMonitor:
        enabled: true -> false
    devicePlugin:
      enabled: true -> false
    driver:
      enabled: true -> false
      rdma:
        enabled: true -> false
    gdrcopy:
      enabled: true -> false
    gds:
      enabled: true -> false
    gfd:
      enabled: true
    kataManager:
      enabled: true -> false
    migManager:
      enabled: true -> false
    nodeStatusExporter:
      enabled: true -> false
    psa:
      enabled: true -> false
    sandboxWorkloads:
      enabled: true -> false
    toolkit:
      enabled: true -> false
    vfioManager:
      enabled: true -> false
    vgpuDeviceManager:
      enabled: true -> false
    vgpuManager:
      enabled: true -> false
```

## Installing DRA

Install DRA in the Control Plane by referring to the following steps.

- Prepare a helm binary for installation.
- Git clone the latest nvidia-dra-driver-gpu into /home/rancher/test.
- Run following command.

```
helm upgrade -i \
    --create-namespace \
    --namespace nvidia-dra-driver-gpu \
    nvidia-dra-driver-gpu \
    /home/rancher/test/k8s-dra-driver-gpu/deployments/helm/nvidia-dra-driver-gpu \
    --set nvidiaDriverRoot=/ \
    --set maskNvidiaDriverParams=false \
    --set gpuResourcesEnabledOverride=true \
    --wait
```

After installation, please confirm that the following ResourceSlice objects
exist.

```
Every 2.0s: kubectl get resourceslices.resource.k8s.io

NAME                                               NODE               DRIVER                      POOL               AGE
controller-qctvl-compute-domain.nvidia.com-dwnbc   controller-qctvl   compute-domain.nvidia.com   controller-qctvl   3m47s
controller-qctvl-gpu.nvidia.com-v8xh2              controller-qctvl   gpu.nvidia.com              controller-qctvl   3m47s
```

## Check installation

```bash
sudo reboot
sudo nvidia-smi
```

Note: At this point, if you attach a suitable GPU to the agent node from LCC,
the GPU will be visible in /sbin/lspci | grep NVIDIA and nvidia-smi.
