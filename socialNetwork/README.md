# Social Network Application Deployment and Benchmarking

## Overview

This document describes how to deploy the Social Network application, a microservices-based application, using the provided Helm chart and the `deploy-social-network.sh` deployment script. It also provides guidance on how to benchmark its end-to-end performance, especially when integrated with Istio service mesh.

The `deploy-social-network.sh` script automates the deployment process, including optional Istio integration (installation and configuration) and mTLS setup.

## Prerequisites

Before you begin, ensure you have the following tools installed and configured:

*   **kubectl:** The Kubernetes command-line tool. Used to interact with your Kubernetes cluster.
    *   Installation: [Install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
*   **Helm:** The package manager for Kubernetes. Used to deploy the application via its Helm chart.
    *   Installation: [Installing Helm](https://helm.sh/docs/intro/install/)
*   **Istio CLI (istioctl):** Required if you plan to enable Istio integration. Used to install and manage Istio.
    *   Installation: [Install Istio](https://istio.io/latest/docs/setup/getting-started/#download)
*   **wrk2:** A modern HTTP benchmarking tool. Used for generating load and measuring latency.
    *   Installation: Usually involves compiling from source. Visit [wrk2 GitHub repository](https://github.com/giltene/wrk2).
    *   Example (Ubuntu):
        ```bash
        sudo apt-get update
        sudo apt-get install -y libssl-dev libz-dev lua5.1 liblua5.1-0-dev build-essential git
        git clone https://github.com/giltene/wrk2.git
        cd wrk2
        make
        # Optional: sudo cp wrk /usr/local/bin/
        ```
*   **A running Kubernetes cluster:** Ensure your `kubectl` is configured to point to your cluster.

## Deployment

The `deploy-social-network.sh` script simplifies the deployment of the Social Network application. It is located in the `socialNetwork` directory.

### Script Options

The script accepts the following command-line options:

*   `--istio-enabled <true|false>`: Enable or disable Istio integration. (Default: `false`)
*   `--istio-namespace <namespace>`: Namespace where the Istio control plane is installed or will be installed. (Default: `istio-system`)
*   `--gateway-namespace <namespace>`: Namespace for the Istio Gateway resource. (Default: value of `--istio-namespace`, then `istio-system`)
*   `--mtls-enabled <true|false>`: Enable or disable Istio mTLS for the application namespace. (Default: `true` if Istio is enabled, otherwise `false`)
*   `--app-namespace <namespace>`: Kubernetes namespace to deploy the application into. The script will create this namespace if it doesn't exist. (Default: `default`)
*   `-h, --help`: Display the help message.

### Deployment Examples

Navigate to the `socialNetwork` directory before running the script.

1.  **Deploy the application without Istio into the `social-app` namespace:**
    ```bash
    ./deploy-social-network.sh --app-namespace social-app
    ```

2.  **Deploy the application with Istio enabled into the `social-app` namespace:**
    This will attempt to install Istio (using demo profile) in the `istio-system` namespace if not already present, label the `social-app` namespace for sidecar injection, and enable mTLS by default for the `social-app` namespace.
    ```bash
    ./deploy-social-network.sh --istio-enabled true --app-namespace social-app
    ```

3.  **Deploy with Istio enabled, but mTLS disabled for the `social-app` namespace:**
    ```bash
    ./deploy-social-network.sh --istio-enabled true --mtls-enabled false --app-namespace social-app
    ```

4.  **Deploy with Istio enabled, using a custom Istio control plane namespace and a separate gateway namespace:**
    ```bash
    ./deploy-social-network.sh \
      --istio-enabled true \
      --istio-namespace my-istio-control-plane \
      --gateway-namespace my-istio-gateways \
      --app-namespace social-app
    ```

After deployment, the script will output information on how to access the application. If Istio is enabled, this usually involves port-forwarding the Istio ingress gateway service.

## Benchmarking

Benchmarking helps understand the performance characteristics of the application under load, with or without Istio.

### Accessing the Application

*   **Without Istio:** You'll typically need to set up port-forwarding to the `nginx-thrift` service, which is the main entry point of the application. The Helm release name and application namespace affect the service name. If deployed with release name `socialnetwork` in namespace `social-app`:
    ```bash
    kubectl port-forward svc/socialnetwork-nginx-thrift -n social-app 8080:8080
    ```
    The application should then be accessible at `http://localhost:8080/`.

*   **With Istio:** The application is exposed through an Istio Ingress Gateway. The `deploy-social-network.sh` script provides instructions on port-forwarding the gateway. The service is typically `istio-ingressgateway` in the gateway namespace (e.g., `istio-system` or the one specified by `--gateway-namespace`).
    ```bash
    # Replace $GATEWAY_NAMESPACE with the actual namespace of your Istio ingress gateway
    kubectl port-forward -n $GATEWAY_NAMESPACE svc/istio-ingressgateway 8080:80
    ```
    The application should then be accessible at `http://localhost:8080/`.

### Load Generation with `wrk2`

`wrk2` is used to generate HTTP load and measure latency distribution. The specific API paths for benchmarking (e.g., `/wrk2-api/home-timeline/read`, `/wrk2-api/post/compose`) depend on the application's API endpoints exposed via `nginx-thrift`. You may need to consult the application's source code or `nginx.conf` for available endpoints.

**Example `wrk2` command:**

```bash
# General syntax: wrk2 -t<threads> -c<connections> -d<duration> -R<rate> [options] <url>
# -t: number of threads to use
# -c: total number of HTTP connections to keep open
# -d: duration of the test (e.g., 30s, 2m, 1h)
# -R: target request rate (requests per second)

# Example: Test home timeline read API for 60 seconds with 100 requests/sec, using 4 threads and 50 connections
# Ensure you have port-forwarded the correct service to localhost:8080 first.
wrk2 -t4 -c50 -d60s -R100 http://localhost:8080/wrk2-api/home-timeline/read
```

**Benchmarking Scenarios:**

*   **Baseline (No Istio):** Deploy the application without Istio and run `wrk2` tests against key endpoints to establish baseline performance.
*   **Istio Enabled (No mTLS):** Deploy with Istio (`--istio-enabled true`), but explicitly disable mTLS (`--mtls-enabled false`). Run the same `wrk2` tests.
*   **Istio Enabled (mTLS STRICT):** Deploy with Istio and mTLS in STRICT mode (default when Istio is enabled). Run `wrk2` tests.
*   **Varying Load:** For each configuration, test with different request rates (`-R`) and connection counts (`-c`) to understand how latency (especially tail latencies like p99, p99.9) changes and to identify potential saturation points.
*   **Different API Endpoints:** Benchmark various critical API endpoints (e.g., compose post, read user timeline, social graph operations) as they may have different performance characteristics.

### Monitoring with Istio Metrics

If Istio is enabled, you can leverage its rich observability features:

*   **Prometheus & Grafana:** If your Istio installation includes Prometheus and Grafana (common with the demo profile installed by the script), you can access pre-configured dashboards.
    *   Access Grafana: `istioctl dashboard grafana`
    *   Look for dashboards like "Istio Service Dashboard", "Istio Workload Dashboard", and "Istio Performance Dashboard" to see metrics like request rate, latency (P50, P90, P99), error rates, and resource consumption for each service.

*   **Kiali:** Kiali provides a visual representation of your service mesh, traffic flow, and health, which can be helpful in understanding service interactions.
    *   Access Kiali: `istioctl dashboard kiali`

*   **`istioctl` commands:**
    *   `istioctl proxy-status`: Check the status and configuration of Envoy proxies.
    *   `istioctl analyze -n <app-namespace>`: Analyze Istio configurations within your application namespace for potential issues.
    *   For more granular metrics directly from Envoy (useful for debugging):
        ```bash
        # Get stats from an istio-proxy container in your application pod
        kubectl exec -n <app-namespace> <your-app-pod-name> -c istio-proxy -- pilot-agent request GET stats
        # For Prometheus-formatted metrics directly from the proxy
        kubectl exec -n <app-namespace> <your-app-pod-name> -c istio-proxy -- curl localhost:15090/stats/prometheus
        ```

## Cleanup

To uninstall the application and clean up resources:

1.  **Uninstall the Helm Release:**
    Use the application namespace specified during deployment (`--app-namespace`) and the Helm release name (default: `socialnetwork`).
    ```bash
    # Replace $APP_NAMESPACE with the namespace used for deployment (e.g., social-app)
    helm uninstall socialnetwork -n $APP_NAMESPACE
    
    # Optionally, delete the application namespace if it's no longer needed and you are sure it contains no other resources
    # kubectl delete namespace $APP_NAMESPACE
    ```

2.  **Uninstall Istio (if installed by the script or needs removal):**
    Use the Istio control plane namespace specified during deployment or your Istio installation (default: `istio-system`).
    ```bash
    # Replace $ISTIO_NAMESPACE with the Istio control plane namespace
    istioctl uninstall -y --revision default # Use the correct revision if not default
    # If you installed a specific profile (like demo), sometimes it's better to use that for uninstall too, though often not required.
    # istioctl manifest generate --set profile=demo | kubectl delete -f -

    # Remove Istio namespace labels from application namespaces (if not already done by disabling Istio via script)
    # kubectl label namespace $APP_NAMESPACE istio-injection- --overwrite=true

    # Optionally, delete the Istio control plane namespace if it's no longer needed and was created solely for this
    # kubectl delete namespace $ISTIO_NAMESPACE
    ```
    **Note:** Uninstalling Istio will affect all applications in the cluster that rely on it. Be cautious if Istio is shared. Always refer to the official Istio documentation for the recommended cleanup procedures for your specific version and installation method.

3.  **Delete Istio CRDs (Use with Extreme Caution):**
    Istio installs Custom Resource Definitions (CRDs). If you want to completely remove all traces of Istio from your cluster, you might need to delete these. **This is a highly destructive operation and will affect all Istio installations and Istio-dependent applications on the cluster.**
    ```bash
    # Example command to list Istio CRDs
    # kubectl get crds | grep 'istio.io'
    # Example command to delete them (USE WITH CAUTION - VERIFY EACH CRD)
    # kubectl get crds | grep 'istio.io' | awk '{print $1}' | xargs -n 1 kubectl delete crd
    ```
    Always consult the official Istio documentation for the recommended CRD removal process. It's often safer to leave CRDs unless you are decommissioning Istio entirely from the cluster.

This README provides a guide to deploying, benchmarking, and managing the Social Network application with optional Istio integration using the `deploy-social-network.sh` script.Okay, I've overwritten the `socialNetwork/README.md` file with the comprehensive documentation.

The README now includes:
-   An **Overview** of the application and deployment script.
-   **Prerequisites** with installation links/instructions for `kubectl`, `helm`, `istioctl`, and `wrk2`.
-   **Deployment** instructions detailing `deploy-social-network.sh` script options and usage examples for various scenarios.
-   **Benchmarking** guidance, including how to access the application (with/without Istio), example `wrk2` commands, suggested benchmarking scenarios, and how to leverage Istio metrics (Prometheus, Grafana, Kiali, `istioctl`).
-   **Cleanup** steps for uninstalling the Helm release and Istio, with necessary precautions.

I believe this fulfills all the requirements for the README.md file.
