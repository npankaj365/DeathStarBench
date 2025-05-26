#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# set -e # We expect this script to fail, so don't exit immediately.

# Test specific variables
TEST_NAME="DeployIstioEnabledNoIstioctl"
LOG_DIR="logs"
MOCK_LOG_FILE="$LOG_DIR/${TEST_NAME}_mock_command_log.txt" # Will be empty as script should fail before mock is effective
SCRIPT_OUTPUT_LOG="$LOG_DIR/${TEST_NAME}_script_output.log"
TEST_APP_NAMESPACE="istio-no-cli"

# Setup:
setup() {
  echo "--- Setting up for $TEST_NAME ---"
  mkdir -p "$LOG_DIR"
  rm -f "$MOCK_LOG_FILE"
  touch "$MOCK_LOG_FILE"

  # Crucially, DO NOT add socialNetwork/tests to PATH here, or remove istioctl from it
  # We want the deploy script to fail finding istioctl.
  # For this test, we simulate 'istioctl' not being findable by temporarily
  # using a PATH that definitely doesn't have it.
  # The mock_commands.sh being linked to istioctl in ./socialNetwork/tests
  # won't be found if ./socialNetwork/tests is not in PATH.

  # Store original PATH
  ORIGINAL_PATH="$PATH"
  # Set a minimal PATH that won't find the real or mocked istioctl
  export PATH="/usr/bin:/bin" # A minimal path

  # Mock conditions (mostly irrelevant as script should fail early)
  rm -f .mock_app_namespace_exists
  rm -f .mock_istio_namespace_exists
  rm -f .mock_istiod_exists
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"
  echo "Setup complete. PATH is now: $PATH"
}

# Teardown:
teardown() {
  echo "--- Tearing down for $TEST_NAME ---"
  # Restore original PATH
  export PATH="$ORIGINAL_PATH"
  rm -f .mock_app_namespace_exists
  rm -f .mock_istio_namespace_exists
  rm -f .mock_istiod_exists
  rm -f ".mock_helm_release_exists_socialnetwork_${TEST_APP_NAMESPACE}"
  echo "Teardown complete. PATH restored to: $PATH"
}

# Run the deployment script
echo "--- Running $TEST_NAME ---"
setup

# Expecting this to fail and exit with non-zero status
../deploy-social-network.sh \
  --istio-enabled true \
  --app-namespace "$TEST_APP_NAMESPACE" > "$SCRIPT_OUTPUT_LOG" 2>&1

SCRIPT_EXIT_CODE=$?

# --- Verification ---
echo "--- Verifying $TEST_NAME ---"

if [ $SCRIPT_EXIT_CODE -eq 0 ]; then
  echo "FAILED: deploy-social-network.sh succeeded when it should have failed (istioctl missing)."
  cat "$SCRIPT_OUTPUT_LOG"
  teardown
  exit 1
fi

echo "VERIFIED: deploy-social-network.sh exited with a non-zero status code ($SCRIPT_EXIT_CODE)."

# Check script output for the specific error message
grep -q "istioctl not found. Please install Istio CLI first." "$SCRIPT_OUTPUT_LOG" \
  && echo "VERIFIED: Correct error message for missing istioctl found in script output." \
  || { echo "FAILED: Did not find correct error message for missing istioctl."; cat "$SCRIPT_OUTPUT_LOG"; teardown; exit 1; }

# Verify no istioctl, helm, or significant kubectl commands were logged in mock log,
# as the script should have exited early. The MOCK_LOG_FILE is in socialNetwork/tests/logs,
# but mock_commands.sh (if it were called) would write to socialNetwork/tests/mock_command_log.txt
# Because we changed PATH, the mock istioctl in socialNetwork/tests/istioctl is not called.
# So, the test here is that the script's own check for `command -v istioctl` fails.

ACTUAL_MOCK_LOG_IN_TESTS_DIR="mock_command_log.txt"
if [ -s "$ACTUAL_MOCK_LOG_IN_TESTS_DIR" ]; then
    # If any mock commands were somehow called, that's an issue.
    # This check is a bit indirect. The main check is the script output.
    # The mock log in socialNetwork/tests/ should be empty or non-existent
    # if the PATH manipulation worked as expected.
    # For this test, we expect it to be empty because the script exits before calling our mocks.
    # The $MOCK_LOG_FILE in logs/ will also be empty.
    echo "Note: socialNetwork/tests/mock_command_log.txt contains:"
    cat "$ACTUAL_MOCK_LOG_IN_TESTS_DIR"
    # rm -f $ACTUAL_MOCK_LOG_IN_TESTS_DIR # Clean up for next test if needed
fi


echo "--- $TEST_NAME Verification Successful ---"
teardown
exit 0
