#!/bin/bash

kubectl delete ns composable-dra composable-resource-operator-system cohdi credentials-namespace --ignore-not-found || true
kubectl create -f cdi-dra-namespace.yaml
kubectl create -f cdi-dra-configmap.yaml
kubectl apply -f cdi-dra-secret.yaml
kubectl create -f cdi-dra-deployment.yaml
kubectl apply -f generated-manifests-v5.yaml
kubectl apply -f cdi-operator-secret.yaml
kubectl apply -f dds.yaml

sleep 5
kubectl get pods -A