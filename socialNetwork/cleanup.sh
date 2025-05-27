#!/bin/bash
# Script to clean up the DeathStarBench social network deployment

set -e

NAMESPACE="social-network"
echo "Cleaning up DeathStarBench social network deployment in namespace: $NAMESPACE"

# Delete the Helm release
echo "Deleting Helm release..."
helm uninstall social-network -n $NAMESPACE || true

# Delete all resources in the namespace
echo "Deleting all resources in namespace $NAMESPACE..."
kubectl delete all --all -n $NAMESPACE || true

# Delete Istio gateway and virtual services
echo "Deleting Istio resources..."
kubectl delete gateway --all -n $NAMESPACE || true
kubectl delete virtualservice --all -n $NAMESPACE || true
kubectl delete destinationrule --all -n $NAMESPACE || true

# Delete the namespace
echo "Deleting namespace $NAMESPACE..."
kubectl delete namespace $NAMESPACE || true

# Remove temporary files
echo "Cleaning up temporary files..."
rm -rf temp-k8s-config || true

echo "Cleanup completed. You can now run deploy-minimal.sh to start fresh."