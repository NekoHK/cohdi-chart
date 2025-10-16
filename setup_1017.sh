#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

sudo -E test -x /var/lib/rancher/rke2/bin/kubectl || { echo "kubectl not found at /var/lib/rancher/rke2/bin"; ls -l /var/lib/rancher/rke2/bin; exit 1; }
sudo -E ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/bin/kubectl
sudo -E which kubectl  
sudo -E kubectl version --client=true
sudo -E install -d -m 700 /root/.kube
sudo -E install -m 600 /etc/rancher/rke2/rke2.yaml /root/.kube/config

sudo -E ln -sf /usr/local/bin/helm /usr/bin/helm
sudo -E which helm
sudo -E helm version --client

sudo -E install -d -m 700 /root/.kube
sudo -E install -m 600 /etc/rancher/rke2/rke2.yaml /root/.kube/config

sudo -E ln -sf /usr/local/bin/go /usr/bin/go


# ─────────────── USER TOGGLES ───────────────
RUN_SERVER_STEPS=${RUN_SERVER_STEPS:-true}   # run Steps 1,3,4,5,7 on SERVER
RUN_AGENT_STEPS=${RUN_AGENT_STEPS:-false}    # run Step 2 on AGENT

# Step 5 (workload test)
GPU_UUID="GPU-0f474061-439e-0f86-ce21-ca64c2ed8b0e"

TEST_NS="${TEST_NS:-tensorflow-test}"

# Step 6: pick Pattern 1 (build) or Pattern 2 (registry)
PATTERN="${PATTERN:-build}"

# Pattern 2 (registry) settings (from doc)
REG_HOST="${REG_HOST:-10.38.251.227:5000}"
REG_USER="${REG_USER:-cdiadmin}"
REG_PASS="${REG_PASS:-cdiadmin}"
CA_CERT_SRC="${CA_CERT_SRC:-}"               # optional path to cohdi-ca.crt to install
CDI_DRA_TAG="${CDI_DRA_TAG:-latest}"         # choose tag (doc: updated regularly)

# Kube config (RKE2)
# export KUBECONFIG="${KUBECONFIG:-/etc/rancher/rke2/rke2.yaml}"

CURRENT_STEP="(not started)"
trap 'echo -e "\n❌ FAILED during: ${CURRENT_STEP}\nAborting."; exit 1' ERR

# # ───────────────── STEP 1 — K8s ENV (SERVER) ─────────────────
# if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
#   CURRENT_STEP="Step 1: Configure RKE2 feature-gates (server)"
#   echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

#   # 1.1 RKE2 via Rancher (informational; no commands in doc)

#   # 1.2 Create/update config.yaml with feature-gates
#   mkdir -p /etc/rancher/rke2
#   install -m 600 /dev/null /etc/rancher/rke2/config.yaml
#   cat > /etc/rancher/rke2/config.yaml <<'YAML'
# kube-apiserver-arg:
#   - "runtime-config=resource.k8s.io/v1=true,resource.k8s.io/v1beta1=true,resource.k8s.io/v1beta2=true,resource.k8s.io/v1alpha3=true"
#   - "feature-gates=DRADeviceBindingConditions=true,DRAResourceClaimDeviceStatus=true,DRADeviceTaints=true"
# kube-controller-manager-arg:
#   - "feature-gates=DRADeviceBindingConditions=true,DRAResourceClaimDeviceStatus=true,DRADeviceTaints=true"
# kube-scheduler-arg:
#   - "feature-gates=DRADeviceBindingConditions=true,DRAResourceClaimDeviceStatus=true,DRADeviceTaints=true"
# YAML

#   # 1.2 Restart rke2-server
#   systemctl restart rke2-server

#   # 1.3 Verify flags
#   ps -ef | grep kube-apiserver | grep runtime-config  >/dev/null
#   ps -ef | grep kube-apiserver | grep feature-gates   >/dev/null
#   ps -ef | grep kube-controller-manager | grep feature-gates >/dev/null
#   ps -ef | grep kube-scheduler | grep feature-gates   >/dev/null

#   echo "✔ SUCCESS: ${CURRENT_STEP}"
# fi

# ──────────────── STEP 2 — NVIDIA DRIVER & TOOLKIT (AGENT) ────────────────
if [[ "${RUN_AGENT_STEPS}" == "true" ]]; then
  CURRENT_STEP="Step 2: NVIDIA driver & container toolkit (agent)"
  echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

  # # (2-1) Add repo + install Open Kernel driver KMP
  # sudo -E zypper ar -f https://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sle15 || true
  # sudo -E zypper --gpg-auto-import-keys -n refresh
  # sudo -E zypper -n install --auto-agree-with-licenses nv-prefer-signed-open-driver

  # utilities & persistenced
  version="$(rpm -qa --queryformat '%{VERSION}\n' nv-prefer-signed-open-driver | cut -d_ -f1 | sort -u | tail -n1)"
  sudo -E zypper -n install --auto-agree-with-licenses "nvidia-compute-utils-G06=${version}" "nvidia-persistenced=${version}"

  # (2-1) check (skip reboot to keep non-interactive)
  nvidia-smi || true

  sudo -E usermod -aG video,render "$USER" || true

  # add /sbin to PATH for lspci
  grep -qs 'export PATH="$PATH:/sbin"' "$HOME/.bashrc" || echo 'export PATH="$PATH:/sbin"' >> "$HOME/.bashrc"
  echo 'export PATH="$PATH:/sbin"' >> ~/.bashrc
  source ~/.bashrc

  # Detach GPU (safe no-ops if not present)
  nvidia-smi -i 0 -pm 0 || true
  sudo -E rm -f /dev/nvidia0 || true
  sudo -E modprobe -r nvidia_drm  || true
  sudo -E modprobe -r nvidia_uvm  || true

  # raw dry-run
  # sudo sh -c 'RAW=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0); \
  # BDF=${RAW/00000000/0000}; BDF=$(echo "$BDF" | tr "[:upper:]" "[:lower:]"); \
  # echo "Target path: /sys/bus/pci/devices/$BDF/remove"; \
  # ls -l "/sys/bus/pci/devices/$BDF"'

  RAW=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0)
  BDF=${RAW/00000000/0000}; BDF=$(echo "$BDF" | tr "[:upper:]" "[:lower:]")
  echo "RAW = $RAW"
  echo "BDF = $BDF"
  ls -ld "/sys/bus/pci/devices/$BDF" || { echo "Device path not found"; exit 1; }
 
  sudo sh -c '
  RAW=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0)
  BDF=${RAW/00000000/0000}
  BDF=$(echo "$BDF" | tr "[:upper:]" "[:lower:]")
  # stop helper to avoid auto-rebinds
  systemctl stop nvidia-persistenced 2>/dev/null || true
  # unbind from the nvidia driver (no ACPI hotplug)
  echo "$BDF" > /sys/bus/pci/drivers/nvidia/unbind
  '



  # sudo sh -c "RAW=\$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0); \
  # BDF=\${RAW/00000000/0000}; BDF=\$(echo \"\$BDF\" | tr '[:upper:]' '[:lower:]'); \
  # echo 1 > \"/sys/bus/pci/devices/\$BDF/remove\""

  # (2-2) Container toolkit + CDI file
  sudo -E zypper ar -f "https://nvidia.github.io/libnvidia-container/stable/rpm/"nvidia-container-toolkit.repo || true
  sudo -E zypper --gpg-auto-import-keys -n install -y nvidia-container-toolkit
  sudo -E mkdir -p /etc/cdi
  nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

  nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader -i 0 | sed -E "s/^00000000/0000/"

  # (2-3) Podman & deps
  SUSEConnect -p sle-module-containers/15.7/x86_64 || true
  sudo -E zypper -n refresh
  sudo -E zypper -n install podman conmon runc fuse-overlayfs slirp4netns
  podman --version >/dev/null

  # (2-4) CUDA test inside container (non-interactive variant)
  podman run --rm --device nvidia.com/gpu=all --security-opt=label=disable \
    registry.suse.com/bci/bci-base:latest \
    bash -lc '
      set -e
      zypper -n ar http://developer.download.nvidia.com/compute/cuda/repos/sles15/x86_64/ cuda-sle15-sp6 || true
      zypper --gpg-auto-import-keys -n refresh
      zypper -n install update-alternatives cuda-libraries-13-0 cuda-demo-suite-12-9
      /usr/local/cuda-12.9/extras/demo_suite/deviceQuery || true
    '

  echo "✔ SUCCESS: ${CURRENT_STEP}"
fi

# # ──────────────── STEP 3 — GPU OPERATOR (SERVER) ────────────────
# if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
#   CURRENT_STEP="Step 3: Deploy NVIDIA GPU Operator (GFD only)"
#   echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

#   # Non-interactive equivalent of kubectl edit: apply HelmChart CR w/ GFD only
#   cat <<'EOF' | kubectl -n kube-system apply -f -
# apiVersion: helm.cattle.io/v1
# kind: HelmChart
# metadata:
#   name: gpu-operator
#   namespace: kube-system
# spec:
#   repo: https://helm.ngc.nvidia.com/nvidia
#   chart: gpu-operator
#   targetNamespace: gpu-operator
#   createNamespace: true
#   valuesContent: |-
#     toolkit:
#       enabled: false
#       env:
#       - name: CONTAINERD_SOCKET
#         value: /run/k3s/containerd/containerd.sock
#     driver:
#       enabled: false
#     devicePlugin:
#       enabled: false
#     dcgm:
#       enabled: false
#     dcgmExporter:
#       enabled: false
#     nodeStatusExporter:
#       enabled: false
#     migManager:
#       enabled: false
#     cdi:
#       enabled: false
#     ccManager:
#       enabled: false
#     gdrcopy:
#       enabled: false
#     kataManager:
#       enabled: false
#     psa:
#       enabled: false
#     sandboxDevicePlugin:
#       enabled: false
#     sandboxWorkloads:
#       enabled: false
#     vfioManager:
#       enabled: false
#     vgpuDeviceManager:
#       enabled: false
#     vgpuManager:
#       enabled: false
#     gfd:
#       enabled: true
# EOF

#   echo "✔ SUCCESS: ${CURRENT_STEP}"
# fi

# # ──────────────── STEP 4 — NVIDIA DRA DRIVER (SERVER) ────────────────
# if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
#   CURRENT_STEP="Step 4: Deploy NVIDIA DRA Driver"
#   echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"
#   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
#   helm repo update


#   helm upgrade -i nvidia-dra-driver-gpu nvidia/nvidia-dra-driver-gpu \
#       --namespace nvidia-dra-driver-gpu --create-namespace --wait \
#       --set image.repository=nvcr.io/nvidia/k8s-dra-driver-gpu \
#       --set image.tag=v25.3.2 \
#       --set nvidiaDriverRoot=/ \
#       --set maskNvidiaDriverParams=false \
#       --set gpuResourcesEnabledOverride=true

#   echo "✔ SUCCESS: ${CURRENT_STEP}"
# fi

# # ──────────────── STEP 5 — WORKLOAD POD (SERVER) ────────────────
# if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
#   CURRENT_STEP="Step 5: Create ResourceClaimTemplate + workload pod"
#   echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

#   if [[ -z "${GPU_UUID}" ]]; then
#     echo "❌ GPU_UUID is required for Step 5 (from 'nvidia-smi -L' on the agent). Set GPU_UUID=GPU-... and re-run."
#     exit 1
#   fi

#   # (1) Namespace (idempotent)
#   kubectl get ns "${TEST_NS}" >/dev/null 2>&1 || kubectl create namespace "${TEST_NS}"

#   # (2) ResourceClaimTemplate (doc yaml with your UUID)
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

#       num_train_samples = 60000
#       num_test_samples = 10000
#       img_rows = 28
#       img_cols = 28
#       num_classes = 10

#       x_train = np.random.randint(0, 256, size=(num_train_samples, img_rows, img_cols), dtype=np.uint8)
#       x_test = np.random.randint(0, 256, size=(num_test_samples, img_rows, img_cols), dtype=np.uint8)

#       y_train = np.random.randint(0, num_classes, size=num_train_samples, dtype=np.uint8)
#       y_test = np.random.randint(0, num_classes, size=num_test_samples, dtype=np.uint8)

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

#   echo "✔ SUCCESS: ${CURRENT_STEP}"
# fi

# ──────────────── STEP 6 — BUILD / REGISTRY (SERVER) ────────────────
    if [[ "${PATTERN}" == "build" ]]; then
        CURRENT_STEP="Step 6 Pattern 1: Build CoHDI images (idempotent)"
        echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

        # Ensure Docker/make/go are available and Docker is running
        # SUSEConnect -p sle-module-containers/15.7/x86_64 || true
        # sudo -E zypper --gpg-auto-import-keys -n refresh
        # sudo -E zypper -n install docker git make go
        # systemctl enable --now docker #UNCOMMENT
        # quick health check (fails fast if daemon down)
        # sudo -E docker version >/dev/null

        # Create the systemd drop-in directory
        sudo -E mkdir -p /etc/systemd/system/docker.service.d

        # Create/update the proxy config (edit URLs & NO_PROXY as needed)
        sudo -E tee /etc/systemd/system/docker.service.d/proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://10.38.251.227:8080"
Environment="HTTPS_PROXY=http://10.38.251.227:8080"
Environment="NO_PROXY=127.0.0.1,localhost,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,192.168.0.0/16,127.0.0.1,172.16.0.0/16,.svc,localhost"
EOF

        # Reload systemd and restart Docker to pick up changes
        sudo -E systemctl daemon-reload
        sudo -E systemctl restart docker

        # 1) DDS
        echo "→ Cloning dynamic-device-scaler"
        rm -rf dynamic-device-scaler 2>/dev/null || true
        git clone https://github.com/CoHDI/dynamic-device-scaler.git
        cd dynamic-device-scaler
        awk 'BEGIN{added=0}
          /^FROM[[:space:]]/{print; if(!added){
              print "ENV HTTP_PROXY=http://10.38.251.227:8080"
              print "ENV HTTPS_PROXY=http://10.38.251.227:8080"
              print "ENV NO_PROXY=127.0.0.1,localhost,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,192.168.0.0/16,127.0.0.1,172.16.0.0/16,.svc,localhost"
              added=1; next
          }}
          {print}' Dockerfile > Dockerfile.new && mv Dockerfile.new Dockerfile
        sudo -E make docker-build    
        cd ..

        # 2) CDI Operator
        echo "→ Cloning composable-resource-operator"
        rm -rf composable-resource-operator 2>/dev/null || true
        git clone https://github.com/CoHDI/composable-resource-operator.git
        cd composable-resource-operator
         awk 'BEGIN{added=0}
          /^FROM[[:space:]]/{print; if(!added){
              print "ENV HTTP_PROXY=http://10.38.251.227:8080"
              print "ENV HTTPS_PROXY=http://10.38.251.227:8080"
              print "ENV NO_PROXY=127.0.0.1,localhost,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,192.168.0.0/16,127.0.0.1,172.16.0.0/16,.svc,localhost"
              added=1; next
          }}
          {print}' Dockerfile > Dockerfile.new && mv Dockerfile.new Dockerfile
        sudo -E make docker-build
        cd ..

        # 3) CDI DRA
        echo "→ Cloning composable-dra-driver"
        rm -rf composable-dra-driver 2>/dev/null || true
        git clone https://github.com/CoHDI/composable-dra-driver.git
        cd composable-dra-driver
        awk 'BEGIN{added=0}
        /^FROM[[:space:]]/{print; if(!added){
            print "ENV HTTP_PROXY=http://10.38.251.227:8080"
            print "ENV HTTPS_PROXY=http://10.38.251.227:8080"
            print "ENV NO_PROXY=127.0.0.1,localhost,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,192.168.0.0/16,127.0.0.1,172.16.0.0/16,.svc,localhost"
            added=1; next
        }}
        {print}' Dockerfile > Dockerfile.new && mv Dockerfile.new Dockerfile
        # doc says plain `docker build`; add a stable local tag so re-runs are clean
        sudo -E docker build -t cdi-dra:local .
        cd -

    echo "✔ SUCCESS: ${CURRENT_STEP}"

  elif [[ "${PATTERN}" == "registry" ]]; then
    CURRENT_STEP="Step 6 Pattern 2: Configure private registry + ctr pulls"
    echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

    # (1) Install Docker on server node
    sudo -E zypper -n refresh
    sudo -E zypper -n install docker
    sudo -E usermod -aG docker "$USER" || true
    docker version || true   # may require re-login; non-fatal

    # Trust CA (doc: place CA; do non-interactive if provided)
    if [[ -n "${CA_CERT_SRC}" && -r "${CA_CERT_SRC}" ]]; then
      install -D -m0644 "${CA_CERT_SRC}" /usr/share/pki/trust/anchors/cohdi-ca.crt
    fi
    chmod 0644 /usr/share/pki/trust/anchors/cohdi-ca.crt || true
    update-ca-certificates
    systemctl restart docker

    # docker login
    docker login "${REG_HOST}" -u "${REG_USER}" -p "${REG_PASS}"

    # (1) Write /etc/rancher/rke2/registries.yaml
    mkdir -p /etc/rancher/rke2/certs.d/"${REG_HOST}"
    if [[ -n "${CA_CERT_SRC}" && -r "${CA_CERT_SRC}" ]]; then
      install -D -m0644 "${CA_CERT_SRC}" /etc/rancher/rke2/certs.d/"${REG_HOST}"/cohdi-ca.crt
    fi
    cat > /etc/rancher/rke2/registries.yaml <<EOF
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
    systemctl restart rke2-server || true
    systemctl restart rke2-agent || true

    # (4) ctr pulls
    ctr -a /run/k3s/containerd/containerd.sock -n k8s.io i pull --user "${REG_USER}:${REG_PASS}" "${REG_HOST}/dds:latest" || true
    ctr -a /run/k3s/containerd/containerd.sock -n k8s.io i pull --user "${REG_USER}:${REG_PASS}" "${REG_HOST}/cdi-operator:latest" || true
    ctr -a /run/k3s/containerd/containerd.sock -n k8s.io i pull --user "${REG_USER}:${REG_PASS}" "${REG_HOST}/cdi-dra:${CDI_DRA_TAG}" || true

    # Notes from doc: image list & tags
    curl -u "${REG_USER}:${REG_PASS}" "https://$(echo "${REG_HOST}" | sed 's/:.*//')/v2/_catalog" || true
    curl -u "${REG_USER}:${REG_PASS}" "https://$(echo "${REG_HOST}" | sed 's/:.*//')/v2/cdi-dra/tags/list" || true

    echo "✔ SUCCESS: ${CURRENT_STEP}"
  else
    echo "❌ Unknown PATTERN=${PATTERN}; use PATTERN=build or PATTERN=registry"
    exit 1
  fi

# ──────────────── STEP 7 — DEPLOY COHDI COMPONENTS (SERVER) ────────────────
if [[ "${RUN_SERVER_STEPS}" == "true" ]]; then
  CURRENT_STEP="Step 7: Deploy CoHDI Components"
  echo -e "\n▶︎ BEGIN: ${CURRENT_STEP}"

  # 7.2.1.1 Namespace
  kubectl apply -f cdi-dra-namespace.yaml

  # 7.2.1.2 ConfigMap
  kubectl apply -f cdi-dra-configmap.yaml

  # 7.2.1.3 Secret (idempotent via dry-run -> apply)
  kubectl -n composable-dra create secret generic composable-dra-secret \
    --from-env-file cdi-dra-secret.file \
    --dry-run=client -o yaml | kubectl apply -f -

  # 7.2.1.4 CDI DRA Pod
  kubectl apply -f cdi-dra-deployment.yaml

  # 7.2.2 cdi-operator
  kubectl apply -f generated-manifests-v5.yaml
  kubectl apply -f secret.yaml

  # 7.2.3 dds
  kubectl apply -f dds.yaml

  # 7.3 status
  kubectl get po -A || true

  echo "✔ SUCCESS: ${CURRENT_STEP}"
fi

echo -e "\n🎉 DONE: All selected steps completed."
