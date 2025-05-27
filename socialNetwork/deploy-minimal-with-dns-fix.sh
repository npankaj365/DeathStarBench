#!/bin/bash
#
# Minimal Kubernetes and Istio Deployment Script for DeathStarBench Social Network
# With DNS resolver fix
#

set -e

# Default values
NAMESPACE="social-network"
REPLICAS=1

# Setup
echo "Setting up deployment..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$SCRIPT_DIR/temp-k8s-config"
mkdir -p "$TEMP_DIR"

# Get DNS service IP
echo "Detecting Kubernetes DNS service..."
DNS_IP=$(kubectl get svc -n kube-system | grep dns | head -1 | awk '{print $3}')
if [ -z "$DNS_IP" ]; then
  echo "Could not detect DNS service IP. Using default: 10.96.0.10"
  DNS_IP="10.96.0.10"
else
  echo "Detected DNS service IP: $DNS_IP"
fi

# Step 1: Create namespace
echo "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml > "$TEMP_DIR/namespace.yaml"
kubectl apply -f "$TEMP_DIR/namespace.yaml"

# Step 2: Enable Istio injection
echo "Enabling Istio injection for namespace: $NAMESPACE"
kubectl label namespace $NAMESPACE istio-injection=enabled --overwrite

# Step 3: Create Istio Gateway
echo "Creating Istio Gateway..."
cat > "$TEMP_DIR/gateway.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
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
    - "*"
EOF
kubectl apply -f "$TEMP_DIR/gateway.yaml"

# Step 4: Create Virtual Services
echo "Creating Virtual Services..."
cat > "$TEMP_DIR/nginx-vs.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: nginx-thrift
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
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
          number: 8080
EOF
kubectl apply -f "$TEMP_DIR/nginx-vs.yaml"

cat > "$TEMP_DIR/media-vs.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: media-frontend
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
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
          number: 8080
EOF
kubectl apply -f "$TEMP_DIR/media-vs.yaml"

# Step 5: Create Helm Values with DNS fix
echo "Preparing Helm values with DNS fix..."
cat > "$TEMP_DIR/values.yaml" <<EOF
global:
  replicas: $REPLICAS
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
  nginx:
    # Use the detected DNS IP directly
    resolverName: $DNS_IP
EOF

# Step 6: Deploy with Helm
echo "Deploying with Helm..."
helm upgrade --install social-network "$SCRIPT_DIR/helm-chart/socialnetwork" \
  --namespace $NAMESPACE \
  --create-namespace \
  -f "$TEMP_DIR/values.yaml"

echo "Deployment completed successfully!"
echo "You can check the status with: kubectl get pods -n $NAMESPACE"
echo "Initialize the social graph with: python3 scripts/init_social_graph.py"

# Keep the temp files for debugging
echo "Temporary files are in $TEMP_DIR"