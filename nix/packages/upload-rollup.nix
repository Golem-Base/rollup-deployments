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

    if ${doppler} secrets get $DOPPLER_KEY_NAME --type "json" --project "golem-base" --config "prd" --token $DOPPLER_TOKEN > /dev/null 2>&1; then
      echo "Found secret for $DOPPLER_KEY_NAME"
    else
      ${doppler} secrets set $DOPPLER_KEY_NAME "$USER_PRIVATE_KEYS" --type "json" --project "golem-base" --config "prd" --token $DOPPLER_TOKEN
    fi

    ENDPOINT=fsn1.your-objectstorage.com
    ACCESS_KEY=$(sops -d "$SECRETS_FILE" | jq -r '.hetzner_storage.access_key')
    SECRET_KEY=$(sops -d "$SECRETS_FILE" | jq -r '.hetzner_storage.secret_key')
    BUCKET_NAME="rollup-deployments"

    # Validate extracted information
    if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
        echo "Error: Failed to extract all required information from SOPS config file"
        echo "Make sure your SOPS file contains access_key, secret_key"
        exit 1
    fi

    export MC_HOST_s3="https://$ACCESS_KEY:$SECRET_KEY@$ENDPOINT"
    if ${mc} stat s3/$BUCKET_NAME/$DEPLOYMENT_NAME > /dev/null 2>&1; then
      echo "$DEPLOYMENT_NAME already uploaded"
    else
      echo "Uploading $DEPLOYMENT_NAME..."
      for file in "$TMP_DIR"/*; do
          if [ -f "$file" ] && [[ ! $(basename "$file") == .* ]]; then
              filename=$(basename "$file")
              echo "Uploading $filename..."
              ${mc} cp "$file" "s3/$BUCKET_NAME/$DEPLOYMENT_NAME/$filename"

              # Check individual file upload status
              if [ $? -ne 0 ]; then
                  echo "Warning: Failed to upload $filename, deleting $DEPLOYMENT_NAME"
                  ${mc} rm "s3/$BUCKECT_NAME/$DEPLOYMENT_NAME"
              fi
          fi
      done

    fi

    rm -rf "$TMP_DIR"
    unset MC_HOST_s3
  ''
