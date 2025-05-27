#!/bin/bash
#
# Kubernetes and Istio Deployment Script for DeathStarBench Social Network
# 
# This script:
# 1. Checks prerequisites
# 2. Configures and deploys Istio with suitable settings
# 3. Deploys the DeathStarBench social network application
# 4. Sets up Istio gateways and virtual services
# 5. Provides post-deployment verification

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="social-network"
ISTIO_PROFILE="default"
REPLICAS=1
ENABLE_METRICS=true
ENABLE_HPA=false
JAEGER_ENABLED=true
CPU_LIMIT="500m"
MEMORY_LIMIT="512Mi"
CPU_REQUEST="100m"
MEMORY_REQUEST="128Mi"
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --istio-profile)
      ISTIO_PROFILE="$2"
      shift 2
      ;;
    --replicas)
      REPLICAS="$2"
      shift 2
      ;;
    --disable-metrics)
      ENABLE_METRICS=false
      shift
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
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --namespace NAME      Kubernetes namespace to deploy to (default: social-network)"
      echo "  --istio-profile NAME  Istio profile to use (default: default)"
      echo "  --replicas N          Number of replicas for each service (default: 1)"
      echo "  --disable-metrics     Disable Prometheus metrics collection"
      echo "  --enable-hpa          Enable Horizontal Pod Autoscaling"
      echo "  --disable-jaeger      Disable Jaeger tracing"
      echo "  --cpu-limit LIMIT     CPU limit per container (default: 500m)"
      echo "  --memory-limit LIMIT  Memory limit per container (default: 512Mi)"
      echo "  --cpu-request REQ     CPU request per container (default: 100m)"
      echo "  --memory-request REQ  Memory request per container (default: 128Mi)"
      echo "  --dry-run             Print commands without executing them"
      echo "  --help                Display this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $key${NC}"
      exit 1
      ;;
  esac
done

# Helper function to run or print commands
run_cmd() {
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN] Would execute: $*${NC}"
  else
    echo -e "${GREEN}Executing: $*${NC}"
    "$@"
  fi
}

# Helper function to apply YAML content
apply_yaml() {
  local content="$1"
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY RUN] Would apply YAML:${NC}"
    echo "$content"
  else
    echo -e "${GREEN}Applying YAML configuration...${NC}"
    echo "$content" | kubectl apply -f -
  fi
}

# Check prerequisites
check_prerequisites() {
  echo -e "${GREEN}Checking prerequisites...${NC}"
  
  # Check kubectl
  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl.${NC}"
    exit 1
  fi
  
  # Check istioctl
  if ! command -v istioctl &> /dev/null; then
    echo -e "${RED}istioctl not found. Please install Istio.${NC}"
    exit 1
  fi
  
  # Check helm
  if ! command -v helm &> /dev/null; then
    echo -e "${RED}helm not found. Please install Helm.${NC}"
    exit 1
  fi
  
  # Check kubectl connection
  if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Prerequisites check passed.${NC}"
}

# Deploy Istio
deploy_istio() {
  echo -e "${GREEN}Deploying Istio with profile: $ISTIO_PROFILE...${NC}"
  
  # Install Istio with specified profile
  run_cmd istioctl install --set profile=$ISTIO_PROFILE -y
  
  # Create namespace if it doesn't exist
  run_cmd kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
  
  # Enable Istio injection
  run_cmd kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite
  
  # Deploy Istio addons if metrics are enabled
  if [ "$ENABLE_METRICS" = true ]; then
    echo -e "${GREEN}Deploying Istio addons...${NC}"
    
    # Apply Prometheus, Grafana, and Kiali if available in the Istio distribution
    if [ -d "$(istioctl profile dump --dir)/samples/addons" ]; then
      run_cmd kubectl apply -f "$(istioctl profile dump --dir)/samples/addons/prometheus.yaml"
      run_cmd kubectl apply -f "$(istioctl profile dump --dir)/samples/addons/grafana.yaml"
      run_cmd kubectl apply -f "$(istioctl profile dump --dir)/samples/addons/kiali.yaml"
    else
      echo -e "${YELLOW}Istio addons not found. Skipping addon deployment.${NC}"
    fi
  fi
  
  echo -e "${GREEN}Istio deployment completed.${NC}"
}

# Create Istio gateway and virtual services
create_istio_resources() {
  echo -e "${GREEN}Creating Istio gateway and virtual services...${NC}"
  
  # Create Istio gateway
  apply_yaml "apiVersion: networking.istio.io/v1alpha3
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
    - \"*\""

  # Create virtual service for the frontend
  apply_yaml "apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: nginx-thrift
  namespace: $NAMESPACE
spec:
  hosts:
  - \"*\"
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
          number: 8080"

  # Create virtual service for the media frontend
  apply_yaml "apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: media-frontend
  namespace: $NAMESPACE
spec:
  hosts:
  - \"*\"
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
          number: 8080"

  echo -e "${GREEN}Istio gateway and virtual services created.${NC}"
}

# Deploy DeathStarBench social network application
deploy_social_network() {
  echo -e "${GREEN}Deploying DeathStarBench social network application...${NC}"
  
  # Create values override file for Helm
  cat <<EOF > social-network-values.yaml
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
      enabled: false
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
    queueSize: 1000000
    bufferFlushInterval: 10
    samplerType: probabilistic
    samplerParam: 0.1
    disabled: $( [ "$JAEGER_ENABLED" = false ] && echo "true" || echo "false" )
    logSpans: false
EOF

  # Deploy with Helm
  run_cmd helm upgrade --install social-network ./helm-chart/socialnetwork \
    --namespace $NAMESPACE \
    --create-namespace \
    -f social-network-values.yaml

  echo -e "${GREEN}DeathStarBench social network deployed.${NC}"
}

# Display post-deployment information
show_post_deployment_info() {
  echo -e "${GREEN}Deployment completed successfully!${NC}"
  
  # Wait for deployment to be ready
  if [ "$DRY_RUN" = false ]; then
    echo "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment --all -n $NAMESPACE
  fi
  
  # Get Istio ingress gateway IP/hostname
  if [ "$DRY_RUN" = false ]; then
    INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$INGRESS_HOST" ]; then
      INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi
    
    if [ -z "$INGRESS_HOST" ]; then
      echo -e "${YELLOW}Istio ingress gateway does not have an external IP or hostname yet.${NC}"
      echo -e "${YELLOW}You may need to wait for the LoadBalancer to be provisioned.${NC}"
      echo -e "${YELLOW}You can check the status with: kubectl -n istio-system get service istio-ingressgateway${NC}"
    else
      echo -e "${GREEN}Social network application is accessible at:${NC}"
      echo -e "  Frontend: http://$INGRESS_HOST"
      echo -e "  Media Frontend: http://$INGRESS_HOST/media"
      echo -e "  Jaeger UI (if enabled): http://$INGRESS_HOST:16686"
    fi
  fi
  
  echo -e "\n${GREEN}Next steps:${NC}"
  echo -e "1. Initialize the social graph with: python3 scripts/init_social_graph.py"
  echo -e "2. Run benchmark tests as described in the benchmark-README.md file"
  echo -e "3. To monitor the application, access the Istio dashboard: istioctl dashboard kiali"
}

# Main execution
check_prerequisites
deploy_istio
create_istio_resources
deploy_social_network
show_post_deployment_info

echo -e "\n${GREEN}Deployment script completed.${NC}"