#!/bin/bash
# Script to access Jaeger UI through port forwarding

set -e

NAMESPACE="social-network"
echo "Setting up port forwarding for Jaeger UI in namespace: $NAMESPACE"

# Find the Jaeger pod
JAEGER_POD=$(kubectl get pods -n $NAMESPACE -l service=jaeger -o jsonpath='{.items[0].metadata.name}')

if [ -z "$JAEGER_POD" ]; then
  echo "Jaeger pod not found. Make sure Jaeger is deployed."
  exit 1
fi

echo "Found Jaeger pod: $JAEGER_POD"
echo "Setting up port forwarding from local port 16686 to pod port 16686..."
echo "Access Jaeger UI at: http://localhost:16686"
echo "Press Ctrl+C to stop port forwarding"

# Start port forwarding
kubectl port-forward -n $NAMESPACE $JAEGER_POD 16686:16686