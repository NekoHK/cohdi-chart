# CoHDI Helm Chart

# Introduction 

The **CoHDI Helm chart** deploys the CoHDI system — an integration layer for CDI management and device configuration in Kubernetes.  

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

## Creating Certificates (Mock Environment)

These steps show how to create mock CA and server certificates with OpenSSL for testing.

1.  Create an OpenSSL Config File
Save as openssl.conf:
```
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
x509_extensions    = v3_ca
prompt             = no

[ req_distinguished_name ]
C  = JP
ST = Tokyo
L  = Default City
O  = Default Company Ltd
CN = cdimgr.localdomain

[ v3_ca ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = cdimgr.localdomain
IP.1  = 192.168.1.101
```
2.  Create a CA Private Key and Certificate
```bash
openssl req -x509 -newkey rsa:2048 -days 365 \
  -keyout ca.key -out ca.crt -config openssl.conf -nodes
```

3. Create a Server Private Key and CSR
```bash
openssl req -new -newkey rsa:2048 -keyout server.key \
  -out server.csr -config openssl.conf -nodes
```

4. Sign the Server Certificate with the CA
```bash
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt -days 365 -extensions v3_ca \
  -extfile openssl.conf
```

## Configure values.yaml
Update ./values.yaml with your settings:

# Build and Test

## Install/Upgrade CoHDI
```bash
helm upgrade --install cohdi . -n cohdi --create-namespace
```

## Check status:
```bash
kubectl get pods -A
```

## Uninstall:
```bash
kubectl delete ns composable-dra composable-resource-operator-system cohdi credentials-namespace
```

# Contribute
TODO: Explain how other users and developers can contribute to make your code better.

