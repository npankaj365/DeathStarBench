# DeathStarBench Social Network on Kubernetes with Istio

This guide explains how to deploy the DeathStarBench social network application on Kubernetes with Istio service mesh.

## Prerequisites

- Kubernetes cluster (v1.19+)
- Istio (v1.10+) installed locally
- kubectl configured to access your cluster
- Helm v3
- Python 3.5+ for initializing the social graph

## Quick Start

1. **Deploy the application:**

   ```bash
   # Deploy with default settings
   ./k8s-istio-deploy.sh
   
   # For custom configuration
   ./k8s-istio-deploy.sh --replicas 3 --enable-hpa --cpu-limit 1000m --memory-limit 1Gi
   
   # To see all available options
   ./k8s-istio-deploy.sh --help
   ```

2. **Get the application URL:**

   ```bash
   # Get the Istio ingress gateway address
   export GATEWAY_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   
   # If using a hostname instead of IP:
   # export GATEWAY_IP=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
   
   echo "Social Network accessible at: http://$GATEWAY_IP"
   echo "Media Frontend accessible at: http://$GATEWAY_IP/media"
   ```

3. **Initialize the social graph:**

   ```bash
   # Initialize with a small social graph
   python3 scripts/init_social_graph.py --graph=socfb-Reed98 --ip=$GATEWAY_IP --port=80
   ```

4. **Access the application:**

   Open your browser and visit:
   - Main frontend: http://$GATEWAY_IP
   - Media frontend: http://$GATEWAY_IP/media
   - Jaeger UI (if enabled): http://$GATEWAY_IP:16686

## Configuration Options

The deployment script supports the following configuration options:

- `--namespace NAME`: Kubernetes namespace to deploy to (default: social-network)
- `--istio-profile NAME`: Istio profile to use (default: default)
- `--replicas N`: Number of replicas for each service (default: 1)
- `--disable-metrics`: Disable Prometheus metrics collection
- `--enable-hpa`: Enable Horizontal Pod Autoscaling
- `--disable-jaeger`: Disable Jaeger tracing
- `--cpu-limit LIMIT`: CPU limit per container (default: 500m)
- `--memory-limit LIMIT`: Memory limit per container (default: 512Mi)
- `--cpu-request REQ`: CPU request per container (default: 100m)
- `--memory-request REQ`: Memory request per container (default: 128Mi)
- `--dry-run`: Print commands without executing them
- `--help`: Display help message

## Advanced Istio Configuration

For advanced Istio configurations, you can apply the included configuration file:

```bash
kubectl apply -f istio-config.yaml -n social-network
```

This configuration includes:
- Gateway setup
- Virtual services for frontend and media services
- Destination rules with circuit breaking
- Traffic management policies
- Retry policies and timeouts

## Monitoring and Observability

### Kiali Dashboard

```bash
istioctl dashboard kiali
```

### Jaeger for Distributed Tracing

```bash
istioctl dashboard jaeger
```

### Prometheus for Metrics

```bash
istioctl dashboard prometheus
```

### Grafana for Visualization

```bash
istioctl dashboard grafana
```

## Performance Benchmarking

For detailed instructions on how to benchmark the application, refer to the included benchmarking guide:

```bash
cat benchmark-README.md
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n social-network
```

### View Pod Logs

```bash
kubectl logs -n social-network <pod-name>
```

### Check Istio Proxy Status

```bash
istioctl proxy-status -n social-network
```

### Verify Istio Configuration

```bash
istioctl analyze -n social-network
```

## Cleanup

To remove the deployed application and resources:

```bash
# Remove application
helm uninstall social-network -n social-network

# Remove namespace
kubectl delete namespace social-network

# Remove Istio gateway and virtual services
kubectl delete -f istio-config.yaml -n social-network
```