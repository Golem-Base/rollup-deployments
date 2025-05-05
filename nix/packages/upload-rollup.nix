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
  docker = lib.getExe pkgs.docker;
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
    DOPPLER_KEY_NAME=$(echo "''${DEPLOYMENT_NAME}" | tr '[:lower:]' '[:upper:]')

    ${doppler} secrets get $DOPPLER_KEY_NAME --project "golem-base" --config "prd" --token $DOPPLER_TOKEN > /dev/null 2>/dev/null;
    DOPPLER_SUCCESS=$?
    if [ ! "$DOPPLER_SUCCESS" -eq 0 ]; then
      ${doppler} secrets set $DOPPLER_KEY_NAME "$USER_PRIVATE_KEYS" --type "json" --project "golem-base" --config "prd" --token $DOPPLER_TOKEN
    else
      echo "Doppler secret $DOPPLER_KEY_NAME already set"
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
    unset MC_HOST_s3

    QUAY_USERNAME=$(${sops} -d $SECRETS_FILE | ${jq} -r ".quay.username")
    QUAY_TOKEN=$(${sops} -d $SECRETS_FILE | ${jq} -r ".quay.token")

    TIMESTAMP=$(date '+%Y%m%d%H%M%S')
    IMAGE_NAME=''${IMAGE_NAME:-"golem-base-init"}
    IMAGE_TAG="$DEPLOYMENT_NAME--$TIMESTAMP"
    FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_TAG"
    REPOSITORY_NAME="rollup-deployments"

    DOCKER_DIR=$(mktemp -d)
    mkdir -p $DOCKER_DIR/scripts $DOCKER_DIR/artifacts

    cp $PRJ_ROOT/docker/Dockerfile $DOCKER_DIR/
    cp -r $TMP_DIR/* $DOCKER_DIR/artifacts/
    cp -r $PRJ_ROOT/docker/scripts/* $DOCKER_DIR/scripts/

    ${docker} buildx build --tag $FULL_IMAGE_NAME $DOCKER_DIR
    if [ $? -ne 0 ]; then
      echo "Error: Failed to build Docker image"
      exit 1
    fi

    echo "Logging in to Quay.io..."
    echo "$QUAY_TOKEN" | docker login quay.io -u "$QUAY_USERNAME" --password-stdin
    QUAY_IMAGE="quay.io/golemnetwork/$REPOSITORY_NAME:$IMAGE_NAME--$IMAGE_TAG"

    echo "Tagging image for Quay.io..."
    docker tag "$FULL_IMAGE_NAME" "$QUAY_IMAGE"

    echo "Pushing image to Quay.io..."
    docker push "$QUAY_IMAGE"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to push image to Quay.io"
      exit 1
    fi

    echo "Success! Image uploaded to Quay.io"
    echo "Image URL: https://$QUAY_IMAGE"

    docker logout quay.io

    rm -rf "$TMP_DIR"
    rm -rf "$DOCKER_DIR"
  ''
