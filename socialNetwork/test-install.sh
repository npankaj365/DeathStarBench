#!/bin/bash
set -e

echo "Testing istioctl installation..."
istioctl install --set profile=default -y

echo "Creating namespace..."
kubectl create namespace test-social-network --dry-run=client -o yaml | kubectl apply -f -

echo "Enabling istio injection..."
kubectl label namespace test-social-network istio-injection=enabled --overwrite

echo "Creating a simple gateway..."
cat > test-gateway.yaml <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: test-gateway
  namespace: test-social-network
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
EOF

echo "Applying gateway..."
kubectl apply -f test-gateway.yaml

echo "Test completed successfully."