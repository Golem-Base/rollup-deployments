#!/bin/sh
set -exu

for dir in "/init" "/execution" "/artifacts"; do
  if [ ! -d "$dir" ]; then
    echo "ERROR: Required directory $dir does not exist"
    exit 1
  fi
done

if [ ! -d /execution/geth ]; then
  geth init --state.scheme=hash --datadir=/execution /artifacts/genesis.json
  echo "Execution state initialized successfully"
else
  echo "Execution state already initialized"
fi

apk add --no-cache jq openssl

cp /artifacts/rollup.json /init
cp /artifacts/chain-id /init

openssl rand -hex 32 > /init/jwt

if [ -n "${POD_NAME:-}" ]; then
  POD_BASE_NAME=$(echo "${POD_NAME}" | sed -E 's/-[0-9]+$//')

  if [ -n "${POD_BASE_NAME:-}" ]; then
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    service_fqdn="$POD_BASE_NAME.$namespace.svc.cluster.local"
    if getent hosts "$service_fqdn" > /dev/null 2>&1; then
      IP=$(getent hosts "$POD_BASE_NAME.$namespace.svc.cluster.local" | awk '{ print $1 }')
      if [ -n "${IP:-}" ]; then
        echo "$IP" > /init/service_ip
        echo "Found service for pod at ip: $(cat /init/service_ip) from service fqdn: $service_fqdn"
      else
        echo "Failed to find IP from POD_BASE_NAME: $POD_BASE_NAME"
      fi
    else
      echo "$service_fqdn is not reachable"
    fi

    PEERS_JSON_PATH="/peers/peers.json"
    if [ -f "$PEERS_JSON_PATH" ]; then
      PEERS_JSON=$(jq -r --arg pod_base_name "$POD_BASE_NAME" '.[] | select(.name != $pod_base_name)' $PEERS_JSON_PATH)
      printf "Found peers: \n%s\n" "$PEERS_JSON"

      echo "$PEERS_JSON" \
        | jq -r ".consensus" \
        | tr '\n' ',' \
        | sed 's/,$//' \
        > /init/op_node_static_peers

      EXECUTION_PEERS=$(echo "$PEERS_JSON" \
        | jq -r ".execution" \
        | sed 's/^/  "/' \
        | sed 's/$/",/' \
        | sed '$s/,$//')

      cat > /init/geth_config << EOF
[Node.P2P]
StaticNodes = [
$EXECUTION_PEERS
]
TrustedNodes = [
$EXECUTION_PEERS
]
EOF
    else
      echo "$PEERS_JSON_PATH does not exist, skipping op-node and op-geth static peer construction"
    fi
  else
    echo "Failed to extract POD_BASE_NAME from POD_NAME: $POD_NAME"
    exit 1
  fi
else
  echo "POD_NAME variable wasn't set, skipping service IP extraction and peering setup"
fi
