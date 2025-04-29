{
  pkgs,
  lib,
  ...
} @ args: let
  select-rollup = lib.getExe args.select-rollup;
  doppler = lib.getExe pkgs.doppler;
  sops = lib.getExe pkgs.sops;
  jq = lib.getExe pkgs.jq;
  mc = lib.getExe pkgs.minio-client;
in
  pkgs.writeShellScriptBin "delete-rollup" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Configuration
    PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    CHAIN_IDS_FILE="''${CHAIN_IDS_FILE:-$PRJ_ROOT/deployments/chain-ids.json}"
    SECRETS_FILE="$PRJ_ROOT/sops/secrets.json"

    if [ ! -f "$CHAIN_IDS_FILE" ]; then
        echo "Error: chain-ids.json not found at $CHAIN_IDS_FILE"
        exit 1
    fi

    NETWORK=$(${select-rollup} --skip-l1 --show-full-path)

    L1_NAME="";
    L2_NAME=""
    L3_NAME=""

    TMP_CHAIN=$(mktemp)
    cp "$CHAIN_IDS_FILE" "$TMP_CHAIN"
    if [[ "$NETWORK" == */*/* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      remaining="''${NETWORK#*/}"
      L2_NAME="''${remaining%%/*}"
      L3_NAME="''${remaining#*/}"
      DEPLOYMENT_NAME=$L3_NAME
      jq --arg l1 $L1_NAME --arg l2 $L2_NAME --arg l3 $L3_NAME 'del(.[$l1][$l2][$l3])' $CHAIN_IDS_FILE > $TMP_CHAIN
    elif [[ "$NETWORK" == */* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      L2_NAME="''${NETWORK#*/}"
      DEPLOYMENT_NAME=$L2_NAME
      jq --arg l1 $L1_NAME --arg l2 $L2_NAME 'del(.[$l1][$l2])' $CHAIN_IDS_FILE > $TMP_CHAIN
    else
      echo "Can't delete a L1 network: $NETWORK, exiting doing nothing..."
      exit 1
    fi

    NETWORK_PATH=""
    if [[ -z "$L3_NAME" ]]; then
      NETWORK_PATH="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME"
    else
      NETWORK_PATH="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME/$L3_NAME"
    fi

    NETWORK_PATH_FILES=$(tree $NETWORK_PATH)

    DOPPLER_TOKEN=$(${sops} decrypt $SECRETS_FILE | ${jq} '.doppler_token' | tr -d '"')
    DOPPLER_KEY_NAME=$(echo "''${DEPLOYMENT_NAME}__private_keys" | tr '[:lower:]' '[:upper:]')

    ENDPOINT=fsn1.your-objectstorage.com
    ACCESS_KEY=$(sops -d "$SECRETS_FILE" | jq -r '.hetzner_storage.access_key')
    SECRET_KEY=$(sops -d "$SECRETS_FILE" | jq -r '.hetzner_storage.secret_key')
    BUCKET_NAME="rollup-deployments"

    echo
    echo "Proposed changes to $CHAIN_IDS_FILE:"
    diff --color -u "$CHAIN_IDS_FILE" "$TMP_CHAIN" || true
    echo -e "Will additionally delete all data contained under:\n> $NETWORK_PATH_FILES"
    echo -e "Will additionally delete storage under:\n> s3/$BUCKET_NAME/$DEPLOYMENT_NAME"
    echo -e "Will additionally delete doppler secret under:\n> $DOPPLER_KEY_NAME"

    # Validate extracted information
    if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
        echo "Error: Failed to extract all required information from SOPS config file"
        echo "Make sure your SOPS file contains access_key, secret_key"
        exit 1
    fi

    read -p "Apply these updates and proceed? (y/n): " confirm
    if [[ "$confirm" != [yY]* ]]; then
      echo "Aborting. No changes made."
      exit 0
    fi

    mv "$TMP_CHAIN" "$CHAIN_IDS_FILE"
    rm -rf $NETWORK_PATH

    if ${doppler} secrets get $DOPPLER_KEY_NAME --type "json" --project "golem-base" --config "prd" --token $DOPPLER_TOKEN > /dev/null 2>&1; then
      ${doppler} secrets delete $DOPPLER_KEY_NAME --type "json" --project "golem-base" --config "prd" --token $DOPPLER_TOKEN
    fi

    export MC_HOST_s3="https://$ACCESS_KEY:$SECRET_KEY@$ENDPOINT"
    if ${mc} stat s3/$BUCKET_NAME/$DEPLOYMENT_NAME > /dev/null 2>&1; then
      ${mc} rm "s3/$BUCKET_NAME/$DEPLOYMENT_NAME"
    fi

    echo "Done"
  ''
