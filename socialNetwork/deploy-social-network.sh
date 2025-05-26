#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
APP_NAMESPACE="default" # Namespace where the social network application will be deployed
HELM_RELEASE_NAME="socialnetwork"
HELM_CHART_PATH="./helm-chart/socialnetwork" # Relative to the script's location

# --- Helper Functions ---
info() {
  echo "[INFO] $1"
}

error() {
  echo "[ERROR] $1" >&2
  exit 1
}

# Function to display usage information
usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Deploys the Social Network application using Helm and optionally integrates with Istio."
  echo ""
  echo "Options:"
  echo "  --istio-enabled <true|false>    Enable or disable Istio integration (default: false)."
  echo "  --istio-namespace <namespace>     Namespace where Istio control plane is installed or will be installed (default: istio-system)."
  echo "  --gateway-namespace <namespace>   Namespace for the Istio Gateway resource (default: value of --istio-namespace, then istio-system)."
  echo "  --mtls-enabled <true|false>     Enable or disable Istio mTLS for the application namespace (default: true if Istio is enabled)."
  echo "  --app-namespace <namespace>       Kubernetes namespace to deploy the application into (default: default)."
  echo "  -h, --help                        Display this help message."
  exit 1
}

# --- Default values ---
DEFAULT_ISTIO_ENABLED=false
DEFAULT_ISTIO_NAMESPACE="istio-system"
DEFAULT_GATEWAY_NAMESPACE="" # Will be derived
DEFAULT_MTLS_ENABLED=""    # Will be set based on ISTIO_ENABLED later
DEFAULT_APP_NAMESPACE="default"

# --- Initialize variables with defaults ---
ISTIO_ENABLED=$DEFAULT_ISTIO_ENABLED
ISTIO_NAMESPACE=$DEFAULT_ISTIO_NAMESPACE
GATEWAY_NAMESPACE=$DEFAULT_GATEWAY_NAMESPACE
MTLS_ENABLED=$DEFAULT_MTLS_ENABLED
APP_NAMESPACE=$DEFAULT_APP_NAMESPACE

# --- Parse command-line arguments ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --istio-enabled) ISTIO_ENABLED="$2"; shift ;;
    --istio-namespace) ISTIO_NAMESPACE="$2"; shift ;;
    --gateway-namespace) GATEWAY_NAMESPACE="$2"; shift ;;
    --mtls-enabled) MTLS_ENABLED="$2"; shift ;;
    --app-namespace) APP_NAMESPACE="$2"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown parameter passed: $1"; usage ;;
  esac
  shift
done

# --- Validate and finalize configuration ---
if [ -z "$GATEWAY_NAMESPACE" ]; then
  GATEWAY_NAMESPACE="$ISTIO_NAMESPACE"
fi

if [ -z "$MTLS_ENABLED" ]; then
  if [ "$ISTIO_ENABLED" == "true" ]; then
    MTLS_ENABLED="true"
  else
    MTLS_ENABLED="false"
  fi
fi

if [[ "$ISTIO_ENABLED" != "true" && "$ISTIO_ENABLED" != "false" ]]; then
  error "Invalid value for --istio-enabled. Must be 'true' or 'false'."
fi
if [[ "$MTLS_ENABLED" != "true" && "$MTLS_ENABLED" != "false" ]]; then
  error "Invalid value for --mtls-enabled. Must be 'true' or 'false'."
fi

# --- Main script execution ---

info "Starting Social Network deployment..."
info "Configuration:"
info "  Application Namespace: $APP_NAMESPACE"
info "  Istio Enabled: $ISTIO_ENABLED"
if [ "$ISTIO_ENABLED" == "true" ]; then
  info "  Istio Control Plane Namespace: $ISTIO_NAMESPACE"
  info "  Istio Gateway Namespace: $GATEWAY_NAMESPACE"
  info "  mTLS Enabled (for $APP_NAMESPACE namespace): $MTLS_ENABLED"
fi

# Create application namespace if it doesn't exist
if ! kubectl get namespace "$APP_NAMESPACE" &> /dev/null; then
  info "Application namespace '$APP_NAMESPACE' not found. Creating..."
  kubectl create namespace "$APP_NAMESPACE"
  info "Namespace '$APP_NAMESPACE' created."
else
  info "Application namespace '$APP_NAMESPACE' already exists."
fi


# Check and install Istio if enabled
if [ "$ISTIO_ENABLED" == "true" ]; then
  info "Istio integration is enabled."
  if ! command -v istioctl &> /dev/null; then
    error "istioctl not found. Please install Istio CLI first. Refer to Istio documentation: https://istio.io/latest/docs/setup/getting-started/"
  fi

  # Check if Istio control plane (istiod) is running in the target namespace
  # Using kubectl to check for istiod deployment as a more reliable check
  if ! kubectl get deployment istiod -n "$ISTIO_NAMESPACE" &> /dev/null; then
    info "Istio control plane (istiod) not found in namespace '$ISTIO_NAMESPACE'. Installing Istio..."
    # The demo profile includes an ingress gateway.
    # We ensure the istio-ingressgateway is in the $GATEWAY_NAMESPACE by setting values.gateways.istio-ingressgateway.namespace
    # However, `istioctl install` primarily uses `values.global.istioNamespace` for its own components if not specified otherwise.
    # For simplicity and common use cases, installing into ISTIO_NAMESPACE and assuming gateway is also there or managed by istioctl's profile.
    # The helm chart's istio.gatewayName and istio.namespace (.Values.istio.namespace which maps to global.istio.namespace)
    # should align with where the gateway is deployed.
    istioctl install --set profile=demo -y --set values.global.istioNamespace="$ISTIO_NAMESPACE"
    # Verify installation
    if ! kubectl get deployment istiod -n "$ISTIO_NAMESPACE" &> /dev/null; then
        error "Istio installation failed. istiod deployment not found in '$ISTIO_NAMESPACE'."
    fi
    info "Istio installation completed in namespace '$ISTIO_NAMESPACE'."

    info "Labeling namespace '$APP_NAMESPACE' for Istio sidecar injection..."
    kubectl label namespace "$APP_NAMESPACE" istio-injection=enabled --overwrite=true
  else
    info "Istio control plane (istiod) found in namespace '$ISTIO_NAMESPACE'. Assuming Istio is already installed and configured."
    info "Ensure namespace '$APP_NAMESPACE' is labeled for Istio sidecar injection if not done already (e.g., kubectl label namespace $APP_NAMESPACE istio-injection=enabled --overwrite=true)"
  fi

  # Apply mTLS configuration (PeerAuthentication) for the application namespace
  if [ "$MTLS_ENABLED" == "true" ]; then
    info "Enabling mTLS for the '$APP_NAMESPACE' namespace..."
    # Create PeerAuthentication resource for the application namespace
    kubectl apply -n "$APP_NAMESPACE" -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default # Name 'default' is conventional for namespace-wide policy
  namespace: ${APP_NAMESPACE}
spec:
  mtls:
    mode: STRICT
EOF
    info "mTLS enabled for the '$APP_NAMESPACE' namespace."
  else
    info "mTLS is disabled for '$APP_NAMESPACE' namespace."
    kubectl delete peerauthentication default -n "$APP_NAMESPACE" --ignore-not-found=true
    info "PeerAuthentication 'default' in namespace '$APP_NAMESPACE' deleted (if it existed)."
  fi
else
  info "Istio integration is disabled."
  info "If Istio was previously used, ensure manual cleanup of any Istio resources (Gateway, VirtualService, DestinationRule, PeerAuthentication) and namespace labels if necessary."
  info "The Helm chart will not deploy Istio-specific resources if global.istio.enabled=false."
  kubectl label namespace "$APP_NAMESPACE" istio-injection- --overwrite=true > /dev/null 2>&1 || true # Attempt to remove label
fi

# Deploy Social Network using Helm
info "Deploying Social Network application to namespace '$APP_NAMESPACE'..."

# Construct Helm values based on script arguments
# The Helm chart uses .Values.global.istio.enabled and .Values.global.istio.namespace
# The Gateway template uses .Values.istio.namespace (which should be .Values.global.istio.namespace for consistency or chart needs update)
# For now, passing GATEWAY_NAMESPACE to global.istio.namespace as that's what values.yaml structure suggests for the gateway.
HELM_SET_VALUES=(
  "--set global.istio.enabled=$ISTIO_ENABLED"
  "--set global.istio.namespace=$GATEWAY_NAMESPACE" 
  # Add other necessary Helm values here if they need to be configured by this script
)

# Check if the Helm release already exists in the target namespace
if helm status "$HELM_RELEASE_NAME" -n "$APP_NAMESPACE" &> /dev/null; then
  info "Helm release '$HELM_RELEASE_NAME' already exists in namespace '$APP_NAMESPACE'. Upgrading..."
  helm upgrade "$HELM_RELEASE_NAME" "$HELM_CHART_PATH" \
    --namespace "$APP_NAMESPACE" \
    "${HELM_SET_VALUES[@]}" \
    --install \
    --wait \
    --timeout 10m0s
else
  info "Helm release '$HELM_RELEASE_NAME' not found in namespace '$APP_NAMESPACE'. Installing..."
  helm install "$HELM_RELEASE_NAME" "$HELM_CHART_PATH" \
    --namespace "$APP_NAMESPACE" \
    --create-namespace \
    "${HELM_SET_VALUES[@]}" \
    --wait \
    --timeout 10m0s
fi

if [ $? -eq 0 ]; then
  info "Social Network deployment to namespace '$APP_NAMESPACE' completed successfully."
else
  error "Social Network deployment to namespace '$APP_NAMESPACE' failed."
fi

# Additional deployment status checks or information
if [ "$ISTIO_ENABLED" == "true" ]; then
  GATEWAY_NAME_FROM_CHART=$(helm get values "$HELM_RELEASE_NAME" -n "$APP_NAMESPACE" -o jsonpath='{.global.istio.gatewayName}')
  if [ -z "$GATEWAY_NAME_FROM_CHART" ]; then
    GATEWAY_NAME_FROM_CHART="socialnetwork-gateway" # Default from chart's values.yaml
  fi
  info "Istio Gateway Name (from chart values): $GATEWAY_NAME_FROM_CHART"
  info "Istio Gateway Namespace (configured for chart): $GATEWAY_NAMESPACE"
  
  info "To access the application, ensure your Istio ingress gateway service in '$GATEWAY_NAMESPACE' is configured and accessible."
  info "Example command to port-forward the default Istio ingress gateway:"
  info "  kubectl port-forward -n $GATEWAY_NAMESPACE svc/istio-ingressgateway 8080:80"
  info "The VirtualService for the application is configured to use the gateway '$GATEWAY_NAME_FROM_CHART' in namespace '$GATEWAY_NAMESPACE'."
fi

exit 0
