#!/bin/bash

cd CoHDI || exit 1

# 
helm uninstall cohdi -n cohdi || true
sleep 5

# Cleanup previous configuration
# kubectl delete ns composable-dra composable-resource-operator-system cohdi credentials-namespace --ignore-not-found || true
rm -f Chart.lock

# Tag existing cluster-level resources so Helm will "treat them as its own"
PREFIXES='^(composable-resource-operator-|cdi-|dynamic-device-scaler-)'
for kind in clusterrole clusterrolebinding validatingwebhookconfiguration mutatingwebhookconfiguration; do
  kubectl get "$kind" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep -E "$PREFIXES" \
  | while read -r name; do
      echo "Adopting $kind/$name"
      kubectl label "$kind" "$name" app.kubernetes.io/managed-by=Helm --overwrite
      kubectl annotate "$kind" "$name" \
        meta.helm.sh/release-name=cohdi \
        meta.helm.sh/release-namespace=cohdi \
        --overwrite
    done
done

# Remove labels and annotations (for testing purposes) 
# for kind in clusterrole clusterrolebinding validatingwebhookconfiguration mutatingwebhookconfiguration; do
#   kubectl get "$kind" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
#   | grep -E "$PREFIXES" \
#   | while read -r name; do
#       kubectl label "$kind" "$name" app.kubernetes.io/managed-by- --overwrite
#       kubectl annotate "$kind" "$name" meta.helm.sh/release-name- --overwrite
#       kubectl annotate "$kind" "$name" meta.helm.sh/release-namespace- --overwrite
#     done
# done

# Build dependencies
helm dependency build .

# Perform statuc analysis
helm lint .

# Install/upgrade cohdi
helm install cohdi . -n cohdi --create-namespace --debug
# helm upgrade --install cohdi . -n cohdi --create-namespace --debug

# Wait and check pods
sleep 5
kubectl get pods -A