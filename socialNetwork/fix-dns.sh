#!/bin/bash
# Script to fix DNS issues in the social network deployment

set -e

NAMESPACE="social-network"
echo "Fixing DNS configuration for social network in namespace: $NAMESPACE"

# First, find the correct DNS service
echo "Checking DNS configuration in the cluster..."
COREDNS_IP=$(kubectl get svc -n kube-system | grep dns | head -1 | awk '{print $3}')
echo "Detected DNS service IP: $COREDNS_IP"

# Create a values file with the correct DNS configuration
cat > dns-fix-values.yaml <<EOF
global:
  replicas: 1
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi
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
  jaeger:
    localAgentHostPort: jaeger:6831
    samplerType: probabilistic
    samplerParam: 0.1
    disabled: false
  # Use the detected DNS IP directly
  nginx:
    resolverName: $COREDNS_IP
EOF

echo "Updating deployment with correct DNS configuration..."
helm upgrade social-network ./helm-chart/socialnetwork \
  --namespace $NAMESPACE \
  -f dns-fix-values.yaml

echo "Deployment updated. Pods should restart with the correct DNS configuration."
echo "Monitor the status with: kubectl get pods -n $NAMESPACE"