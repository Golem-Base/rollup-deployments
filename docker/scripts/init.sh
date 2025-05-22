#!/bin/sh
set -exu

# Constants
INIT_DIR="/init"
EXECUTION_DIR="/execution"
ARTIFACTS_DIR="/artifacts"
REQUIRED_DIRS="$INIT_DIR $EXECUTION_DIR $ARTIFACTS_DIR"
GETH_DIR="/execution/geth"
GENESIS_FILE="$ARTIFACTS_DIR/genesis.json"
ROLLUP_JSON="$ARTIFACTS_DIR/rollup.json"
CHAIN_ID_FILE="$ARTIFACTS_DIR/chain-id"
JWT_FILE="$INIT_DIR/jwt"
SERVICE_IP_FILE="$INIT_DIR/service_ip"
PEERS_JSON_PATH="/peers/peers.json"
OP_NODE_STATIC_PEERS_FILE="$INIT_DIR/op_node_static_peers"
GETH_CONFIG_FILE="$INIT_DIR/geth_config"
K8S_NAMESPACE_FILE="/var/run/secrets/kubernetes.io/serviceaccount/namespace"

# Check required directories
check_required_directories() {
  for dir in $REQUIRED_DIRS; do
    if [ ! -d "$dir" ]; then
      echo "ERROR: Required directory $dir does not exist"
      exit 1
    fi
  done
}

# Initialize execution state if not already done
initialize_execution_state() {
  if [ ! -d "$GETH_DIR" ]; then
    geth init --state.scheme=hash --datadir="$EXECUTION_DIR" "$GENESIS_FILE"
    echo "Execution state initialized successfully"
  else
    echo "Execution state already initialized"
  fi
}

# Setup initial configuration files
setup_initial_config() {
  cp "$ROLLUP_JSON" "$INIT_DIR"
  cp "$CHAIN_ID_FILE" "$INIT_DIR"
  openssl rand -hex 32 >"$JWT_FILE"
}

# Extract service IP from pod name
extract_service_ip() {
  if [ -z "${POD_NAME:-}" ]; then
    echo "POD_NAME variable wasn't set, skipping service IP extraction and peering setup"
    return 0
  fi

  POD_BASE_NAME=$(echo "${POD_NAME}" | sed -E 's/-[0-9]+$//')

  if [ -z "${POD_BASE_NAME:-}" ]; then
    echo "Failed to extract POD_BASE_NAME from POD_NAME: $POD_NAME"
    exit 1
  fi

  namespace=$(cat "$K8S_NAMESPACE_FILE")
  service_fqdn="$POD_BASE_NAME.$namespace.svc.cluster.local"

  if getent hosts "$service_fqdn" >/dev/null 2>&1; then
    IP=$(getent hosts "$service_fqdn" | awk '{ print $1 }')
    if [ -n "${IP:-}" ]; then
      echo "$IP" >"$SERVICE_IP_FILE"
      echo "Found service for pod at ip: $(cat "$SERVICE_IP_FILE") from service fqdn: $service_fqdn"
    else
      echo "Failed to find IP from POD_BASE_NAME: $POD_BASE_NAME"
    fi
  else
    echo "$service_fqdn is not reachable"
  fi

  return 0
}

# Setup peer configuration
setup_peer_config() {
  if [ -z "${POD_NAME:-}" ]; then
    return 0
  fi

  POD_BASE_NAME=$(echo "${POD_NAME}" | sed -E 's/-[0-9]+$//')

  if [ ! -f "$PEERS_JSON_PATH" ]; then
    echo "$PEERS_JSON_PATH does not exist, skipping op-node and op-geth static peer construction"
    return 0
  fi

  PEERS_JSON=$(jq -r --arg pod_base_name "$POD_BASE_NAME" '.[] | select(.name != $pod_base_name)' "$PEERS_JSON_PATH")
  printf "Found peers: \n%s\n\n" "$PEERS_JSON"

  # Configure op-node static peers
  echo "$PEERS_JSON" |
    jq -r ".consensus" |
    tr '\n' ',' |
    sed 's/,$//' \
      >"$OP_NODE_STATIC_PEERS_FILE"

  # Configure geth static peers
  EXECUTION_PEERS=$(echo "$PEERS_JSON" |
    jq -r ".execution" |
    sed 's/^/  "/' |
    sed 's/$/",/' |
    sed '$s/,$//')

  cat >"$GETH_CONFIG_FILE" <<EOF
[Node.P2P]
StaticNodes = [
$EXECUTION_PEERS
]
TrustedNodes = [
$EXECUTION_PEERS
]
EOF
}

# Main function
main() {
  check_required_directories
  initialize_execution_state
  setup_initial_config
  extract_service_ip
  setup_peer_config
}

# Execute main function
main
