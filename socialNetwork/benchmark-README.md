# Benchmarking DeathStarBench Social Network on Kubernetes with Istio

This guide outlines how to benchmark the DeathStarBench social network application running on Kubernetes with Istio. It covers setting up the environment, running benchmark tests, and analyzing the results.

## Prerequisites

- Kubernetes cluster with Istio installed
- The social network application deployed using the `k8s-istio-deploy.sh` script
- [`wrk2`](https://github.com/giltene/wrk2) installed on your local machine or a separate load testing instance
- Python 3.5+ with required packages for the social graph initialization

## Setup Environment

Before running benchmarks, ensure the following steps are completed:

1. Deploy the social network application:

```bash
# Deploy with default settings
./k8s-istio-deploy.sh

# Or deploy with custom configuration
./k8s-istio-deploy.sh --replicas 3 --enable-hpa --cpu-limit 1000m --memory-limit 1Gi
```

2. Get the Istio ingress gateway address:

```bash
GATEWAY_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# If using a hostname instead of IP:
# GATEWAY_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Social network accessible at: http://$GATEWAY_IP"
```

3. Initialize the social graph:

```bash
# For a small social graph (Reed98 Facebook Networks)
python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=$GATEWAY_IP --port=80

# For a medium social graph (Ego Twitter)
python3 scripts/init_social_graph.py --graph=ego-twitter --ip=$GATEWAY_IP --port=80

# For a large social graph (Twitter-follows-mun)
python3 scripts/init_social_graph.py --graph=soc-twitter-follows-mun --ip=$GATEWAY_IP --port=80
```

## Benchmark Tests

The following benchmark tests can be used to evaluate the performance of the social network application:

### 1. Compose Post Test

This test measures the performance of the compose post functionality:

```bash
../wrk2/wrk -D exp -t <num-threads> -c <num-conns> -d <duration> -L -s ./wrk2/scripts/social-network/compose-post.lua http://$GATEWAY_IP/wrk2-api/post/compose -R <reqs-per-sec>
```

Example with parameters:
```bash
../wrk2/wrk -D exp -t 12 -c 400 -d 30s -L -s ./wrk2/scripts/social-network/compose-post.lua http://$GATEWAY_IP/wrk2-api/post/compose -R 100
```

### 2. Read Home Timeline Test

This test measures the performance of reading a user's home timeline:

```bash
../wrk2/wrk -D exp -t <num-threads> -c <num-conns> -d <duration> -L -s ./wrk2/scripts/social-network/read-home-timeline.lua http://$GATEWAY_IP/wrk2-api/home-timeline/read -R <reqs-per-sec>
```

Example with parameters:
```bash
../wrk2/wrk -D exp -t 12 -c 400 -d 30s -L -s ./wrk2/scripts/social-network/read-home-timeline.lua http://$GATEWAY_IP/wrk2-api/home-timeline/read -R 200
```

### 3. Read User Timeline Test

This test measures the performance of reading a user's personal timeline:

```bash
../wrk2/wrk -D exp -t <num-threads> -c <num-conns> -d <duration> -L -s ./wrk2/scripts/social-network/read-user-timeline.lua http://$GATEWAY_IP/wrk2-api/user-timeline/read -R <reqs-per-sec>
```

Example with parameters:
```bash
../wrk2/wrk -D exp -t 12 -c 400 -d 30s -L -s ./wrk2/scripts/social-network/read-user-timeline.lua http://$GATEWAY_IP/wrk2-api/user-timeline/read -R 200
```

### 4. Mixed Workload Test

For a more realistic workload, run multiple benchmark tests concurrently with a distribution that matches your expected usage pattern. Here's a script to run a mixed workload:

```bash
#!/bin/bash

GATEWAY_IP=$1
DURATION=$2  # Duration in seconds

# Run compose post test (10% of workload)
../wrk2/wrk -D exp -t 4 -c 100 -d ${DURATION}s -L -s ./wrk2/scripts/social-network/compose-post.lua http://$GATEWAY_IP/wrk2-api/post/compose -R 50 &

# Run read home timeline test (45% of workload)
../wrk2/wrk -D exp -t 8 -c 200 -d ${DURATION}s -L -s ./wrk2/scripts/social-network/read-home-timeline.lua http://$GATEWAY_IP/wrk2-api/home-timeline/read -R 225 &

# Run read user timeline test (45% of workload)
../wrk2/wrk -D exp -t 8 -c 200 -d ${DURATION}s -L -s ./wrk2/scripts/social-network/read-user-timeline.lua http://$GATEWAY_IP/wrk2-api/user-timeline/read -R 225 &

# Wait for all tests to complete
wait

echo "Mixed workload test completed"
```

Save this script as `run-mixed-workload.sh` and run it:
```bash
chmod +x run-mixed-workload.sh
./run-mixed-workload.sh $GATEWAY_IP 60
```

## Performance Metrics Collection

To collect comprehensive performance metrics, use the following tools:

### 1. Istio Service Metrics

Access Istio's built-in Kiali dashboard to visualize service metrics:

```bash
istioctl dashboard kiali
```

### 2. Prometheus Metrics

Access Prometheus dashboard to view detailed metrics:

```bash
istioctl dashboard prometheus
```

Useful Prometheus queries:
- Request rate: `sum(rate(istio_requests_total{destination_service=~".*social-network.*"}[1m])) by (destination_service)`
- Error rate: `sum(rate(istio_requests_total{destination_service=~".*social-network.*", response_code=~"5.*|4.*"}[1m])) by (destination_service)`
- Latency: `histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{destination_service=~".*social-network.*"}[1m])) by (destination_service, le))`

### 3. Jaeger Distributed Tracing

Access Jaeger to view distributed traces:

```bash
istioctl dashboard jaeger
```

### 4. Resource Utilization

Monitor resource utilization with:

```bash
kubectl top pods -n social-network
kubectl top nodes
```

## Benchmark Scenarios

Here are recommended benchmark scenarios to evaluate the social network application:

### Scenario 1: Baseline Performance

Run benchmarks with the default deployment (single replica per service) to establish a performance baseline:

```bash
# Deploy with default settings
./k8s-istio-deploy.sh

# Run benchmarks with gradually increasing load
for RATE in 50 100 200 400 800; do
  echo "Testing at $RATE requests per second"
  ../wrk2/wrk -D exp -t 12 -c 400 -d 30s -L -s ./wrk2/scripts/social-network/compose-post.lua http://$GATEWAY_IP/wrk2-api/post/compose -R $RATE
  sleep 30
done
```

### Scenario 2: Scalability Testing

Test how the application scales with increased replica count:

```bash
# Deploy with 3 replicas per service
./k8s-istio-deploy.sh --replicas 3

# Run the same benchmark tests as in Scenario 1
```

### Scenario 3: Resilience Testing

Test application resilience by introducing failures:

```bash
# Identify a critical service
kubectl get pods -n social-network

# Delete a pod to simulate failure
kubectl delete pod <pod-name> -n social-network

# Run benchmarks during pod recreation
../wrk2/wrk -D exp -t 12 -c 400 -d 60s -L -s ./wrk2/scripts/social-network/compose-post.lua http://$GATEWAY_IP/wrk2-api/post/compose -R 100
```

### Scenario 4: HPA Testing

Test the Horizontal Pod Autoscaler's effectiveness:

```bash
# Deploy with HPA enabled
./k8s-istio-deploy.sh --enable-hpa --cpu-limit 500m --cpu-request 200m

# Run benchmarks with sustained high load
../wrk2/wrk -D exp -t 12 -c 400 -d 300s -L -s ./wrk2/scripts/social-network/compose-post.lua http://$GATEWAY_IP/wrk2-api/post/compose -R 800

# Monitor HPA in action
kubectl get hpa -n social-network -w
```

## Analyzing Results

After running the benchmark tests, analyze the results to understand the performance characteristics:

1. **Throughput**: Maximum sustained requests per second without errors
2. **Latency**: Response time distribution (50th, 95th, 99th percentiles)
3. **Error Rate**: Percentage of failed requests
4. **Resource Utilization**: CPU, memory, and network usage
5. **Scaling Behavior**: How performance changes with increased replicas
6. **Service Dependencies**: Identify bottlenecks in the service chain

Use the following template to record your results:

```
Benchmark: [Test Name]
Configuration:
- Replicas: [Number]
- HPA Enabled: [Yes/No]
- Resource Limits: CPU [Value], Memory [Value]

Results:
- Max Throughput: [Value] req/s
- Latency (95th percentile): [Value] ms
- Error Rate: [Value] %
- Resource Utilization: CPU [Value] %, Memory [Value] %

Observations:
- [Key observations about performance]
- [Identified bottlenecks]
- [Recommendations for improvement]
```

## Optimizing Performance

Based on benchmark results, consider the following optimizations:

1. **Resource Allocation**: Adjust CPU and memory limits/requests
2. **Replica Count**: Increase replicas for bottleneck services
3. **Database Tuning**: Optimize MongoDB and Redis configuration
4. **Network Policies**: Configure Istio traffic policies
5. **Caching Strategy**: Adjust cache TTLs and sizes
6. **Circuit Breaking**: Add circuit breakers to prevent cascading failures
7. **Connection Pooling**: Optimize connection pools for databases and services

## Conclusion

Benchmarking the DeathStarBench social network on Kubernetes with Istio provides valuable insights into microservice architecture performance. Use the results to make data-driven decisions about scaling, resource allocation, and architectural improvements.

Remember that performance characteristics in a production environment may differ from benchmark results due to factors like network latency, user behavior, and external dependencies.