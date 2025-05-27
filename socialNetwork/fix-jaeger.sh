#!/bin/bash
# Script to fix Jaeger access in DeathStarBench social network

set -e

NAMESPACE="social-network"
echo "Setting up Jaeger for DeathStarBench social network in namespace: $NAMESPACE"

# Check if Jaeger is running
JAEGER_POD=$(kubectl get pods -n $NAMESPACE -l service=jaeger -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$JAEGER_POD" ]; then
  echo "Jaeger pod not found. Setting up Jaeger..."
  
  # Create Jaeger deployment
  echo "Creating Jaeger deployment..."
  cat > jaeger-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jaeger
  namespace: $NAMESPACE
  labels:
    service: jaeger
spec:
  replicas: 1
  selector:
    matchLabels:
      service: jaeger
  template:
    metadata:
      labels:
        service: jaeger
    spec:
      containers:
      - name: jaeger
        image: jaegertracing/all-in-one:latest
        ports:
        - containerPort: 5775
          protocol: UDP
        - containerPort: 6831
          protocol: UDP
        - containerPort: 6832
          protocol: UDP
        - containerPort: 5778
        - containerPort: 16686
        - containerPort: 14268
        - containerPort: 9411
        env:
        - name: COLLECTOR_ZIPKIN_HTTP_PORT
          value: "9411"
EOF
  kubectl apply -f jaeger-deployment.yaml
else
  echo "Jaeger pod found: $JAEGER_POD"
fi

# Create Jaeger service
echo "Creating Jaeger service..."
cat > jaeger-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jaeger
  namespace: $NAMESPACE
  labels:
    service: jaeger
spec:
  type: ClusterIP
  ports:
  - port: 5775
    name: udp-5775
    protocol: UDP
    targetPort: 5775
  - port: 6831
    name: udp-6831
    protocol: UDP
    targetPort: 6831
  - port: 6832
    name: udp-6832
    protocol: UDP
    targetPort: 6832
  - port: 5778
    name: tcp-5778
    targetPort: 5778
  - port: 16686
    name: tcp-16686
    targetPort: 16686
  - port: 14268
    name: tcp-14268
    targetPort: 14268
  - port: 9411
    name: tcp-9411
    targetPort: 9411
  selector:
    service: jaeger
EOF
kubectl apply -f jaeger-service.yaml

# Create Istio Gateway for Jaeger UI
echo "Creating Istio Gateway rule for Jaeger UI..."
cat > jaeger-gateway.yaml <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: jaeger-gateway
  namespace: $NAMESPACE
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 16686
      name: http-jaeger
      protocol: HTTP
    hosts:
    - "*"
EOF
kubectl apply -f jaeger-gateway.yaml

# Create Virtual Service for Jaeger UI
echo "Creating Virtual Service for Jaeger UI..."
cat > jaeger-virtualservice.yaml <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: jaeger
  namespace: $NAMESPACE
spec:
  hosts:
  - "*"
  gateways:
  - jaeger-gateway
  http:
  - match:
    - port: 16686
    route:
    - destination:
        host: jaeger
        port:
          number: 16686
EOF
kubectl apply -f jaeger-virtualservice.yaml

# Get Istio Ingress Gateway IP
INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$INGRESS_IP" ]; then
  INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

echo ""
echo "Jaeger setup completed!"
echo "Jaeger UI should be accessible at: http://$INGRESS_IP:16686"
echo "Note: It may take a few minutes for the Jaeger pod to start and the UI to become accessible."
echo "You can check the status with: kubectl get pods -n $NAMESPACE -l service=jaeger"