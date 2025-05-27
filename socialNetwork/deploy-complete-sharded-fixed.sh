#!/bin/bash
#
# Complete Kubernetes and Istio Deployment Script for DeathStarBench Social Network
# With DNS fix, Jaeger integration, and sharding enabled
# Fixed to address Helm release conflicts
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
ENABLE_SHARDING=true  # Default to sharded mode
HELM_RELEASE_NAME="socialnet"  # Changed from social-network to avoid conflicts
MONGODB_RELEASE="mongodb"  # Shortened name
REDIS_RELEASE="redis"  # Shortened name

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
    --disable-sharding)
      ENABLE_SHARDING=false
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
      echo "  --disable-sharding    Disable database sharding (default: sharding enabled)"
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

# Install Helm repositories if sharding is enabled
if [ "$ENABLE_SHARDING" = true ]; then
  echo -e "${GREEN}Checking if Helm dependencies are installed...${NC}"
  
  # Check if Bitnami repo is added
  if ! helm repo list 2>/dev/null | grep -q "bitnami"; then
    echo -e "${YELLOW}Adding Bitnami Helm repository...${NC}"
    helm repo add bitnami https://charts.bitnami.com/bitnami
  fi
  
  # Check if Redis cluster chart exists
  if ! helm show chart bitnami/redis-cluster &>/dev/null; then
    echo -e "${YELLOW}Redis cluster chart not found, updating Helm repositories...${NC}"
    helm repo update
  fi
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

# Step 5: Create Helm Values with DNS fix and sharding configuration
echo -e "${GREEN}Preparing Helm values...${NC}"

# Base configuration
if [ "$ENABLE_SHARDING" = true ]; then
  # Sharded configuration
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
        name: "$MONGODB_RELEASE-mongodb-sharded"
        user: "root"
        password: "password"
        port: 27017
  nginx:
    # Use the detected DNS IP directly
    resolverName: $DNS_IP
  jaeger:
    localAgentHostPort: jaeger:6831
    samplerType: probabilistic
    samplerParam: 0.1
    disabled: $( [ "$JAEGER_ENABLED" = false ] && echo "true" || echo "false" )
    logSpans: false
EOF
else
  # Non-sharded configuration
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
  nginx:
    # Use the detected DNS IP directly
    resolverName: $DNS_IP
  jaeger:
    localAgentHostPort: jaeger:6831
    samplerType: probabilistic
    samplerParam: 0.1
    disabled: $( [ "$JAEGER_ENABLED" = false ] && echo "true" || echo "false" )
    logSpans: false
EOF
fi

# Step 6: Create service config for sharded setup if needed
if [ "$ENABLE_SHARDING" = true ]; then
  echo -e "${GREEN}Creating service config for sharded setup...${NC}"

  cat > "$TEMP_DIR/sharded-service-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: service-config-sharded
  namespace: $NAMESPACE
data:
  service-config.json: |
    {
      "secret": "secret",
      "social-graph-service": {
        "addr": "social-graph-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "social-graph-mongodb": {
        "addr": "$MONGODB_RELEASE-mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "social-graph-redis": {
        "addr": "$REDIS_RELEASE-redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1,
        "use_replica": 0
      },
      "home-timeline-service": {
        "addr": "home-timeline-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "home-timeline-redis": {
        "addr": "$REDIS_RELEASE-redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1,
        "use_replica": 0
      },
      "compose-post-service": {
        "addr": "compose-post-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "compose-post-redis": {
        "addr": "$REDIS_RELEASE-redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1
      },
      "user-timeline-service": {
        "addr": "user-timeline-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-timeline-mongodb": {
        "addr": "$MONGODB_RELEASE-mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-timeline-redis": {
        "addr": "$REDIS_RELEASE-redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1,
        "use_replica": 0
      },
      "post-storage-service": {
        "addr": "post-storage-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "post-storage-mongodb": {
        "addr": "$MONGODB_RELEASE-mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "post-storage-memcached": {
        "addr": "post-storage-memcached",
        "port": 11211,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "url-shorten-service": {
        "addr": "url-shorten-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "url-shorten-mongodb": {
        "addr": "$MONGODB_RELEASE-mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "url-shorten-memcached": {
        "addr": "url-shorten-memcached",
        "port": 11211,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "user-service": {
        "addr": "user-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-mongodb": {
        "addr": "$MONGODB_RELEASE-mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-memcached": {
        "addr": "user-memcached",
        "port": 11211,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "media-service": {
        "addr": "media-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "media-mongodb": {
        "addr": "$MONGODB_RELEASE-mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "media-memcached": {
        "addr": "media-memcached",
        "port": 11211,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "text-service": {
        "addr": "text-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "unique-id-service": {
        "addr": "unique-id-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-mention-service": {
        "addr": "user-mention-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      }
    }
EOF

  # Create ConfigMap mount path patch
  cat > "$TEMP_DIR/configmap-patch.yaml" <<EOF
spec:
  template:
    spec:
      containers:
      - name: {{containerName}}
        volumeMounts:
        - name: service-config-sharded-volume
          mountPath: /social-network-microservices/config/service-config.json
          subPath: service-config.json
      volumes:
      - name: service-config-sharded-volume
        configMap:
          name: service-config-sharded
EOF

  # Create a list of the services that need redis-cluster flag
  cat > "$TEMP_DIR/redis-cluster-services.txt" <<EOF
social-graph-service
home-timeline-service
user-timeline-service
EOF

  # Deploy Redis Cluster and MongoDB Sharded before main application
  echo -e "${GREEN}Installing/upgrading Redis Cluster...${NC}"
  helm upgrade --install $REDIS_RELEASE bitnami/redis-cluster \
    --namespace $NAMESPACE \
    --set fullnameOverride=$REDIS_RELEASE-redis-cluster \
    --set usePassword=false \
    --set cluster.slaveCount=1 \
    --set cluster.nodes=6 \
    --set metrics.enabled=false \
    --set persistence.enabled=false

  echo -e "${GREEN}Installing/upgrading MongoDB Sharded...${NC}"
  helm upgrade --install $MONGODB_RELEASE bitnami/mongodb-sharded \
    --namespace $NAMESPACE \
    --set fullnameOverride=$MONGODB_RELEASE-mongodb-sharded \
    --set auth.rootPassword=password \
    --set shards=2 \
    --set shardsvr.dataNode.replicaCount=2 \
    --set configsvr.replicaCount=2 \
    --set persistence.enabled=false

  # Apply service config for sharded setup
  kubectl apply -f "$TEMP_DIR/sharded-service-config.yaml"
fi

# Step 7: Deploy with Helm
echo -e "${GREEN}Deploying with Helm...${NC}"
helm upgrade --install $HELM_RELEASE_NAME "$SCRIPT_DIR/helm-chart/socialnetwork" \
  --namespace $NAMESPACE \
  --create-namespace \
  -f "$TEMP_DIR/values.yaml"

# Step 8: Set up Jaeger if enabled
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

# Step 9: Patch services for sharded setup if needed
if [ "$ENABLE_SHARDING" = true ]; then
  echo -e "${GREEN}Patching deployments to use the sharded service config...${NC}"
  
  # Wait for deployments to be created
  sleep 15
  
  # Get all service deployments
  SERVICE_DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -l "app.kubernetes.io/part-of=social-network" -o name 2>/dev/null || kubectl get deployments -n $NAMESPACE -o name)
  
  for DEPLOYMENT in $SERVICE_DEPLOYMENTS; do
    DEPLOYMENT_NAME=$(echo $DEPLOYMENT | cut -d '/' -f 2)
    
    # Skip database deployments
    if [[ $DEPLOYMENT_NAME == *"mongodb"* ]] || [[ $DEPLOYMENT_NAME == *"redis"* ]] || [[ $DEPLOYMENT_NAME == *"memcached"* ]]; then
      continue
    fi
    
    echo -e "${GREEN}Patching deployment $DEPLOYMENT_NAME...${NC}"
    
    # Get the container name
    CONTAINER_NAME=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null || echo $DEPLOYMENT_NAME)
    
    # Create the patch file with container name
    sed "s/{{containerName}}/$CONTAINER_NAME/g" "$TEMP_DIR/configmap-patch.yaml" > "$TEMP_DIR/$DEPLOYMENT_NAME-patch.yaml"
    
    # Apply the patch
    kubectl patch deployment $DEPLOYMENT_NAME -n $NAMESPACE --patch "$(cat $TEMP_DIR/$DEPLOYMENT_NAME-patch.yaml)" || echo -e "${YELLOW}Could not patch $DEPLOYMENT_NAME, may need manual configuration.${NC}"
  done
  
  # Check for services that need the --redis-cluster flag
  echo -e "${GREEN}Adding --redis-cluster flag to services that need it...${NC}"
  while read SERVICE; do
    if kubectl get deployment $SERVICE -n $NAMESPACE &>/dev/null; then
      echo -e "${GREEN}Adding --redis-cluster flag to $SERVICE...${NC}"
      
      # Get current command and args
      CURRENT_COMMAND=$(kubectl get deployment $SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].command}' 2>/dev/null || echo "[]")
      CURRENT_ARGS=$(kubectl get deployment $SERVICE -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
      
      # Create patch based on whether it's using command or args
      if [ "$CURRENT_COMMAND" != "[]" ]; then
        # Service uses command
        cat > "$TEMP_DIR/$SERVICE-redis-cluster-patch.yaml" <<EOF
spec:
  template:
    spec:
      containers:
      - name: $SERVICE
        command:
        - $SERVICE
        - --redis-cluster
EOF
      else
        # Service uses args
        cat > "$TEMP_DIR/$SERVICE-redis-cluster-patch.yaml" <<EOF
spec:
  template:
    spec:
      containers:
      - name: $SERVICE
        args:
        - --redis-cluster
EOF
      fi
      
      # Apply the patch
      kubectl patch deployment $SERVICE -n $NAMESPACE --patch "$(cat $TEMP_DIR/$SERVICE-redis-cluster-patch.yaml)" || echo -e "${YELLOW}Could not add --redis-cluster flag to $SERVICE, may need manual configuration.${NC}"
    fi
  done < "$TEMP_DIR/redis-cluster-services.txt"
fi

# Step 10: Wait for deployment to be ready
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
echo -e "Sharding enabled: ${YELLOW}$ENABLE_SHARDING${NC}"

if [ "$ENABLE_SHARDING" = true ]; then
  echo -e "\n${GREEN}Sharding configuration:${NC}"
  echo -e "- Redis: Clustered with 6 nodes (3 masters, 3 replicas)"
  echo -e "- MongoDB: Sharded with 2 shards and 2 replicas per shard"
  echo -e "- Memcached: Standalone instances"
fi

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

if [ "$ENABLE_SHARDING" = true ]; then
  echo -e "\n${YELLOW}Important notes for sharded setup:${NC}"
  echo -e "1. The first requests after deployment may be slow while shards initialize"
  echo -e "2. You can check Redis cluster status with: ${YELLOW}kubectl exec -n $NAMESPACE \$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$REDIS_RELEASE -o jsonpath='{.items[0].metadata.name}') -- redis-cli cluster info${NC}"
  echo -e "3. You can check MongoDB status with: ${YELLOW}kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$MONGODB_RELEASE${NC}"
fi

# Keep the temp files for debugging
echo -e "\n${GREEN}Temporary files are in $TEMP_DIR${NC}"