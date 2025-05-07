#!/bin/sh
set -euo pipefail

for dir in "/init" "/execution" "/artifacts" "/peers"; do
  if [ ! -d "$dir" ]; then
    echo "ERROR: Required directory $dir does not exist"
    exit 1
  fi
done

if [ -z "${POD_NAME:-}" ]; then
  echo "ERROR: Required environment variable \$POD_NAME is not set"
  exit 1
fi

if ! jq empty /peers/peers.json > /dev/null 2>&1; then
  echo "ERROR: /peers/peers.json is not valid JSON"
  exit 1
fi

if [ ! -d /execution/geth ]; then
  geth init --state.scheme=hash --datadir=/execution /artifacts/genesis.json
fi

cp /artifacts/rollup.json /init
cp /artifacts/chain-id /init

POD_BASE_NAME=$(echo "${POD_NAME}" | sed -E 's/-[0-9]+$//')
getent hosts "$POD_BASE_NAME.$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace).svc.cluster.local" | awk '{ print $1 }' > /init/service_ip
echo "Found service for pod at ip: $(cat /init/service_ip)"

PEERS_JSON=$(jq -r --arg pod_base_name "$POD_BASE_NAME" '.[] | select(.name != $pod_base_name)' /peers/peers.json)
echo -e "Found peers: \n$PEERS_JSON\n"

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

openssl rand -hex 32 > /init/jwt
