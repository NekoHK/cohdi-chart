#!/usr/bin/env bash

# Run all helm unittest suites and aggregate exit codes

rc=0

echo "=== Ensuring helm-unittest plugin is installed ==="
if ! helm plugin list | grep -q 'unittest'; then
  helm plugin install https://github.com/helm-unittest/helm-unittest --verify=false
fi

echo "=== Running CoHDI chart tests ==="
helm unittest ./CoHDI --strict || rc=$?

echo "=== Final exit code: $rc ==="
exit $rc
