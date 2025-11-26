#!/usr/bin/env bash

# Run all helm unittest suites and aggregate exit codes

rc=0

echo "=== Ensuring helm-unittest plugin is installed ==="
if ! helm plugin list | grep -q 'unittest'; then
  helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false
fi

echo "=== Running umbrella chart tests ==="
helm unittest ./CoHDI --strict || rc=$?

echo "=== Running cdi_dra tests ==="
helm unittest CoHDI/charts/cdi_dra --strict || rc=$?

echo "=== Running cdi_operator tests ==="
helm unittest CoHDI/charts/cdi_operator --strict || rc=$?

echo "=== Running dds tests ==="
helm unittest CoHDI/charts/dds --strict || rc=$?

echo "=== Final exit code: $rc ==="
exit $rc

