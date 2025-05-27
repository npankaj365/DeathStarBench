#!/bin/bash
#
# Script to enable sharding for DeathStarBench social network
# This converts standalone Redis and MongoDB to sharded clusters
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="social-network"
TEMP_DIR="./temp-k8s-config"
mkdir -p "$TEMP_DIR"

echo -e "${GREEN}Enabling sharding for DeathStarBench social network...${NC}"
echo -e "${YELLOW}Warning: This will modify your current deployment and restart services.${NC}"
echo -e "${YELLOW}Make sure you have enough resources in your cluster.${NC}"
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
fi

# Step 1: Create Helm values with sharding enabled
echo -e "${GREEN}Creating Helm values with sharding enabled...${NC}"

cat > "$TEMP_DIR/sharded-values.yaml" <<EOF
global:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 200m
      memory: 256Mi
  imagePullPolicy: "IfNotPresent"
  restartPolicy: Always
  serviceType: ClusterIP
  dockerRegistry: docker.io
  defaultImageVersion: latest
  redis:
    cluster:
      enabled: true
    standalone:
      enabled: false
    replication:
      enabled: false
  memcached:
    cluster:
      enabled: true
      port: 5000
    standalone:
      enabled: false
  mongodb:
    standalone:
      enabled: false
    sharding:
      enabled: true
      svc:
        name: "mongodb-sharded"
        user: "root"
        password: "password"
        port: 27017

# Redis Cluster Configuration
redis-cluster:
  usePassword: false
  cluster:
    slaveCount: 1
    nodes: 6
  redis:
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 128Mi
    readinessProbe:
      enabled: false
    livenessProbe:
      enabled: false

# MongoDB Sharded Configuration
mongodb-sharded:
  fullnameOverride: mongodb-sharded
  auth:
    rootPassword: password
  shards: 2
  shardsvr:
    dataNode:
      replicaCount: 2
  configsvr:
    replicaCount: 2
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

# Memcached Cluster Configuration
mcrouter:
  controller: statefulset
  memcached:
    replicaCount: 3
  mcrouterCommandParams:
    port: 5000
EOF

# Step 2: Create service config for sharded setup
echo -e "${GREEN}Creating service config for sharded setup...${NC}"

cat > "$TEMP_DIR/sharded-service-config.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: service-config-sharded
  namespace: $NAMESPACE
data:
  service-config.json: |
    {
      "secret": "secret",
      "social-graph-service": {
        "addr": "social-graph-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "social-graph-mongodb": {
        "addr": "mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "social-graph-redis": {
        "addr": "redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1,
        "use_replica": 0
      },
      "home-timeline-service": {
        "addr": "home-timeline-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "home-timeline-redis": {
        "addr": "redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1,
        "use_replica": 0
      },
      "compose-post-service": {
        "addr": "compose-post-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "compose-post-redis": {
        "addr": "redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1
      },
      "user-timeline-service": {
        "addr": "user-timeline-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-timeline-mongodb": {
        "addr": "mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-timeline-redis": {
        "addr": "redis-cluster",
        "port": 6379,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "use_cluster": 1,
        "use_replica": 0
      },
      "post-storage-service": {
        "addr": "post-storage-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "post-storage-mongodb": {
        "addr": "mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "post-storage-memcached": {
        "addr": "mcrouter-mcrouter",
        "port": 5000,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "url-shorten-service": {
        "addr": "url-shorten-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "url-shorten-mongodb": {
        "addr": "mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "url-shorten-memcached": {
        "addr": "mcrouter-mcrouter",
        "port": 5000,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "user-service": {
        "addr": "user-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-mongodb": {
        "addr": "mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-memcached": {
        "addr": "mcrouter-mcrouter",
        "port": 5000,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "media-service": {
        "addr": "media-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "media-mongodb": {
        "addr": "mongodb-sharded",
        "port": 27017,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "media-memcached": {
        "addr": "mcrouter-mcrouter",
        "port": 5000,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "text-service": {
        "addr": "text-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "unique-id-service": {
        "addr": "unique-id-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      },
      "user-mention-service": {
        "addr": "user-mention-service",
        "port": 9090,
        "connections": 512,
        "timeout_ms": 10000,
        "keepalive_ms": 10000
      }
    }
EOF

# Step 3: Install Helm dependencies if they don't exist
echo -e "${GREEN}Checking if Helm dependencies are installed...${NC}"

# Check if Bitnami repo is added
if ! helm repo list | grep -q "bitnami"; then
  echo -e "${YELLOW}Adding Bitnami Helm repository...${NC}"
  helm repo add bitnami https://charts.bitnami.com/bitnami
fi

# Check if Redis cluster chart exists
if ! helm show chart bitnami/redis-cluster &>/dev/null; then
  echo -e "${YELLOW}Redis cluster chart not found, updating Helm repositories...${NC}"
  helm repo update
fi

# Step 4: Apply service config and other necessary configurations
echo -e "${GREEN}Applying service config for sharded setup...${NC}"
kubectl apply -f "$TEMP_DIR/sharded-service-config.yaml"

# Create ConfigMap mount path patch
cat > "$TEMP_DIR/configmap-patch.yaml" <<EOF
spec:
  template:
    spec:
      containers:
      - name: {{containerName}}
        volumeMounts:
        - name: service-config-sharded-volume
          mountPath: /social-network-microservices/config/service-config.json
          subPath: service-config.json
      volumes:
      - name: service-config-sharded-volume
        configMap:
          name: service-config-sharded
EOF

# Step 5: Deploy or upgrade with sharding enabled
echo -e "${GREEN}Deploying with sharding enabled...${NC}"

# Backup current release before upgrading
if helm list -n $NAMESPACE | grep -q "social-network"; then
  echo -e "${YELLOW}Backing up current release before upgrading...${NC}"
  helm get values social-network -n $NAMESPACE > "$TEMP_DIR/previous-values.yaml"
fi

# First, deploy/upgrade Redis Cluster and MongoDB Sharded
echo -e "${GREEN}Installing/upgrading Redis Cluster...${NC}"
helm upgrade --install redis-cluster bitnami/redis-cluster \
  --namespace $NAMESPACE \
  --set usePassword=false \
  --set cluster.slaveCount=1 \
  --set cluster.nodes=6 \
  --set metrics.enabled=false

echo -e "${GREEN}Installing/upgrading MongoDB Sharded...${NC}"
helm upgrade --install mongodb-sharded bitnami/mongodb-sharded \
  --namespace $NAMESPACE \
  --set auth.rootPassword=password \
  --set shards=2 \
  --set shardsvr.dataNode.replicaCount=2 \
  --set configsvr.replicaCount=2

echo -e "${GREEN}Installing/upgrading Mcrouter for Memcached clustering...${NC}"
helm upgrade --install mcrouter bitnami/mcrouter \
  --namespace $NAMESPACE \
  --set memcached.replicaCount=3 \
  --set mcrouterCommandParams.port=5000

# Now, update the main application with sharding config
echo -e "${GREEN}Updating social-network with sharding configuration...${NC}"
helm upgrade social-network ./helm-chart/socialnetwork \
  --namespace $NAMESPACE \
  -f "$TEMP_DIR/sharded-values.yaml"

# Step 6: Patch deployments to use the new service config
echo -e "${GREEN}Patching deployments to use the sharded service config...${NC}"

# Get all service deployments
SERVICE_DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -l "app.kubernetes.io/part-of=social-network" -o name 2>/dev/null || kubectl get deployments -n $NAMESPACE -o name)

for DEPLOYMENT in $SERVICE_DEPLOYMENTS; do
  DEPLOYMENT_NAME=$(echo $DEPLOYMENT | cut -d '/' -f 2)
  
  # Skip database deployments
  if [[ $DEPLOYMENT_NAME == *"mongodb"* ]] || [[ $DEPLOYMENT_NAME == *"redis"* ]] || [[ $DEPLOYMENT_NAME == *"memcached"* ]] || [[ $DEPLOYMENT_NAME == *"mcrouter"* ]]; then
    continue
  fi
  
  echo -e "${GREEN}Patching deployment $DEPLOYMENT_NAME...${NC}"
  
  # Get the container name
  CONTAINER_NAME=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null || echo $DEPLOYMENT_NAME)
  
  # Create the patch file with container name
  sed "s/{{containerName}}/$CONTAINER_NAME/g" "$TEMP_DIR/configmap-patch.yaml" > "$TEMP_DIR/$DEPLOYMENT_NAME-patch.yaml"
  
  # Apply the patch
  kubectl patch deployment $DEPLOYMENT_NAME -n $NAMESPACE --patch "$(cat $TEMP_DIR/$DEPLOYMENT_NAME-patch.yaml)" || echo -e "${YELLOW}Could not patch $DEPLOYMENT_NAME, may need manual configuration.${NC}"
done

# Step 7: Wait for deployments to be ready
echo -e "${GREEN}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=600s deployment --all -n $NAMESPACE || true

# Get service endpoints
INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$INGRESS_IP" ]; then
  INGRESS_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
fi

# Summary
echo -e "\n${GREEN}DeathStarBench social network sharding setup complete!${NC}"
echo -e "The following changes were made:"
echo -e "1. Switched MongoDB to sharded cluster with 2 shards"
echo -e "2. Enabled Redis cluster with 6 nodes (3 masters, 3 replicas)"
echo -e "3. Configured Memcached clustering with Mcrouter"
echo -e "4. Updated service configurations to use sharded databases"
echo -e "5. Patched deployments to use the new configurations"

if [ -n "$INGRESS_IP" ]; then
  echo -e "\n${GREEN}Access URLs:${NC}"
  echo -e "Main Frontend:  ${YELLOW}http://$INGRESS_IP${NC}"
  echo -e "Media Frontend: ${YELLOW}http://$INGRESS_IP/media${NC}"
  echo -e "Jaeger UI:      ${YELLOW}http://$INGRESS_IP:16686${NC}"
else
  echo -e "\n${YELLOW}Istio ingress gateway address not found.${NC}"
  echo -e "${YELLOW}You can check the status with: kubectl -n istio-system get service istio-ingressgateway${NC}"
fi

echo -e "\n${YELLOW}Important Notes:${NC}"
echo -e "1. Sharded setup requires more resources than standalone - ensure your cluster has enough capacity"
echo -e "2. The first requests after deployment may be slow while shards initialize"
echo -e "3. You may need to re-initialize the social graph: python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=$INGRESS_IP --port=80"
echo -e "4. If you experience issues, check pods with: kubectl get pods -n $NAMESPACE"
echo -e "5. View database statuses with: kubectl get pods -n $NAMESPACE | grep 'mongodb\\|redis\\|mcrouter'"

echo -e "\n${GREEN}Next steps:${NC}"
echo -e "1. Run your benchmarks again to see if performance has improved"
echo -e "2. Monitor database performance with: kubectl top pods -n $NAMESPACE"