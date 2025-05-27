#!/bin/bash
#
# Complete Kubernetes and Istio Deployment Script for DeathStarBench Social Network
# With DNS and Jaeger fixes integrated
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="social-network"
REPLICAS=1
ENABLE_HPA=false
JAEGER_ENABLED=true
CPU_LIMIT="500m"
MEMORY_LIMIT="512Mi"
CPU_REQUEST="100m"
MEMORY_REQUEST="128Mi"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --replicas)
      REPLICAS="$2"
      shift 2
      ;;
    --enable-hpa)
      ENABLE_HPA=true
      shift
      ;;
    --disable-jaeger)
      JAEGER_ENABLED=false
      shift
      ;;
    --cpu-limit)
      CPU_LIMIT="$2"
      shift 2
      ;;
    --memory-limit)
      MEMORY_LIMIT="$2"
      shift 2
      ;;
    --cpu-request)
      CPU_REQUEST="$2"
      shift 2
      ;;
    --memory-request)
      MEMORY_REQUEST="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --namespace NAME      Kubernetes namespace to deploy to (default: social-network)"
      echo "  --replicas N          Number of replicas for each service (default: 1)"
      echo "  --enable-hpa          Enable Horizontal Pod Autoscaling"
      echo "  --disable-jaeger      Disable Jaeger tracing"
      echo "  --cpu-limit LIMIT     CPU limit per container (default: 500m)"
      echo "  --memory-limit LIMIT  Memory limit per container (default: 512Mi)"
      echo "  --cpu-request REQ     CPU request per container (default: 100m)"
      echo "  --memory-request REQ  Memory request per container (default: 128Mi)"
      echo "  --help                Display this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $key${NC}"
      exit 1
      ;;
  esac
done

# Setup
echo -e "${GREEN}Setting up DeathStarBench social network deployment...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$SCRIPT_DIR/temp-k8s-config"
mkdir -p "$TEMP_DIR"

# Get DNS service IP
echo -e "${GREEN}Detecting Kubernetes DNS service...${NC}"
DNS_IP=$(kubectl get svc -n kube-system | grep dns | head -1 | awk '{print $3}')
if [ -z "$DNS_IP" ]; then
  echo -e "${YELLOW}Could not detect DNS service IP. Using default: 10.96.0.10${NC}"
  DNS_IP="10.96.0.10"
else
  echo -e "${GREEN}Detected DNS service IP: $DNS_IP${NC}"
fi

# Check prerequisites
echo -e "${GREEN}Checking prerequisites...${NC}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}kubectl not found. Please install kubectl.${NC}"
  exit 1
fi

# Check istioctl if available
if ! command -v istioctl &> /dev/null; then
  echo -e "${YELLOW}istioctl not found. Will proceed without Istio version check.${NC}"
else
  echo -e "${GREEN}Istio installation detected.${NC}"
  istioctl version
fi

# Check helm
if ! command -v helm &> /dev/null; then
  echo -e "${RED}helm not found. Please install Helm.${NC}"
  exit 1
fi

# Step 1: Create namespace
echo -e "${GREEN}Creating namespace: $NAMESPACE${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml > "$TEMP_DIR/namespace.yaml"
kubectl apply -f "$TEMP_DIR/namespace.yaml"

# Step 2: Enable Istio injection
echo -e "${GREEN}Enabling Istio injection for namespace: $NAMESPACE${NC}"
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# Step 3: Create Istio Gateway
echo -e "${GREEN}Creating Istio Gateway...${NC}"
cat > "$TEMP_DIR/gateway.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: social-network-gateway
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
kubectl apply -f "$TEMP_DIR/gateway.yaml"

# Step 4: Create Virtual Services
echo -e "${GREEN}Creating Virtual Services...${NC}"
cat > "$TEMP_DIR/nginx-vs.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: nginx-thrift
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
  gateways:
  - social-network-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: nginx-thrift
        port:
          number: 8080
EOF
kubectl apply -f "$TEMP_DIR/nginx-vs.yaml"

cat > "$TEMP_DIR/media-vs.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: media-frontend
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
  gateways:
  - social-network-gateway
  http:
  - match:
    - uri:
        prefix: /media
    route:
    - destination:
        host: media-frontend
        port:
          number: 8080
EOF
kubectl apply -f "$TEMP_DIR/media-vs.yaml"

# Step 5: Create Helm Values with DNS fix
echo -e "${GREEN}Preparing Helm values with DNS fix...${NC}"
cat > "$TEMP_DIR/values.yaml" <<EOF
global:
  replicas: $REPLICAS
  hpa:
    enabled: $ENABLE_HPA
    minReplicas: 1
    maxReplicas: 10
    targetCPUUtilizationPercentage: '60'
    targetMemoryUtilizationPercentage: '60'
  resources:
    limits:
      cpu: $CPU_LIMIT
      memory: $MEMORY_LIMIT
    requests:
      cpu: $CPU_REQUEST
      memory: $MEMORY_REQUEST
  imagePullPolicy: "IfNotPresent"
  restartPolicy: Always
  serviceType: ClusterIP
  dockerRegistry: docker.io
  defaultImageVersion: latest
  redis:
    standalone:
      enabled: true
  memcached:
    standalone:
      enabled: true
  mongodb:
    standalone:
      enabled: true
  jaeger:
    localAgentHostPort: jaeger:6831
    samplerType: probabilistic
    samplerParam: 0.1
    disabled: $( [ "$JAEGER_ENABLED" = false ] && echo "true" || echo "false" )
    logSpans: false
  nginx:
    # Use the detected DNS IP directly
    resolverName: $DNS_IP
EOF

# Step 6: Deploy with Helm
echo -e "${GREEN}Deploying with Helm...${NC}"
helm upgrade --install social-network "$SCRIPT_DIR/helm-chart/socialnetwork" \
  --namespace $NAMESPACE \
  --create-namespace \
  -f "$TEMP_DIR/values.yaml"

# Step 7: Set up Jaeger if enabled
if [ "$JAEGER_ENABLED" = true ]; then
  echo -e "${GREEN}Setting up Jaeger...${NC}"
  
  # Patch the Istio ingress gateway service to expose port 16686
  echo -e "${GREEN}Adding port 16686 to Istio ingress gateway service...${NC}"
  cat > "$TEMP_DIR/istio-gateway-patch.yaml" <<EOF
spec:
  ports:
  - name: jaeger-ui
    port: 16686
    protocol: TCP
    targetPort: 16686
EOF

  kubectl patch svc istio-ingressgateway -n istio-system --patch "$(cat $TEMP_DIR/istio-gateway-patch.yaml)" --type=strategic || true

  # Create a dedicated Gateway and VirtualService for Jaeger
  echo -e "${GREEN}Creating a dedicated Gateway and VirtualService for Jaeger...${NC}"
  cat > "$TEMP_DIR/jaeger-port-gateway.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: jaeger-gateway
  namespace: $NAMESPACE
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 16686
      name: http-jaeger
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: jaeger-vs
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
  gateways:
  - jaeger-gateway
  http:
  - match:
    - port: 16686
    route:
    - destination:
        host: jaeger
        port:
          number: 16686
EOF

  kubectl apply -f "$TEMP_DIR/jaeger-port-gateway.yaml"
  
  # Create a NodePort service for Jaeger as a fallback option
  echo -e "${GREEN}Creating a NodePort service for Jaeger as a fallback option...${NC}"
  cat > "$TEMP_DIR/jaeger-nodeport.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jaeger-nodeport
  namespace: $NAMESPACE
  labels:
    service: jaeger
spec:
  type: NodePort
  ports:
  - port: 16686
    nodePort: 30686
    name: http-ui
    targetPort: 16686
  selector:
    service: jaeger
EOF

  kubectl apply -f "$TEMP_DIR/jaeger-nodeport.yaml"
fi

# Step 8: Wait for deployment to be ready
echo -e "${GREEN}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment --all -n $NAMESPACE || true

# Get service endpoints
INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$INGRESS_IP" ]; then
  INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

# Get a node IP for the NodePort fallback
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
if [ -z "$NODE_IP" ]; then
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

# Summary
echo -e "\n${GREEN}DeathStarBench social network deployment complete!${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Replicas per service: ${YELLOW}$REPLICAS${NC}"
echo -e "HPA enabled: ${YELLOW}$ENABLE_HPA${NC}"
echo -e "Jaeger enabled: ${YELLOW}$JAEGER_ENABLED${NC}"

if [ -n "$INGRESS_IP" ]; then
  echo -e "\n${GREEN}Access URLs:${NC}"
  echo -e "Main Frontend:  ${YELLOW}http://$INGRESS_IP${NC}"
  echo -e "Media Frontend: ${YELLOW}http://$INGRESS_IP/media${NC}"
  if [ "$JAEGER_ENABLED" = true ]; then
    echo -e "Jaeger UI:      ${YELLOW}http://$INGRESS_IP:16686${NC}"
    echo -e "Jaeger NodePort: ${YELLOW}http://$NODE_IP:30686${NC} (fallback)"
  fi
else
  echo -e "\n${YELLOW}Istio ingress gateway address not found.${NC}"
  echo -e "${YELLOW}You can check the status with: kubectl -n istio-system get service istio-ingressgateway${NC}"
fi

echo -e "\n${GREEN}Next steps:${NC}"
echo -e "1. Initialize the social graph: ${YELLOW}python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=$INGRESS_IP --port=80${NC}"
echo -e "2. Run benchmark tests as described in the benchmark-README.md file"
echo -e "3. Check pod status: ${YELLOW}kubectl get pods -n $NAMESPACE${NC}"

# Keep the temp files for debugging
echo -e "\n${GREEN}Temporary files are in $TEMP_DIR${NC}"