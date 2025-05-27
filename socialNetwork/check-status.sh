#!/bin/bash
# Script to check the status of the DeathStarBench social network deployment

set -e

NAMESPACE="social-network"
echo "Checking status of DeathStarBench social network in namespace: $NAMESPACE"

# Check pod status
echo "=== Pod Status ==="
kubectl get pods -n $NAMESPACE

# Check services
echo -e "\n=== Services ==="
kubectl get services -n $NAMESPACE

# Check Istio resources
echo -e "\n=== Istio Gateways ==="
kubectl get gateways -n $NAMESPACE

echo -e "\n=== Istio Virtual Services ==="
kubectl get virtualservices -n $NAMESPACE

# Get ingress gateway info
echo -e "\n=== Istio Ingress Gateway ==="
INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$INGRESS_IP" ]; then
  INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

if [ -z "$INGRESS_IP" ]; then
  echo "Istio Ingress Gateway IP/hostname not found."
  echo "Check the status with: kubectl -n istio-system get service istio-ingressgateway"
else
  echo "Istio Ingress Gateway: $INGRESS_IP"
  echo "Access URLs:"
  echo "  Main Frontend:  http://$INGRESS_IP"
  echo "  Media Frontend: http://$INGRESS_IP/media"
  echo "  Jaeger UI:      http://$INGRESS_IP:16686"
fi

# Check for any issues
echo -e "\n=== Checking for issues ==="
CRASHING_PODS=$(kubectl get pods -n $NAMESPACE | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' | wc -l)

if [ "$CRASHING_PODS" -gt "0" ]; then
  echo "Found pods with issues. Showing logs for problematic pods:"
  
  PROBLEM_PODS=$(kubectl get pods -n $NAMESPACE | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' | awk '{print $1}')
  
  for POD in $PROBLEM_PODS; do
    echo -e "\n=== Logs for $POD ==="
    kubectl logs -n $NAMESPACE $POD --tail=20 || echo "Could not get logs for $POD"
    
    echo -e "\n=== Details for $POD ==="
    kubectl describe pod -n $NAMESPACE $POD | grep -A 10 "Events:" || echo "Could not get details for $POD"
  done
else
  echo "No pods with obvious issues found."
fi

echo -e "\nStatus check completed."