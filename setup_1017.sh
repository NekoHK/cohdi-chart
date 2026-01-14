#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

# set english langauge
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

RUN_SERVER_STEPS=${RUN_SERVER_STEPS:-true}
RUN_AGENT_STEPS=${RUN_AGENT_STEPS:-false}

# TEST_NS="${TEST_NS:-tensorflow-test}"

# Pattern 2 (registry) settings (from doc)
REG_HOST="${REG_HOST:-10.38.251.227:5000}"
REG_USER="${REG_USER:-cdiadmin}"
REG_PASS="${REG_PASS:-cdiadmin}"
CA_CERT_SRC="${CA_CERT_SRC:-/usr/share/pki/trust/anchors/cohdi-ca.crt}"
# CDI_DRA_TAG="v20-c7f88bd"         # choose tag (doc: updated regularly)
# CDI_CRO_TAG="gdctest"         # choose tag (doc: updated regularly)
# CDI_DDS_TAG="test"         # choose tag (doc: updated regularly)
GPU_OPERATOR_VERSION="v25.10.1"
NVIDIA_DRA_DRIVER_GPU_VERSION="25.3.2"
NVIDIA_DRA_DRIVER_GPU_IMAGE_TAG="v25.3.2"

# Kube config (RKE2)
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/rke2/rke2.yaml}"

CURRENT_STEP="(not started)"
trap 'echo -e "\nFAILED during: ${CURRENT_STEP}\nAborting."; exit 1' ERR

sudo -E test -x /var/lib/rancher/rke2/bin/kubectl || { echo "kubectl not found at /var/lib/rancher/rke2/bin"; ls -l /var/lib/rancher/rke2/bin; exit 1; }
sudo -E ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/bin/kubectl
sudo -E which kubectl
sudo -E kubectl version --client=true
sudo -E install -d -m 700 /root/.kube
sudo -E install -m 644 /etc/rancher/rke2/rke2.yaml /root/.kube/config

# ================= STEP 1 — K8s ENV (SERVER) =================
if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
  CURRENT_STEP="Step 1: Configure RKE2 feature-gates (server)"
  echo -e "\nBEGIN: ${CURRENT_STEP}"

  # 1.1 RKE2 via Rancher

  # 1.2 Create/update config.yaml with feature-gates
  sudo -E mkdir -p /etc/rancher/rke2
  sudo -E install -m 600 /dev/null /etc/rancher/rke2/config.yaml
  sudo -E tee /etc/rancher/rke2/config.yaml > /dev/null <<'YAML'
  kube-apiserver-arg:
    - "runtime-config=resource.k8s.io/v1=true,resource.k8s.io/v1beta1=true,resource.k8s.io/v1beta2=true,resource.k8s.io/v1alpha3=true"
    - "feature-gates=DRADeviceBindingConditions=true,DRAResourceClaimDeviceStatus=true,DRADeviceTaints=true"
  kube-controller-manager-arg:
    - "feature-gates=DRADeviceBindingConditions=true,DRAResourceClaimDeviceStatus=true,DRADeviceTaints=true"
  kube-scheduler-arg:
    - "feature-gates=DRADeviceBindingConditions=true,DRAResourceClaimDeviceStatus=true,DRADeviceTaints=true"
YAML

  # 1.2 Restart rke2-server
  sudo -E systemctl restart rke2-server || true
  echo "rke2 restarted"

  # 1.3 Verify flags
  ps -ef | grep kube-apiserver | grep runtime-config  >/dev/null
  ps -ef | grep kube-apiserver | grep feature-gates   >/dev/null
  ps -ef | grep kube-controller-manager | grep feature-gates >/dev/null
  ps -ef | grep kube-scheduler | grep feature-gates   >/dev/null

  echo "SUCCESS: ${CURRENT_STEP}"
fi

# ================ STEP 2 — NVIDIA DRIVER & TOOLKIT (SERVER & AGENT) ================
CURRENT_STEP="Step 2: NVIDIA driver & container toolkit (agent)"
echo -e "\nBEGIN: ${CURRENT_STEP}"

sudo zypper rm -y '*nvidia*'

# # (2-1) Add repo + install Open Kernel driver KMP
sudo -E zypper ar -f https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sle15 || true
sudo -E zypper --gpg-auto-import-keys -n refresh
sudo -E zypper -n install --auto-agree-with-licenses nv-prefer-signed-open-driver

# utilities & persistenced
version="$(rpm -qa --queryformat '%{VERSION}\n' nv-prefer-signed-open-driver | cut -d_ -f1 | sort -u | tail -n1)"
sudo -E zypper -n install --auto-agree-with-licenses "nvidia-compute-utils-G06=${version}" "nvidia-persistenced=${version}"

# (2-1) check (skip reboot to keep non-interactive)
sudo -E nvidia-smi || true

sudo -E usermod -aG video,render "$USER" || true

# add /sbin to PATH for lspci
grep -qs 'export PATH="$PATH:/sbin"' "$HOME/.bashrc" || echo 'export PATH="$PATH:/sbin"' >> "$HOME/.bashrc"
source ~/.bashrc

if [[ "${RUN_AGENT_STEPS}" == "true" ]]; then

  # # Detach GPU (safe no-ops if not present)
  # sudo -E nvidia-smi -i 0 -pm 0 || true
  # sudo -E rm -f /dev/nvidia0 || true
  # sudo -E modprobe -r nvidia_drm  || true
  # sudo -E modprobe -r nvidia_uvm  || true
  #
  # if nvidia-smi -L | grep -q "GPU 0"; then
  #     RAW=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0)
  #     BDF=${RAW/00000000/0000}
  #     BDF=$(echo "$BDF" | tr "[:upper:]" "[:lower:]")
  #     echo "RAW = $RAW"
  #     echo "BDF = $BDF"
  #
  #     if [[ -d "/sys/bus/pci/devices/$BDF" ]]; then
  #       echo "Detaching GPU $BDF..."
  #       sudo systemctl stop nvidia-persistenced || true
  #       sleep 2
  #       echo 1 | sudo -E tee "/sys/bus/pci/devices/$BDF/remove"
  #     else
  #       echo "Device path not found: /sys/bus/pci/devices/$BDF"
  #     fi
  #   else
  #     echo "No GPU found. Skipping PCI detach."
  # fi

  # (2-2) Container toolkit + CDI file
  sudo -E zypper ar -f "https://nvidia.github.io/libnvidia-container/stable/rpm/"nvidia-container-toolkit.repo || true
  sudo -E zypper --gpg-auto-import-keys -n install -y nvidia-container-toolkit
  sudo -E mkdir -p /etc/cdi
  sudo -E nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

  # nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0 | sed -E "s/^00000000/0000/"

  # (2-3) Podman & deps
  # sudo -E SUSEConnect -p sle-module-containers/15.7/x86_64 || true
  # sudo -E zypper -n refresh
  # sudo -E zypper -n install podman conmon runc fuse-overlayfs slirp4netns
  # podman --version >/dev/null

  # (2-4) CUDA test inside container (non-interactive variant)
  # podman run --rm --device nvidia.com/gpu=all --security-opt=label=disable \
  #   registry.suse.com/bci/bci-base:latest \
  #   bash -lc '
  #     set -e
  #     zypper -n ar http://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sle15-sp6 || true
  #     zypper --gpg-auto-import-keys -n refresh
  #     zypper -n install update-alternatives cuda-libraries-13-0 cuda-demo-suite-12-9
  #     /usr/local/cuda-12.9/extras/demo_suite/deviceQuery || true
  #   '
fi
echo "SUCCESS: ${CURRENT_STEP}"

# ================ STEP 3 — GPU OPERATOR (SERVER) ================
if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
  CURRENT_STEP="Step 3: Deploy NVIDIA GPU Operator (GFD only)"
  echo -e "\nBEGIN: ${CURRENT_STEP}"

  sudo chmod 644 /etc/rancher/rke2/rke2.yaml

  cat <<EOF | kubectl -n kube-system apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: gpu-operator
  namespace: kube-system
spec:
  repo: https://helm.ngc.nvidia.com/nvidia
  chart: gpu-operator
  version: ${GPU_OPERATOR_VERSION}
  targetNamespace: gpu-operator
  createNamespace: true
  valuesContent: |-
    toolkit:
      env:
      - name: CONTAINERD_SOCKET
        value: /run/k3s/containerd/containerd.sock
EOF

  # Wait for the gpu-operator pods to do their initial job
  echo -e "\nWaiting 60s for the gpu-operator to initialize"
  sleep 60

  # Non-interactive equivalent of kubectl edit: apply HelmChart CR w/ GFD only
  cat <<EOF | kubectl -n kube-system apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: gpu-operator
  namespace: kube-system
spec:
  repo: https://helm.ngc.nvidia.com/nvidia
  chart: gpu-operator
  version: ${GPU_OPERATOR_VERSION}
  targetNamespace: gpu-operator
  createNamespace: true
  valuesContent: |-
    toolkit:
      enabled: false
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
    gfd:
      enabled: true
EOF

  echo "SUCCESS: ${CURRENT_STEP}"
fi

# ================ STEP 4 — NVIDIA DRA DRIVER (SERVER) ================
if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
  CURRENT_STEP="Step 4: Deploy NVIDIA DRA Driver"
  echo -e "\nBEGIN: ${CURRENT_STEP}"

  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true

  helm repo update

  helm upgrade -i nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
      --namespace nvidia-dra-driver-gpu \
      --create-namespace \
      --version=${NVIDIA_DRA_DRIVER_GPU_VERSION} \
      --set image.tag=${NVIDIA_DRA_DRIVER_GPU_IMAGE_TAG} \
      --set nvidiaDriverRoot=/ \
      --set maskNvidiaDriverParams=false \
      --set gpuResourcesEnabledOverride=true \
      --wait

  echo "SUCCESS: ${CURRENT_STEP}"
fi

# ================ STEP 5 — WORKLOAD POD (AGENT) ================
# if [[ "${RUN_AGENT_STEPS}" == "true" ]]; then
#   CURRENT_STEP="Step 5: Create ResourceClaimTemplate + workload pod"
#   echo -e "\nBEGIN: ${CURRENT_STEP}"
#
#   GPU_UUID=$(sudo -E nvidia-smi --query-gpu=gpu_uuid --format=csv,noheader | sed -n '1p')
#   echo "GPU_UUID = $GPU_UUID"
#
#   if [[ -z "${GPU_UUID}" ]]; then
#     echo "GPU_UUID is required for Step 5 (from 'nvidia-smi -L' on the agent). Set GPU_UUID=GPU-... and re-run."
#     exit 1
#   fi
#
#   # (1) Namespace (idempotent)
#   kubectl get ns "${TEST_NS}" >/dev/null 2>&1 || kubectl create namespace "${TEST_NS}"
#
#   # (2) ResourceClaimTemplate (doc yaml with UUID)
#   cat > /tmp/single-gpu-rct.yaml <<EOF
# apiVersion: resource.k8s.io/v1beta2
# kind: ResourceClaimTemplate
# metadata:
#   name: single-gpu-gpu3
#   namespace: ${TEST_NS}
# spec:
#   spec:
#     devices:
#       requests:
#       - name: single-gpu-gpu3
#         exactly:
#           deviceClassName: gpu.nvidia.com
#           count: 1
#           selectors:
#           - cel:
#              expression: |
#                 device.attributes["gpu.nvidia.com"].uuid == "${GPU_UUID}"
# EOF
#   kubectl apply -f /tmp/single-gpu-rct.yaml
#
#   # (3) Workload Pod (doc yaml)
#   cat > /tmp/test-gpu-pod.yaml <<'EOF'
# apiVersion: v1
# kind: Pod
# metadata:
#   namespace: tensorflow-test
#   name: test-gpu-gpu3
# spec:
#   restartPolicy: Never
#   containers:
#   - name: training
#     image: nvcr.io/nvidia/tensorflow:25.02-tf2-py3
#     command:
#     - python
#     - -c
#     - |
#       import tensorflow as tf
#       import numpy as np
#       print("Num GPUs Available: ", len(tf.config.list_physical_devices("GPU")))
#
#       num_train_samples = 60000
#       num_test_samples = 10000
#       img_rows = 28
#       img_cols = 28
#       num_classes = 10
#
#       x_train = np.random.randint(0, 256, size=(num_train_samples, img_rows, img_cols), dtype=np.uint8)
#       x_test = np.random.randint(0, 256, size=(num_test_samples, img_rows, img_cols), dtype=np.uint8)
#
#       y_train = np.random.randint(0, num_classes, size=num_train_samples, dtype=np.uint8)
#       y_test = np.random.randint(0, num_classes, size=num_test_samples, dtype=np.uint8)
#
#       x_train, x_test = x_train / 255.0, x_test / 255.0
#       model = tf.keras.models.Sequential(
#         [
#             tf.keras.layers.Flatten(input_shape=(28, 28)),
#             tf.keras.layers.Dense(128, activation="relu"),
#             tf.keras.layers.Dropout(0.2),
#             tf.keras.layers.Dense(10),
#         ]
#       )
#       model.compile(
#         optimizer="adam",
#         loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
#         metrics=["accuracy"],
#       )
#       model.fit(x_train, y_train, epochs=300000)
#       model.evaluate(x_test, y_test)
#     resources:
#       claims:
#       - name: gpu
#   resourceClaims:
#   - name: gpu
#     resourceClaimTemplateName: single-gpu-gpu3
# EOF
#   kubectl apply -f /tmp/test-gpu-pod.yaml
#
#   echo "SUCCESS: ${CURRENT_STEP}"
# fi

# ================ STEP 5 - REGISTRY (SERVER) ================
    CURRENT_STEP="Step 5 Pattern 2: Configure private registry"
    echo -e "\nBEGIN: ${CURRENT_STEP}"

    # (1) Install Docker on server node
    # sudo -E zypper -n refresh
    # sudo -E zypper -n install docker
    # sudo -E usermod -aG docker "$USER" || true
    # docker version || true   # may require re-login; non-fatal
    # sudo -E chmod 0644 /usr/share/pki/trust/anchors/cohdi-ca.crt || true
    # sudo -E update-ca-certificates
    # sudo -E systemctl restart docker

    # docker login
    # docker login "${REG_HOST}" -u "${REG_USER}" -p "${REG_PASS}"

    # (1) Write /etc/rancher/rke2/registries.yaml
    sudo -E mkdir -p /etc/rancher/rke2/certs.d/"${REG_HOST}"
    if [[ -n "${CA_CERT_SRC}" && -r "${CA_CERT_SRC}" ]]; then
      sudo -E install -D -m0644 "${CA_CERT_SRC}" /etc/rancher/rke2/certs.d/"${REG_HOST}"/cohdi-ca.crt
    fi
    sudo -E tee /etc/rancher/rke2/registries.yaml > /dev/null <<EOF
mirrors:
  "${REG_HOST}":
    endpoint:
      - "https://${REG_HOST}"
configs:
  "${REG_HOST}":
    tls:
      ca_file: /etc/rancher/rke2/certs.d/${REG_HOST}/cohdi-ca.crt
    auth:
      username: ${REG_USER}
      password: ${REG_PASS}
EOF

    # (3) Restart rke2 server & agent
    sudo -E systemctl restart rke2-server || true
    # sudo -E systemctl restart rke2-agent || true  #RR: Last time I tried this it couldn't restart, but after machine reboot it worked fine

    # (4) ctr pulls
    #RR: needs to be run with sudo, but with sudo it doesn't recognize the path to crt so I used the full path in the command
    # sudo chmod 644 /etc/rancher/rke2/rke2.yaml
    # sudo -E /var/lib/rancher/rke2/bin/ctr -a /run/k3s/containerd/containerd.sock -n k8s.io i pull --tlscacert /etc/rancher/rke2/certs.d/${REG_HOST}/cohdi-ca.crt --local --user "${REG_USER}:${REG_PASS}" "${REG_HOST}/dds:${CDI_DDS_TAG}" || true
    # sudo -E /var/lib/rancher/rke2/bin/ctr -a /run/k3s/containerd/containerd.sock -n k8s.io i pull --tlscacert /etc/rancher/rke2/certs.d/${REG_HOST}/cohdi-ca.crt --local --user "${REG_USER}:${REG_PASS}" "${REG_HOST}/cdi-operator:${CDI_CRO_TAG}" || true
    # sudo -E /var/lib/rancher/rke2/bin/ctr -a /run/k3s/containerd/containerd.sock -n k8s.io i pull --tlscacert /etc/rancher/rke2/certs.d/${REG_HOST}/cohdi-ca.crt --local --user "${REG_USER}:${REG_PASS}" "${REG_HOST}/cdi-dra:${CDI_DRA_TAG}" || true

    echo "SUCCESS: ${CURRENT_STEP}"

 # ================ STEP 7 — DEPLOY COHDI COMPONENTS (SERVER) ================
  # cd step_07_manual_deployment || exit 1
  # chmod +x step_07.sh && ./step_07.sh; cd ..

echo -e "\nDONE: All selected steps completed."
