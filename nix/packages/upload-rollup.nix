{
  pkgs,
  lib,
  ...
} @ args: let
  select-rollup = lib.getExe args.select-rollup;
  mc = lib.getExe pkgs.minio-client;
  doppler = lib.getExe pkgs.doppler;
  sops = lib.getExe pkgs.sops;
  jq = lib.getExe pkgs.jq;
in
  pkgs.writeShellScriptBin "upload-rollup" ''
    NETWORK=$(${select-rollup} --skip-l1 --show-full-path)

    [[ -z "$SOPS_AGE_KEY" ]] && echo "Error: SOPS_AGE_KEY environment variable not set" && exit 1

    PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    CHAIN_IDS_FILE="''${CHAIN_IDS_FILE:-$PRJ_ROOT/deployments/chain-ids.json}"
    SECRETS_FILE="$PRJ_ROOT/sops/secrets.json"

    if [ ! -f "$CHAIN_IDS_FILE" ]; then
        echo "Error: chain-ids.json not found at $CHAIN_IDS_FILE"
        exit 1
    fi

    if [[ "$NETWORK" == */*/* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      remaining="''${NETWORK#*/}"
      L2_NAME="''${remaining%%/*}"
      L3_NAME="''${remaining#*/}"
      DEPLOYMENT_NAME=$L3_NAME
    elif [[ "$NETWORK" == */* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      L2_NAME="''${NETWORK#*/}"
      DEPLOYMENT_NAME=$L2_NAME
    else
      echo "Error, exiting doing nothing..."
      exit 1
    fi

    NETWORK_PATH=""
    if [[ -z "$L3_NAME" ]]; then
      NETWORK_PATH="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME"
    else
      NETWORK_PATH="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME/$L3_NAME"
    fi

    INTENT_FILE="$NETWORK_PATH/intent.toml"
    CHAIN_ID_FILE="$NETWORK_PATH/chain-id"
    STATE_FILE="$NETWORK_PATH/state.json"
    USER_ADDRESSES_FILE="$NETWORK_PATH/user-addresses.json"
    USER_PRIVATE_KEYS_FILE="$NETWORK_PATH/user-private-keys.json"
    SUPERCHAIN_FILE="$NETWORK_PATH/superchain.json"
    IMPLEMENTATIONS_FILE="$NETWORK_PATH/implementations.json"
    PROXY_FILE="$NETWORK_PATH/proxy.json"
    GENESIS_FILE="$NETWORK_PATH/genesis.json"
    ROLLUP_FILE="$NETWORK_PATH/rollup.json"
    L1_ADDRESSES_FILE="$NETWORK_PATH/l1_addresses.json"

    TMP_DIR=$(mktemp -d)
    cp $INTENT_FILE $CHAIN_ID_FILE $STATE_FILE $USER_ADDRESSES_FILE $SUPERCHAIN_FILE $IMPLEMENTATIONS_FILE $PROXY_FILE $GENESIS_FILE $ROLLUP_FILE $L1_ADDRESSES_FILE $TMP_DIR

    USER_PRIVATE_KEYS=$(${sops} -d $USER_PRIVATE_KEYS_FILE | ${jq})

    DOPPLER_TOKEN=$(${sops} decrypt $SECRETS_FILE | ${jq} '.doppler_token' | tr -d '"')
    DOPPLER_KEY_NAME=$(echo "''${DEPLOYMENT_NAME}__private_keys" | tr '[:lower:]' '[:upper:]')

    ${doppler} secrets set $DOPPLER_KEY_NAME "$USER_PRIVATE_KEYS" --type "json" --project "golem-base" --config "prd" --token $DOPPLER_TOKEN

    ENDPOINT=$(sops -d "$SOPS_CONFIG" | jq -r '.minio.endpoint')
    ACCESS_KEY=$(sops -d "$SOPS_CONFIG" | jq -r '.minio.access_key')
    SECRET_KEY=$(sops -d "$SOPS_CONFIG" | jq -r '.minio.secret_key')
    BUCKET_NAME=$(sops -d "$SOPS_CONFIG" | jq -r '.minio.bucket')

    # Validate extracted information
    if [ -z "$ENDPOINT" ] || [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ] || [ -z "$BUCKET_NAME" ]; then
        echo "Error: Failed to extract all required information from SOPS config file"
        echo "Make sure your SOPS file contains endpoint, access_key, secret_key, and bucket fields"
        exit 1
    fi

    echo "Uploading directory '$LOCAL_DIR' to bucket '$BUCKET_NAME/$REMOTE_PATH'..."

    # Use the AWS S3 compatible approach with environment variables
    # This avoids the need to set aliases in the config file
    export MC_HOST_s3="https://$ACCESS_KEY:$SECRET_KEY@$ENDPOINT"

    # Upload the directory recursively
    mc cp --recursive "$TMP_DIR" "s3/$BUCKET_NAME/$DEPLOYMENT_NAME"

    # # Unset environment variables to clean up
    # unset MC_HOST_s3

    ${mc} put $GENESIS_FILE gb/golem-base/$DEPLOYMENT_NAME/genesis.json
    # # mc put ./{{ network }}/rollup.json gb/golem-base/{{ network }}-l2/rollup.json
    # # mc put ./{{ network }}/state.json gb/golem-base/{{ network }}-l2/state.json

  ''
