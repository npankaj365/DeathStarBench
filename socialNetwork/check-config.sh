#!/bin/bash
# Script to check the nginx configuration and DNS setup

set -e

NAMESPACE="social-network"

# Get the pod name
NGINX_POD=$(kubectl get pods -n $NAMESPACE -l service=nginx-thrift -o jsonpath='{.items[0].metadata.name}')
MEDIA_POD=$(kubectl get pods -n $NAMESPACE -l service=media-frontend -o jsonpath='{.items[0].metadata.name}')

if [ -n "$NGINX_POD" ]; then
  echo "Nginx pod found: $NGINX_POD"
  
  # Check the pod details
  echo "=== Pod Details ==="
  kubectl describe pod -n $NAMESPACE $NGINX_POD
  
  # Try to check the nginx configuration
  echo "=== Attempting to view nginx.conf ==="
  kubectl exec -n $NAMESPACE $NGINX_POD -c nginx-thrift -- cat /usr/local/openresty/nginx/conf/nginx.conf || echo "Failed to get nginx.conf"
else
  echo "No nginx-thrift pod found"
fi

# Show DNS config in the cluster
echo "=== Kubernetes DNS configuration ==="
kubectl get svc -n kube-system | grep dns

# Show endpoints for the DNS service
echo "=== DNS Service Endpoints ==="
kubectl get endpoints -n kube-system | grep dns