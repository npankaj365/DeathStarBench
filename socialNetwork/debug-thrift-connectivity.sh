#!/bin/bash
# Script to debug Thrift connectivity issues in social network

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_NAMESPACE="social-network"
DB_NAMESPACE="social-network-db"

echo -e "${GREEN}=== Debugging Thrift Communication Issues ===${NC}"

# Check the status of critical services
echo -e "\n${GREEN}=== Critical Service Status ===${NC}"
kubectl get pods -n $APP_NAMESPACE -l service=user-service
kubectl get pods -n $APP_NAMESPACE -l service=nginx-thrift
kubectl get pods -n $APP_NAMESPACE -l service=social-graph-service

# Check user-service logs
echo -e "\n${GREEN}=== User Service Logs ===${NC}"
USER_SERVICE_POD=$(kubectl get pods -n $APP_NAMESPACE -l service=user-service -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$USER_SERVICE_POD" ]; then
  # Try alternative label format
  USER_SERVICE_POD=$(kubectl get pods -n $APP_NAMESPACE | grep user-service | head -1 | awk '{print $1}')
fi

if [ -n "$USER_SERVICE_POD" ]; then
  echo -e "${YELLOW}--- Last 50 lines of logs for user-service ($USER_SERVICE_POD) ---${NC}"
  kubectl logs -n $APP_NAMESPACE $USER_SERVICE_POD --tail=50
else
  echo -e "${RED}No pod found for user-service${NC}"
fi

# Check nginx-thrift logs
echo -e "\n${GREEN}=== Nginx Thrift Logs ===${NC}"
NGINX_POD=$(kubectl get pods -n $APP_NAMESPACE -l service=nginx-thrift -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$NGINX_POD" ]; then
  # Try alternative label format
  NGINX_POD=$(kubectl get pods -n $APP_NAMESPACE | grep nginx-thrift | head -1 | awk '{print $1}')
fi

if [ -n "$NGINX_POD" ]; then
  echo -e "${YELLOW}--- Last 50 lines of logs for nginx-thrift ($NGINX_POD) ---${NC}"
  kubectl logs -n $APP_NAMESPACE $NGINX_POD --tail=50
else
  echo -e "${RED}No pod found for nginx-thrift${NC}"
fi

# Check service endpoints
echo -e "\n${GREEN}=== Service Endpoints ===${NC}"
kubectl get endpoints -n $APP_NAMESPACE user-service
kubectl get endpoints -n $APP_NAMESPACE nginx-thrift
kubectl get endpoints -n $APP_NAMESPACE social-graph-service

# Check if services can communicate with each other
echo -e "\n${GREEN}=== Service Connectivity Test ===${NC}"

if [ -n "$NGINX_POD" ]; then
  echo -e "${YELLOW}Testing connectivity from nginx-thrift to user-service:${NC}"
  kubectl exec -n $APP_NAMESPACE $NGINX_POD -- sh -c "nc -zv user-service 9090" || echo "Failed to connect to user-service"
  
  echo -e "${YELLOW}Testing connectivity from nginx-thrift to social-graph-service:${NC}"
  kubectl exec -n $APP_NAMESPACE $NGINX_POD -- sh -c "nc -zv social-graph-service 9090" || echo "Failed to connect to social-graph-service"
else
  echo -e "${RED}Cannot test connectivity without nginx-thrift pod${NC}"
fi

# Check the service-config.json
echo -e "\n${GREEN}=== Service Configuration ===${NC}"
if [ -n "$USER_SERVICE_POD" ]; then
  echo -e "${YELLOW}Checking service-config.json in user-service pod:${NC}"
  kubectl exec -n $APP_NAMESPACE $USER_SERVICE_POD -- cat /social-network-microservices/config/service-config.json || echo "Failed to read service-config.json"
else
  echo -e "${RED}Cannot check service-config.json without user-service pod${NC}"
fi

# Check if services are actually running inside pods
echo -e "\n${GREEN}=== Process Check ===${NC}"
if [ -n "$USER_SERVICE_POD" ]; then
  echo -e "${YELLOW}Checking processes in user-service pod:${NC}"
  kubectl exec -n $APP_NAMESPACE $USER_SERVICE_POD -- ps aux || echo "Failed to check processes"
else
  echo -e "${RED}Cannot check processes without user-service pod${NC}"
fi

# Check MongoDB status for user-service
echo -e "\n${GREEN}=== MongoDB Status ===${NC}"
echo -e "${YELLOW}Checking MongoDB endpoints:${NC}"
kubectl get endpoints -n $APP_NAMESPACE mongodb-sharded

if [ -n "$USER_SERVICE_POD" ]; then
  echo -e "${YELLOW}Testing connectivity from user-service to MongoDB:${NC}"
  kubectl exec -n $APP_NAMESPACE $USER_SERVICE_POD -- sh -c "nc -zv mongodb-sharded 27017" || echo "Failed to connect to MongoDB"
else
  echo -e "${RED}Cannot test MongoDB connectivity without user-service pod${NC}"
fi

# Check if DNS resolution is working
echo -e "\n${GREEN}=== DNS Resolution Check ===${NC}"
if [ -n "$USER_SERVICE_POD" ]; then
  echo -e "${YELLOW}Testing DNS resolution from user-service:${NC}"
  kubectl exec -n $APP_NAMESPACE $USER_SERVICE_POD -- nslookup mongodb-sharded || echo "Failed to resolve MongoDB"
  kubectl exec -n $APP_NAMESPACE $USER_SERVICE_POD -- nslookup nginx-thrift || echo "Failed to resolve nginx-thrift"
else
  echo -e "${RED}Cannot test DNS resolution without user-service pod${NC}"
fi

# Provide some potential fixes
echo -e "\n${GREEN}=== Potential Fixes ===${NC}"
echo -e "1. Check that all services are running correctly"
echo -e "2. Verify that service-config.json is mounted correctly in all pods"
echo -e "3. Ensure MongoDB and Redis are accessible from application namespace"
echo -e "4. Restart problematic services: kubectl rollout restart deployment user-service -n $APP_NAMESPACE"
echo -e "5. Check that DNS resolution is working between pods"
echo -e "6. Verify that the ExternalName services are correctly set up for cross-namespace communication"

echo -e "\n${GREEN}=== Next Steps ===${NC}"
echo -e "1. Fix any identified issues"
echo -e "2. Restart services if needed: kubectl rollout restart deployment -n $APP_NAMESPACE"
echo -e "3. Try initializing the social graph again: python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=\$GATEWAY_IP --port=80"