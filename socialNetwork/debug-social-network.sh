#!/bin/bash
# Script to debug the social network deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_NAMESPACE="social-network"
DB_NAMESPACE="social-network-db"

# Get pods status
echo -e "${GREEN}=== Application Pods (${APP_NAMESPACE}) ===${NC}"
kubectl get pods -n $APP_NAMESPACE

echo -e "\n${GREEN}=== Database Pods (${DB_NAMESPACE}) ===${NC}"
kubectl get pods -n $DB_NAMESPACE

# Get services
echo -e "\n${GREEN}=== Application Services (${APP_NAMESPACE}) ===${NC}"
kubectl get services -n $APP_NAMESPACE

echo -e "\n${GREEN}=== Database Services (${DB_NAMESPACE}) ===${NC}"
kubectl get services -n $DB_NAMESPACE

# Get the gateway IP
GATEWAY_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$GATEWAY_IP" ]; then
  GATEWAY_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

echo -e "\n${GREEN}=== Checking access to homepage ===${NC}"
echo "Accessing http://$GATEWAY_IP"
curl -s -I "http://$GATEWAY_IP" || echo "Failed to access homepage"

echo -e "\n${GREEN}=== Checking social graph initialization ===${NC}"
echo "Testing if social graph needs to be initialized"
curl -s "http://$GATEWAY_IP/main.html" | grep -q "Sign In" && echo "Social graph may need initialization. Run: python3 scripts/init_social_graph.py" || echo "Homepage doesn't show login, social graph may be initialized"

# Check logs of key services
echo -e "\n${GREEN}=== Checking logs for key services ===${NC}"

# Function to check logs for a service
check_logs() {
  local service=$1
  local ns=$2
  local pod=$(kubectl get pods -n $ns -l "service=$service" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [ -z "$pod" ]; then
    pod=$(kubectl get pods -n $ns | grep $service | head -1 | awk '{print $1}')
  fi
  
  if [ -n "$pod" ]; then
    echo -e "${YELLOW}--- Last 20 lines of logs for $service ($pod) ---${NC}"
    kubectl logs -n $ns $pod --tail=20
  else
    echo -e "${RED}No pod found for service $service in namespace $ns${NC}"
  fi
}

# Check logs for frontend services
check_logs "nginx-thrift" $APP_NAMESPACE
check_logs "user-service" $APP_NAMESPACE
check_logs "social-graph-service" $APP_NAMESPACE

echo -e "\n${GREEN}=== Cross-namespace connectivity test ===${NC}"
echo "Testing if application pods can reach database services"

# Get a pod from application namespace
APP_POD=$(kubectl get pods -n $APP_NAMESPACE | grep -v NAME | head -1 | awk '{print $1}')

if [ -n "$APP_POD" ]; then
  echo "Testing connectivity from pod $APP_POD"
  echo -e "${YELLOW}Testing MongoDB connectivity:${NC}"
  kubectl exec -n $APP_NAMESPACE $APP_POD -- sh -c "nc -zv mongodb-sharded 27017" || echo "Failed to connect to MongoDB"
  
  echo -e "${YELLOW}Testing Redis connectivity:${NC}"
  kubectl exec -n $APP_NAMESPACE $APP_POD -- sh -c "nc -zv redis-cluster 6379" || echo "Failed to connect to Redis"
else
  echo -e "${RED}No pod found in application namespace for connectivity test${NC}"
fi

# Check configuration
echo -e "\n${GREEN}=== Service Configuration ===${NC}"
kubectl get configmap service-config-sharded -n $APP_NAMESPACE -o yaml

# Check if social graph needs initialization
echo -e "\n${GREEN}=== Initializing Social Graph ===${NC}"
echo "Social graph may need to be initialized using:"
echo "python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=$GATEWAY_IP --port=80"
echo -e "${YELLOW}This step is REQUIRED for the first deployment.${NC}"

echo -e "\n${GREEN}=== Debugging complete ===${NC}"
echo "After fixing any issues, try running the benchmark again."