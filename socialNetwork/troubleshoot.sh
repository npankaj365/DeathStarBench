#!/bin/bash

# Set up color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}DeathStarBench Social Network Kubernetes Troubleshooter${NC}"
echo "This script will help diagnose issues with the deployment."

# Check istioctl
echo -e "\n${YELLOW}Step 1: Checking istioctl version${NC}"
if ! command -v istioctl &> /dev/null; then
  echo -e "${RED}istioctl not found. Please install Istio.${NC}"
  exit 1
else
  istioctl version
fi

# Test namespace creation
echo -e "\n${YELLOW}Step 2: Testing namespace creation${NC}"
NAMESPACE="test-dsb-$(date +%s)"
echo "Creating test namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE
echo -e "${GREEN}Namespace created successfully.${NC}"

# Test Istio injection
echo -e "\n${YELLOW}Step 3: Testing Istio injection${NC}"
echo "Enabling Istio injection on namespace: $NAMESPACE"
kubectl label namespace $NAMESPACE istio-injection=enabled
echo -e "${GREEN}Istio injection enabled.${NC}"

# Test Gateway creation
echo -e "\n${YELLOW}Step 4: Testing Gateway creation${NC}"
echo "Creating a test Gateway..."

# First approach - pipe from echo
echo "Method 1: Using echo | kubectl apply"
cat > "test-gateway-1.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: test-gateway-1
  namespace: $NAMESPACE
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

echo "Applying gateway using kubectl apply -f..."
kubectl apply -f test-gateway-1.yaml
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Gateway created successfully with method 1.${NC}"
else
  echo -e "${RED}Failed to create Gateway with method 1.${NC}"
fi

# Clean up
echo -e "\n${YELLOW}Step 5: Cleaning up${NC}"
echo "Deleting test namespace and resources..."
kubectl delete namespace $NAMESPACE
rm -f test-gateway-1.yaml

echo -e "\n${GREEN}Troubleshooting completed.${NC}"
echo "Please report the above results to diagnose your issue."