#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Test specific variables
TEST_NAME="DeployWithIstioNewInstall"
LOG_DIR="logs"
MOCK_LOG_FILE="$LOG_DIR/${TEST_NAME}_mock_command_log.txt"
SCRIPT_OUTPUT_LOG="$LOG_DIR/${TEST_NAME}_script_output.log"
TEST_APP_NAMESPACE="istio-app-new"
TEST_ISTIO_NAMESPACE="istio-system" # Default, but explicit for clarity

# Setup:
setup() {
  echo "--- Setting up for $TEST_NAME ---"
  mkdir -p "$LOG_DIR"
  rm -f "$MOCK_LOG_FILE"
  touch "$MOCK_LOG_FILE"
  
  export PATH="$(pwd):$PATH"
  
  # Mock conditions:
  # - App namespace does not exist initially
  rm -f .mock_app_namespace_exists
  # - Istio namespace does not exist initially (so istioctl install is triggered)
  rm -f .mock_istio_namespace_exists
  # - istiod deployment does not exist initially
  rm -f .mock_istiod_exists
  # - Helm release does not exist in the app namespace
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"

  echo "Setup complete."
}

# Teardown:
teardown() {
  echo "--- Tearing down for $TEST_NAME ---"
  rm -f .mock_app_namespace_exists
  rm -f .mock_istio_namespace_exists
  rm -f .mock_istiod_exists # istioctl install mock creates this
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"
  echo "Teardown complete."
}

# Run the deployment script
echo "--- Running $TEST_NAME ---"
setup

../deploy-social-network.sh \
  --istio-enabled true \
  --app-namespace "$TEST_APP_NAMESPACE" \
  --istio-namespace "$TEST_ISTIO_NAMESPACE" > "$SCRIPT_OUTPUT_LOG" 2>&1

if [ $? -ne 0 ]; then
  echo "ERROR: deploy-social-network.sh failed for $TEST_NAME."
  cat "$SCRIPT_OUTPUT_LOG"
  teardown
  exit 1
fi
echo "deploy-social-network.sh executed successfully."

# --- Verification ---
echo "--- Verifying $TEST_NAME ---"

# 1. Verify app namespace creation
grep -q "kubectl create namespace $TEST_APP_NAMESPACE" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: kubectl create namespace $TEST_APP_NAMESPACE" \
  || { echo "FAILED: Did not find kubectl create namespace $TEST_APP_NAMESPACE"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 2. Verify istioctl install was called
grep -q "istioctl install --set profile=demo -y --set values.global.istioNamespace=$TEST_ISTIO_NAMESPACE" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: istioctl install command found" \
  || { echo "FAILED: istioctl install command not found"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 3. Verify app namespace labeling for Istio injection
grep -q "kubectl label namespace $TEST_APP_NAMESPACE istio-injection=enabled --overwrite=true" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: kubectl label namespace $TEST_APP_NAMESPACE for Istio injection" \
  || { echo "FAILED: Did not find kubectl label for Istio injection"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 4. Verify mTLS PeerAuthentication was applied (default is STRICT for the app namespace)
grep "kubectl apply -n $TEST_APP_NAMESPACE -f -" "$MOCK_LOG_FILE" | grep -q "kind: PeerAuthentication" \
  && grep "kubectl apply -n $TEST_APP_NAMESPACE -f -" "$MOCK_LOG_FILE" | grep -q "mode: STRICT" \
  && echo "VERIFIED: mTLS PeerAuthentication STRICT applied to $TEST_APP_NAMESPACE" \
  || { echo "FAILED: mTLS PeerAuthentication not correctly applied"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 5. Verify Helm install command
# Expected: helm install socialnetwork ./helm-chart/socialnetwork --namespace istio-app-new --create-namespace --set global.istio.enabled=true --set global.istio.namespace=istio-system --wait --timeout 10m0s
grep "helm install socialnetwork ../helm-chart/socialnetwork --namespace $TEST_APP_NAMESPACE --create-namespace --set global.istio.enabled=true --set global.istio.namespace=$TEST_ISTIO_NAMESPACE --wait --timeout 10m0s" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: Correct Helm install command found for Istio deployment" \
  || { echo "FAILED: Correct Helm install command for Istio deployment not found"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

echo "--- $TEST_NAME Verification Successful ---"
teardown
exit 0
