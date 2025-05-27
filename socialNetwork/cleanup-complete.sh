#!/bin/bash
# Enhanced cleanup script to remove all resources including Helm releases
# Ensures clean environment for deploy-complete-sharded.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="social-network"
echo -e "${YELLOW}Performing complete cleanup of DeathStarBench social network deployment in namespace: $NAMESPACE${NC}"
echo -e "${RED}Warning: This will delete ALL resources in the namespace, including data.${NC}"
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborted.${NC}"
    exit 1
fi

# List all Helm releases in the namespace
echo -e "${GREEN}Listing all Helm releases in namespace $NAMESPACE...${NC}"
HELM_RELEASES=$(helm list -n $NAMESPACE -q 2>/dev/null || echo "")

if [ -n "$HELM_RELEASES" ]; then
    echo -e "${GREEN}Found the following Helm releases:${NC}"
    echo "$HELM_RELEASES"
    
    # Delete each Helm release individually
    for RELEASE in $HELM_RELEASES; do
        echo -e "${GREEN}Deleting Helm release: $RELEASE${NC}"
        helm uninstall $RELEASE -n $NAMESPACE || true
    done
else
    echo -e "${YELLOW}No Helm releases found in namespace $NAMESPACE.${NC}"
fi

# Delete all resources in the namespace
echo -e "${GREEN}Deleting all resources in namespace $NAMESPACE...${NC}"

# Delete all custom resources first
echo -e "${GREEN}Deleting Istio resources...${NC}"
kubectl delete gateway --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
kubectl delete virtualservice --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true
kubectl delete destinationrule --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all pods with force
echo -e "${GREEN}Force deleting all pods...${NC}"
kubectl delete pods --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all deployments
echo -e "${GREEN}Deleting all deployments...${NC}"
kubectl delete deployments --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all statefulsets
echo -e "${GREEN}Deleting all statefulsets...${NC}"
kubectl delete statefulsets --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all services
echo -e "${GREEN}Deleting all services...${NC}"
kubectl delete services --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all configmaps
echo -e "${GREEN}Deleting all configmaps...${NC}"
kubectl delete configmaps --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all secrets
echo -e "${GREEN}Deleting all secrets...${NC}"
kubectl delete secrets --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all PVCs
echo -e "${GREEN}Deleting all persistent volume claims...${NC}"
kubectl delete pvc --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete all remaining resources
echo -e "${GREEN}Deleting all remaining resources...${NC}"
kubectl delete all --all -n $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Delete the namespace and recreate it
echo -e "${GREEN}Deleting namespace $NAMESPACE...${NC}"
kubectl delete namespace $NAMESPACE --grace-period=0 --force 2>/dev/null || true

# Wait to ensure namespace is fully deleted
echo -e "${YELLOW}Waiting for namespace deletion to complete...${NC}"
while kubectl get namespace $NAMESPACE 2>/dev/null; do
    echo -e "${YELLOW}Namespace $NAMESPACE still exists, waiting...${NC}"
    sleep 5
done

# Recreate the namespace
echo -e "${GREEN}Recreating namespace $NAMESPACE...${NC}"
kubectl create namespace $NAMESPACE

# Re-enable Istio injection
echo -e "${GREEN}Re-enabling Istio injection for namespace $NAMESPACE...${NC}"
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# Remove temporary files
echo -e "${GREEN}Cleaning up temporary files...${NC}"
rm -rf temp-k8s-config || true

echo -e "${GREEN}Cleanup completed. You can now run deploy-complete-sharded.sh without conflicts.${NC}"
echo -e "${GREEN}Note: Namespace $NAMESPACE has been recreated with Istio injection enabled.${NC}"