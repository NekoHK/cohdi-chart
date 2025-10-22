cd "CoHDI"
rm -f Chart.lock
kubectl delete ns composable-dra composable-resource-operator-system cohdi credentials-namespace --ignore-not-found || true

helm dependency build .
helm lint .

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


helm upgrade --install cohdi . -n cohdi --create-namespace --debug

sleep 5

kubectl get pods -A