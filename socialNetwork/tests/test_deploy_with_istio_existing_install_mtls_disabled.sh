#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Test specific variables
TEST_NAME="DeployWithIstioExistingInstallMtlsDisabled"
LOG_DIR="logs"
MOCK_LOG_FILE="$LOG_DIR/${TEST_NAME}_mock_command_log.txt"
SCRIPT_OUTPUT_LOG="$LOG_DIR/${TEST_NAME}_script_output.log"
TEST_APP_NAMESPACE="istio-app-existing"
TEST_ISTIO_NAMESPACE="istio-system"
TEST_GATEWAY_NAMESPACE="custom-gateway-ns" # Different from istio control plane ns

# Setup:
setup() {
  echo "--- Setting up for $TEST_NAME ---"
  mkdir -p "$LOG_DIR"
  rm -f "$MOCK_LOG_FILE"
  touch "$MOCK_LOG_FILE"
  
  export PATH="$(pwd):$PATH"
  
  # Mock conditions:
  # - App namespace exists
  touch .mock_app_namespace_exists
  # - Istio namespace exists
  touch .mock_istio_namespace_exists
  # - istiod deployment exists (Istio already installed)
  touch .mock_istiod_exists
  # - Helm release already exists (trigger helm upgrade)
  touch ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"

  echo "Setup complete."
}

# Teardown:
teardown() {
  echo "--- Tearing down for $TEST_NAME ---"
  rm -f .mock_app_namespace_exists
  rm -f .mock_istio_namespace_exists
  rm -f .mock_istiod_exists
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"
  echo "Teardown complete."
}

# Run the deployment script
echo "--- Running $TEST_NAME ---"
setup

../deploy-social-network.sh \
  --istio-enabled true \
  --mtls-enabled false \
  --app-namespace "$TEST_APP_NAMESPACE" \
  --istio-namespace "$TEST_ISTIO_NAMESPACE" \
  --gateway-namespace "$TEST_GATEWAY_NAMESPACE" > "$SCRIPT_OUTPUT_LOG" 2>&1

if [ $? -ne 0 ]; then
  echo "ERROR: deploy-social-network.sh failed for $TEST_NAME."
  cat "$SCRIPT_OUTPUT_LOG"
  teardown
  exit 1
fi
echo "deploy-social-network.sh executed successfully."

# --- Verification ---
echo "--- Verifying $TEST_NAME ---"

# 1. Verify app namespace is NOT created (because .mock_app_namespace_exists was touched)
if grep -q "kubectl create namespace $TEST_APP_NAMESPACE" "$MOCK_LOG_FILE"; then
  echo "FAILED: Attempted to create app namespace $TEST_APP_NAMESPACE when it should exist"; cat "$MOCK_LOG_FILE"; teardown; exit 1;
else
  echo "VERIFIED: Did not attempt to create existing app namespace $TEST_APP_NAMESPACE"
fi

# 2. Verify istioctl install was NOT called (because .mock_istiod_exists was touched)
if grep -q "istioctl install" "$MOCK_LOG_FILE"; then
  echo "FAILED: istioctl install command was called when Istio should be existing"; cat "$MOCK_LOG_FILE"; teardown; exit 1;
else
  echo "VERIFIED: istioctl install command was not called"
fi

# 3. Verify app namespace labeling for Istio injection (still happens to be sure)
grep -q "kubectl label namespace $TEST_APP_NAMESPACE istio-injection=enabled --overwrite=true" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: kubectl label namespace $TEST_APP_NAMESPACE for Istio injection" \
  || { echo "FAILED: Did not find kubectl label for Istio injection"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 4. Verify mTLS PeerAuthentication was DELETED for the app namespace (because --mtls-enabled false)
grep "kubectl delete peerauthentication default -n $TEST_APP_NAMESPACE --ignore-not-found=true" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: mTLS PeerAuthentication DELETED for $TEST_APP_NAMESPACE" \
  || { echo "FAILED: mTLS PeerAuthentication not deleted for $TEST_APP_NAMESPACE"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 5. Verify Helm upgrade command is used
# Expected: helm upgrade socialnetwork ./helm-chart/socialnetwork --namespace istio-app-existing --set global.istio.enabled=true --set global.istio.namespace=custom-gateway-ns --install --wait --timeout 10m0s
grep "helm upgrade socialnetwork ../helm-chart/socialnetwork --namespace $TEST_APP_NAMESPACE --set global.istio.enabled=true --set global.istio.namespace=$TEST_GATEWAY_NAMESPACE --install --wait --timeout 10m0s" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: Correct Helm upgrade command found" \
  || { echo "FAILED: Correct Helm upgrade command not found"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

echo "--- $TEST_NAME Verification Successful ---"
teardown
exit 0
