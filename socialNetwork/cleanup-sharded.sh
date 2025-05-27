#!/bin/bash
#
# Cleanup script for DeathStarBench social network deployments
# Properly removes all resources including sharded databases
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default namespace
NAMESPACE="social-network"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --namespace NAME      Kubernetes namespace to clean up (default: social-network)"
      echo "  --help                Display this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $key${NC}"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}Cleaning up DeathStarBench social network deployment...${NC}"
echo -e "Namespace: ${YELLOW}$NAMESPACE${NC}"

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
  echo -e "${YELLOW}Namespace $NAMESPACE does not exist. Nothing to clean up.${NC}"
  exit 0
fi

# Delete all Helm releases first
echo -e "${GREEN}Deleting Helm releases...${NC}"
HELM_RELEASES=$(helm list -n $NAMESPACE -q 2>/dev/null || echo "")
for RELEASE in $HELM_RELEASES; do
  echo -e "${GREEN}Deleting Helm release $RELEASE in namespace $NAMESPACE...${NC}"
  helm uninstall $RELEASE -n $NAMESPACE --wait || true
done

# Delete any remaining resources
echo -e "${GREEN}Deleting remaining Kubernetes resources...${NC}"
kubectl delete all --all -n $NAMESPACE --grace-period=0 --force || true
kubectl delete configmaps --all -n $NAMESPACE --grace-period=0 --force || true
kubectl delete secrets --all -n $NAMESPACE --grace-period=0 --force || true
kubectl delete pvc --all -n $NAMESPACE --grace-period=0 --force || true

# Delete Istio resources
echo -e "${GREEN}Deleting Istio resources...${NC}"
kubectl delete gateways --all -n $NAMESPACE --grace-period=0 --force || true
kubectl delete virtualservices --all -n $NAMESPACE --grace-period=0 --force || true
kubectl delete destinationrules --all -n $NAMESPACE --grace-period=0 --force || true

# Delete the namespace
echo -e "${GREEN}Deleting namespace $NAMESPACE...${NC}"
kubectl delete namespace $NAMESPACE --grace-period=0 --force || true

# Wait for namespace to be fully deleted
echo -e "${YELLOW}Waiting for namespace $NAMESPACE to be deleted...${NC}"
while kubectl get namespace $NAMESPACE &>/dev/null; do
  sleep 2
done

echo -e "\n${GREEN}Cleanup complete!${NC}"
echo -e "You can now run the deployment script again."