#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Test specific variables
TEST_NAME="DeployNoIstio"
LOG_DIR="logs"
MOCK_LOG_FILE="$LOG_DIR/${TEST_NAME}_mock_command_log.txt"
SCRIPT_OUTPUT_LOG="$LOG_DIR/${TEST_NAME}_script_output.log"
TEST_APP_NAMESPACE="no-istio-app"

# Setup:
# - Ensure logs directory exists
# - Clean up mock command log file for this test
# - Add mock commands directory to PATH
# - Set up mock conditions (e.g., helm release does not exist)
setup() {
  echo "--- Setting up for $TEST_NAME ---"
  mkdir -p "$LOG_DIR"
  rm -f "$MOCK_LOG_FILE"
  touch "$MOCK_LOG_FILE" # Ensure it exists for the mock script
  
  # Add current directory (socialNetwork/tests) to PATH to use mock commands
  export PATH="$(pwd):$PATH"
  
  # Mock conditions for this test:
  # - App namespace does not exist initially
  rm -f .mock_app_namespace_exists 
  # - Helm release does not exist in the app namespace
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"

  echo "Setup complete."
}

# Teardown:
# - Clean up mock condition files
teardown() {
  echo "--- Tearing down for $TEST_NAME ---"
  rm -f .mock_app_namespace_exists 
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"
  echo "Teardown complete."
}

# Run the deployment script
echo "--- Running $TEST_NAME ---"
setup

# Execute the deployment script from the parent directory (socialNetwork)
# Log stdout and stderr of the script
../deploy-social-network.sh \
  --istio-enabled false \
  --app-namespace "$TEST_APP_NAMESPACE" > "$SCRIPT_OUTPUT_LOG" 2>&1

# Check script exit code
if [ $? -ne 0 ]; then
  echo "ERROR: deploy-social-network.sh failed for $TEST_NAME."
  cat "$SCRIPT_OUTPUT_LOG"
  teardown
  exit 1
fi
echo "deploy-social-network.sh executed successfully."

# --- Verification ---
echo "--- Verifying $TEST_NAME ---"

# 1. Verify namespace creation (if it didn't exist)
grep -q "kubectl create namespace $TEST_APP_NAMESPACE" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: kubectl create namespace $TEST_APP_NAMESPACE" \
  || { echo "FAILED: Did not find kubectl create namespace $TEST_APP_NAMESPACE"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 2. Verify Helm install command
# Expected: helm install socialnetwork ./helm-chart/socialnetwork --namespace no-istio-app --create-namespace --set global.istio.enabled=false --set global.istio.namespace=istio-system --wait --timeout 10m0s
grep "helm install socialnetwork ../helm-chart/socialnetwork --namespace $TEST_APP_NAMESPACE --create-namespace --set global.istio.enabled=false --set global.istio.namespace=istio-system --wait --timeout 10m0s" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: Correct Helm install command found" \
  || { echo "FAILED: Correct Helm install command not found"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }

# 3. Verify no istioctl commands were called
if grep -q "istioctl" "$MOCK_LOG_FILE"; then
  echo "FAILED: istioctl commands were called in no-Istio deployment"
  cat "$MOCK_LOG_FILE"
  teardown
  exit 1
else
  echo "VERIFIED: No istioctl commands were called"
fi

# 4. Verify no PeerAuthentication was applied
if grep -q "kubectl apply.*PeerAuthentication" "$MOCK_LOG_FILE"; then
  echo "FAILED: PeerAuthentication was applied in no-Istio deployment"
  cat "$MOCK_LOG_FILE"
  teardown
  exit 1
else
  echo "VERIFIED: No PeerAuthentication was applied"
fi

# 5. Verify istio-injection label is removed/not set
grep -q "kubectl label namespace $TEST_APP_NAMESPACE istio-injection- --overwrite=true" "$MOCK_LOG_FILE" \
  && echo "VERIFIED: kubectl label namespace $TEST_APP_NAMESPACE istio-injection- --overwrite=true" \
  || { echo "FAILED: Did not find kubectl label namespace $TEST_APP_NAMESPACE istio-injection- --overwrite=true"; cat "$MOCK_LOG_FILE"; teardown; exit 1; }


echo "--- $TEST_NAME Verification Successful ---"
teardown
exit 0
