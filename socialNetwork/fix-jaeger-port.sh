#!/bin/bash
# Script to fix Jaeger port exposure in the Istio ingress gateway

set -e

NAMESPACE="social-network"
echo "Fixing Jaeger port exposure for DeathStarBench social network"

# Check the current Istio ingress gateway service
echo "Checking current Istio ingress gateway service..."
kubectl get svc istio-ingressgateway -n istio-system -o yaml > istio-gateway-svc.yaml

# Patch the Istio ingress gateway service to expose port 16686
echo "Adding port 16686 to Istio ingress gateway service..."
cat > istio-gateway-patch.yaml <<EOF
spec:
  ports:
  - name: jaeger-ui
    port: 16686
    protocol: TCP
    targetPort: 16686
EOF

kubectl patch svc istio-ingressgateway -n istio-system --patch "$(cat istio-gateway-patch.yaml)" --type=strategic

# Remove temporary files
rm -f istio-gateway-svc.yaml istio-gateway-patch.yaml

# Create a dedicated Gateway and VirtualService for Jaeger
echo "Creating a dedicated Gateway and VirtualService for Jaeger..."
cat > jaeger-port-gateway.yaml <<EOF
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
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: jaeger-vs
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

kubectl apply -f jaeger-port-gateway.yaml
rm -f jaeger-port-gateway.yaml

# Update the Jaeger service to ensure it's correctly defined
echo "Updating Jaeger service definition..."
cat > jaeger-service-updated.yaml <<EOF
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
    name: http-ui
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

kubectl apply -f jaeger-service-updated.yaml
rm -f jaeger-service-updated.yaml

# Get Istio Ingress Gateway IP
INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$INGRESS_IP" ]; then
  INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

# Create a NodePort service for Jaeger as a fallback option
echo "Creating a NodePort service for Jaeger as a fallback option..."
cat > jaeger-nodeport.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jaeger-nodeport
  namespace: $NAMESPACE
  labels:
    service: jaeger
spec:
  type: NodePort
  ports:
  - port: 16686
    nodePort: 30686
    name: http-ui
    targetPort: 16686
  selector:
    service: jaeger
EOF

kubectl apply -f jaeger-nodeport.yaml
rm -f jaeger-nodeport.yaml

# Get a node IP for the NodePort fallback
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
if [ -z "$NODE_IP" ]; then
  NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
fi

echo ""
echo "Jaeger port exposure fixes applied!"
echo "Try accessing Jaeger UI through Istio gateway: http://$INGRESS_IP:16686"
echo ""
echo "If that doesn't work, try the NodePort fallback: http://$NODE_IP:30686"
echo ""
echo "You can check the status of Jaeger with: kubectl get pods,svc -n $NAMESPACE -l service=jaeger"
echo "And check the Istio gateway with: kubectl get svc -n istio-system istio-ingressgateway"