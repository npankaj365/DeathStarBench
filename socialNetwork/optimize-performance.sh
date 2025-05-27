#!/bin/bash
#
# Performance optimization script for DeathStarBench social network
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

echo -e "${GREEN}Optimizing DeathStarBench social network performance...${NC}"

# Step 1: Increase resource limits for critical services
echo -e "${GREEN}Increasing resource limits for critical services...${NC}"

cat > "$TEMP_DIR/optimize-values.yaml" <<EOF
global:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 256Mi

nginx-thrift:
  container:
    resources:
      limits:
        cpu: 2000m
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 512Mi

media-frontend:
  container:
    resources:
      limits:
        cpu: 2000m
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 512Mi

compose-post-service:
  container:
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 300m
        memory: 512Mi

post-storage-service:
  container:
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 300m
        memory: 512Mi

user-timeline-service:
  container:
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 300m
        memory: 512Mi

user-service:
  container:
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 300m
        memory: 512Mi

home-timeline-service:
  container:
    resources:
      limits:
        cpu: 1000m
        memory: 1Gi
      requests:
        cpu: 300m
        memory: 512Mi
EOF

echo -e "${GREEN}Applying resource optimizations via Helm...${NC}"
helm upgrade social-network ./helm-chart/socialnetwork -n $NAMESPACE -f "$TEMP_DIR/optimize-values.yaml"

# Step 2: Optimize MongoDB and Redis
echo -e "${GREEN}Creating optimized configs for MongoDB and Redis...${NC}"

cat > "$TEMP_DIR/mongodb-optimize.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-optimize
  namespace: $NAMESPACE
data:
  mongod.conf: |
    # MongoDB configuration optimized for performance
    systemLog:
      destination: file
      path: /data/db/mongod.log
      logAppend: true
    storage:
      dbPath: /data/db
      journal:
        enabled: true
    processManagement:
      fork: false
    net:
      bindIp: 0.0.0.0
      port: 27017
    setParameter:
      cursorTimeoutMillis: 300000
      internalQueryExecMaxBlockingSortBytes: 335544320
    operationProfiling:
      mode: slowOp
      slowOpThresholdMs: 100
EOF

cat > "$TEMP_DIR/redis-optimize.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-optimize
  namespace: $NAMESPACE
data:
  redis.conf: |
    # Redis configuration optimized for performance
    bind 0.0.0.0
    protected-mode yes
    port 6379
    tcp-backlog 511
    timeout 0
    tcp-keepalive 300
    daemonize no
    supervised no
    loglevel notice
    databases 16
    save ""
    stop-writes-on-bgsave-error yes
    rdbcompression yes
    rdbchecksum yes
    maxmemory 512mb
    maxmemory-policy allkeys-lru
    maxclients 10000
    appendonly no
    no-appendfsync-on-rewrite no
    auto-aof-rewrite-percentage 100
    auto-aof-rewrite-min-size 64mb
    lua-time-limit 5000
    slowlog-log-slower-than 10000
    slowlog-max-len 128
    latency-monitor-threshold 0
    notify-keyspace-events ""
    hash-max-ziplist-entries 512
    hash-max-ziplist-value 64
    list-max-ziplist-size -2
    list-compress-depth 0
    set-max-intset-entries 512
    zset-max-ziplist-entries 128
    zset-max-ziplist-value 64
    hll-sparse-max-bytes 3000
    activerehashing yes
    hz 10
    aof-rewrite-incremental-fsync yes
EOF

kubectl apply -f "$TEMP_DIR/mongodb-optimize.yaml"
kubectl apply -f "$TEMP_DIR/redis-optimize.yaml"

# Step 3: Create optimized Istio configurations
echo -e "${GREEN}Creating optimized Istio configurations...${NC}"

cat > "$TEMP_DIR/istio-optimize.yaml" <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: nginx-thrift-optimize
  namespace: $NAMESPACE
spec:
  host: nginx-thrift
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    connectionPool:
      tcp:
        maxConnections: 1000
        connectTimeout: 30ms
        tcpKeepalive:
          time: 300s
          interval: 75s
      http:
        http2MaxRequests: 10000
        maxRequestsPerConnection: 1000
        maxRetries: 5
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: media-frontend-optimize
  namespace: $NAMESPACE
spec:
  host: media-frontend
  trafficPolicy:
    loadBalancer:
      simple: ROUND_ROBIN
    connectionPool:
      tcp:
        maxConnections: 1000
        connectTimeout: 30ms
        tcpKeepalive:
          time: 300s
          interval: 75s
      http:
        http2MaxRequests: 10000
        maxRequestsPerConnection: 1000
        maxRetries: 5
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: nginx-thrift-optimize
  namespace: $NAMESPACE
spec:
  hosts:
  - nginx-thrift
  http:
  - route:
    - destination:
        host: nginx-thrift
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 5s
      retryOn: connect-failure,refused-stream,unavailable,gateway-error,5xx
EOF

kubectl apply -f "$TEMP_DIR/istio-optimize.yaml"

# Step 4: Update connection settings in service-config
echo -e "${GREEN}Creating optimized service-config.json ConfigMap...${NC}"

cat > "$TEMP_DIR/service-config-optimize.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: service-config-optimize
  namespace: $NAMESPACE
data:
  service-config.json: |
    {
      "secret": "secret",
      "social-graph-service": {
        "addr": "social-graph-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "social-graph-mongodb": {
        "addr": "social-graph-mongodb",
        "port": 27017,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "social-graph-redis": {
        "addr": "social-graph-redis",
        "port": 6379,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "use_cluster": 0,
        "use_replica": 0
      },
      "home-timeline-service": {
        "addr": "home-timeline-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "home-timeline-redis": {
        "addr": "home-timeline-redis",
        "port": 6379,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "use_cluster": 0,
        "use_replica": 0
      },
      "compose-post-service": {
        "addr": "compose-post-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "compose-post-redis": {
        "addr": "compose-post-redis",
        "port": 6379,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "use_cluster": 0
      },
      "user-timeline-service": {
        "addr": "user-timeline-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "user-timeline-mongodb": {
        "addr": "user-timeline-mongodb",
        "port": 27017,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "user-timeline-redis": {
        "addr": "user-timeline-redis",
        "port": 6379,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "use_cluster": 0,
        "use_replica": 0
      },
      "post-storage-service": {
        "addr": "post-storage-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "post-storage-mongodb": {
        "addr": "post-storage-mongodb",
        "port": 27017,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "post-storage-memcached": {
        "addr": "post-storage-memcached",
        "port": 11211,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "url-shorten-service": {
        "addr": "url-shorten-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "url-shorten-mongodb": {
        "addr": "url-shorten-mongodb",
        "port": 27017,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "url-shorten-memcached": {
        "addr": "url-shorten-memcached",
        "port": 11211,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "user-service": {
        "addr": "user-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "user-mongodb": {
        "addr": "user-mongodb",
        "port": 27017,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "user-memcached": {
        "addr": "user-memcached",
        "port": 11211,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "media-service": {
        "addr": "media-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "media-mongodb": {
        "addr": "media-mongodb",
        "port": 27017,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "media-memcached": {
        "addr": "media-memcached",
        "port": 11211,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000,
        "binary_protocol": 1
      },
      "text-service": {
        "addr": "text-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "unique-id-service": {
        "addr": "unique-id-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      },
      "user-mention-service": {
        "addr": "user-mention-service",
        "port": 9090,
        "connections": 1000,
        "timeout_ms": 30000,
        "keepalive_ms": 10000
      }
    }
EOF

kubectl apply -f "$TEMP_DIR/service-config-optimize.yaml"

# Step 5: Apply optimized configuration
echo -e "${GREEN}Applying optimized configurations...${NC}"

echo -e "${GREEN}Restarting deployments to apply new configurations...${NC}"
kubectl rollout restart deployment -n $NAMESPACE

echo -e "${GREEN}Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment --all -n $NAMESPACE || true

echo -e "\n${GREEN}Performance optimizations applied!${NC}"
echo -e "The following optimizations were made:"
echo -e "1. Increased CPU and memory resources for critical services"
echo -e "2. Optimized MongoDB and Redis configurations"
echo -e "3. Applied Istio traffic management optimizations"
echo -e "4. Increased connection limits and timeouts in service-config"
echo -e "5. Restarted all deployments to apply changes"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Run your benchmarks again to see if performance has improved"
echo -e "2. Check for any remaining bottlenecks using: kubectl top pods -n $NAMESPACE"
echo -e "3. Monitor with Jaeger for any service with excessive latency"

echo -e "\n${GREEN}Note: These optimizations increase resource usage. Make sure your cluster has enough capacity.${NC}"