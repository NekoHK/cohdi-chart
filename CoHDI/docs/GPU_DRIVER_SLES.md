# Installing the GPU Driver on SLES

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
