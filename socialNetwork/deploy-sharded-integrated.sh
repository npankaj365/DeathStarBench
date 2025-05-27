#!/bin/bash
#
# Integrated Sharded Deployment Script for DeathStarBench Social Network
# Uses the Helm chart's built-in sharding support to avoid conflicts
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
echo -e "${GREEN}Setting up DeathStarBench social network deployment with integrated sharding...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$SCRIPT_DIR/temp-integrated-config"
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

# Check if Bitnami repo is added and add if needed
echo -e "${GREEN}Setting up Helm repositories...${NC}"
if ! helm repo list 2>/dev/null | grep -q "bitnami"; then
  echo -e "${YELLOW}Adding Bitnami Helm repository...${NC}"
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi

# Update repositories
echo -e "${GREEN}Updating Helm repositories...${NC}"
helm repo update

# Step 1: Clean up existing namespace completely
echo -e "${GREEN}Cleaning up existing resources...${NC}"

if kubectl get namespace $NAMESPACE &>/dev/null; then
  # Delete all Helm releases first
  echo -e "${GREEN}Deleting existing Helm releases...${NC}"
  HELM_RELEASES=$(helm list -n $NAMESPACE -q 2>/dev/null || echo "")
  for RELEASE in $HELM_RELEASES; do
    echo -e "${GREEN}Deleting Helm release $RELEASE in namespace $NAMESPACE...${NC}"
    helm uninstall $RELEASE -n $NAMESPACE --wait || true
  done
  
  # Delete namespace
  echo -e "${GREEN}Deleting namespace $NAMESPACE...${NC}"
  kubectl delete namespace $NAMESPACE --grace-period=0 --force || true
  
  # Wait for namespace to be fully deleted
  echo -e "${YELLOW}Waiting for namespace $NAMESPACE to be deleted...${NC}"
  while kubectl get namespace $NAMESPACE &>/dev/null; do
    sleep 2
  done
fi

# Step 2: Create namespace and enable Istio injection
echo -e "${GREEN}Creating namespace: $NAMESPACE${NC}"
kubectl create namespace $NAMESPACE

echo -e "${GREEN}Enabling Istio injection for namespace: $NAMESPACE${NC}"
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# Step 3: Create Istio Gateway and Virtual Services
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

# Step 4: Create Helm values with integrated sharding
echo -e "${GREEN}Preparing Helm values with integrated sharding...${NC}"
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
    cluster:
      enabled: true
    standalone:
      enabled: false
    replication:
      enabled: false
  memcached:
    standalone:
      enabled: true
  mongodb:
    standalone:
      enabled: false
    sharding:
      enabled: true
      svc:
        name: "mongodb-sharded"
        user: "root"
        password: "password"
        port: 27017
  nginx:
    resolverName: $DNS_IP
  jaeger:
    localAgentHostPort: jaeger:6831
    samplerType: probabilistic
    samplerParam: 0.1
    disabled: $( [ "$JAEGER_ENABLED" = false ] && echo "true" || echo "false" )
    logSpans: false

# Enable Redis Cluster through the chart
redis-cluster:
  usePassword: false
  cluster:
    nodes: 6
    slaveCount: 1
  redis:
    resources:
      limits:
        cpu: $CPU_LIMIT
        memory: $MEMORY_LIMIT
      requests:
        cpu: $CPU_REQUEST
        memory: $MEMORY_REQUEST
    readinessProbe:
      enabled: false
    livenessProbe:
      enabled: false
  persistence:
    enabled: false

# Enable MongoDB Sharding through the chart
mongodb-sharded:
  fullnameOverride: mongodb-sharded
  auth:
    rootPassword: password
  shards: 2
  shardsvr:
    dataNode:
      replicaCount: 2
      resources:
        limits:
          cpu: $CPU_LIMIT
          memory: $MEMORY_LIMIT
        requests:
          cpu: $CPU_REQUEST
          memory: $MEMORY_REQUEST
  configsvr:
    replicaCount: 2
    resources:
      limits:
        cpu: $CPU_LIMIT
        memory: $MEMORY_LIMIT
      requests:
        cpu: $CPU_REQUEST
        memory: $MEMORY_REQUEST
  mongos:
    resources:
      limits:
        cpu: $CPU_LIMIT
        memory: $MEMORY_LIMIT
      requests:
        cpu: $CPU_REQUEST
        memory: $MEMORY_REQUEST
  persistence:
    enabled: false
EOF

# Step 5: Deploy main application with Helm and all dependencies
echo -e "${GREEN}Deploying social network application with integrated sharding...${NC}"
helm install social-network "$SCRIPT_DIR/helm-chart/socialnetwork" \
  --namespace $NAMESPACE \
  -f "$TEMP_DIR/values.yaml" \
  --timeout 15m \
  --wait

# Step 6: Set up Jaeger if enabled
if [ "$JAEGER_ENABLED" = true ]; then
  echo -e "${GREEN}Setting up Jaeger...${NC}"
  
  # Create a NodePort service for Jaeger
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

# Step 7: Post-deployment configuration for sharding
echo -e "${GREEN}Configuring services for sharded setup...${NC}"

# Wait a bit for the deployment to stabilize
sleep 30

# Add redis-cluster flag to services that need it
REDIS_CLUSTER_SERVICES=("social-graph-service" "home-timeline-service" "user-timeline-service")

for SERVICE in "${REDIS_CLUSTER_SERVICES[@]}"; do
  if kubectl get deployment $SERVICE -n $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}Adding --redis-cluster flag to $SERVICE...${NC}"
    
    # Get current args and add the flag if not present
    CURRENT_ARGS=$(kubectl get deployment $SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
    
    if [[ "$CURRENT_ARGS" != *"--redis-cluster"* ]]; then
      # Create patch to add --redis-cluster flag
      cat > "$TEMP_DIR/$SERVICE-redis-cluster-patch.yaml" <<EOF
spec:
  template:
    spec:
      containers:
      - name: $SERVICE
        args:
        - --redis-cluster
EOF
      kubectl patch deployment $SERVICE -n $NAMESPACE --patch "$(cat $TEMP_DIR/$SERVICE-redis-cluster-patch.yaml)" || echo -e "${YELLOW}Could not add --redis-cluster flag to $SERVICE${NC}"
    fi
  fi
done

# Step 8: Wait for final deployment to be ready
echo -e "${GREEN}Waiting for all deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=600s deployment --all -n $NAMESPACE || true

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
echo -e "\n${GREEN}DeathStarBench social network deployment with integrated sharding complete!${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "Replicas per service: ${YELLOW}$REPLICAS${NC}"
echo -e "HPA enabled: ${YELLOW}$ENABLE_HPA${NC}"
echo -e "Jaeger enabled: ${YELLOW}$JAEGER_ENABLED${NC}"
echo -e "Sharding: ${YELLOW}Enabled (Redis Cluster + MongoDB Sharded)${NC}"

echo -e "\n${GREEN}Sharding configuration:${NC}"
echo -e "- Redis: Clustered with 6 nodes (3 masters, 3 replicas)"
echo -e "- MongoDB: Sharded with 2 shards and 2 replicas per shard"
echo -e "- Memcached: Standalone instances"

if [ -n "$INGRESS_IP" ]; then
  echo -e "\n${GREEN}Access URLs:${NC}"
  echo -e "Main Frontend:  ${YELLOW}http://$INGRESS_IP${NC}"
  echo -e "Media Frontend: ${YELLOW}http://$INGRESS_IP/media${NC}"
  if [ "$JAEGER_ENABLED" = true ]; then
    echo -e "Jaeger NodePort: ${YELLOW}http://$NODE_IP:30686${NC}"
  fi
else
  echo -e "\n${YELLOW}Istio ingress gateway address not found.${NC}"
  echo -e "${YELLOW}You can check the status with: kubectl -n istio-system get service istio-ingressgateway${NC}"
fi

echo -e "\n${GREEN}Next steps:${NC}"
echo -e "1. Wait for all pods to be running: ${YELLOW}kubectl get pods -n $NAMESPACE${NC}"
echo -e "2. Initialize the social graph: ${YELLOW}python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=$INGRESS_IP --port=80${NC}"
echo -e "3. Run benchmark tests with higher load"

echo -e "\n${YELLOW}Important notes for sharded setup:${NC}"
echo -e "1. The first requests after deployment may be slow while shards initialize"
echo -e "2. Check Redis cluster status: ${YELLOW}kubectl exec -n $NAMESPACE \$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=redis-cluster -o jsonpath='{.items[0].metadata.name}') -- redis-cli cluster info${NC}"
echo -e "3. Check MongoDB status: ${YELLOW}kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=mongodb-sharded${NC}"

# Keep the temp files for debugging
echo -e "\n${GREEN}Temporary files are in $TEMP_DIR${NC}"