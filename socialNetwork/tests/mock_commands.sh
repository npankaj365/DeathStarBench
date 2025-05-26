#!/bin/bash

COMMAND_LOG_FILE="mock_command_log.txt"

# Ensure log file is clean for a new test run (test script should manage this)
# echo "Mock script loaded. Logging to $COMMAND_LOG_FILE"

# Get the actual command name
CMD_NAME=$(basename "$0")

# Log the command and its arguments
echo "$CMD_NAME $@" >> "$COMMAND_LOG_FILE"

# Simulate behavior based on the command
case "$CMD_NAME" in
  kubectl)
    case "$1" in
      get)
        if [[ "$2" == "namespace" && "$3" == "istio-system" ]]; then
          # Simulate Istio namespace exists for some tests, not for others
          if [[ -f ".mock_istio_namespace_exists" ]]; then
            echo "Namespace istio-system found." # Simulate found
            exit 0
          else
            echo "Error from server (NotFound): namespaces \"istio-system\" not found"
            exit 1 # Simulate not found
          fi
        elif [[ "$2" == "namespace" && "$3" == "custom-app-ns" ]]; then
           if [[ -f ".mock_app_namespace_exists" ]]; then
            echo "Namespace custom-app-ns found."
            exit 0
          else
            echo "Error from server (NotFound): namespaces \"custom-app-ns\" not found"
            exit 1
          fi
        elif [[ "$2" == "namespace" && "$3" == "default" ]]; then
            echo "Namespace default found." # Default namespace always exists
            exit 0
        elif [[ "$2" == "deployment" && "$3" == "istiod" && "$5" == "istio-system" ]]; then
          if [[ -f ".mock_istiod_exists" ]]; then
            echo "Deployment istiod found."
            exit 0
          else
            echo "Error from server (NotFound): deployments.apps \"istiod\" not found"
            exit 1
          fi
        fi
        ;;
      create)
        if [[ "$1" == "namespace" ]]; then
          # Simulate namespace creation success
          echo "namespace/$3 created"
          exit 0
        fi
        ;;
      label)
        # Simulate label success
        echo "namespace/$3 labeled"
        exit 0
        ;;
      apply)
        # Simulate apply success
        echo "applied"
        exit 0
        ;;
      delete)
        # Simulate delete success
        echo "deleted"
        exit 0
        ;;
      *)
        # Default success for other kubectl commands
        exit 0
        ;;
    esac
    ;;
  helm)
    case "$1" in
      status)
        # $2 is release name, $4 is namespace
        if [[ -f ".mock_helm_release_exists_${2}_${4}" ]]; then
          echo "STATUS: deployed" # Simulate release exists
          exit 0
        else
          echo "Error: release: not found"
          exit 1 # Simulate release does not exist
        fi
        ;;
      install|upgrade)
        # Simulate helm install/upgrade success
        echo "Release \"$2\" has been installed." # or upgraded
        exit 0
        ;;
      get)
        if [[ "$2" == "values" ]]; then
          # Simulate fetching a value, e.g. gatewayName
          echo "socialnetwork-gateway" # Return a default value
          exit 0
        fi
        ;;
      *)
        # Default success for other helm commands
        exit 0
        ;;
    esac
    ;;
  istioctl)
    case "$1" in
      install)
        # Simulate istioctl install success
        # And create the .mock_istiod_exists marker
        touch .mock_istiod_exists
        echo "Istio CNI installed."
        echo "Istio Discovery installed."
        echo "Istio Ingress gateways installed."
        echo "Istio Egress gateways installed."
        echo "Installation complete."
        exit 0
        ;;
      *)
        # Default success for other istioctl commands
        exit 0
        ;;
    esac
    ;;
  *)
    echo "Mock for $CMD_NAME not implemented."
    exit 127 # Command not found
    ;;
esac

# Default exit code if no specific case matched
exit 0
