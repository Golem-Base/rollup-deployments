{
  pkgs,
  lib,
  ...
} @ args: let
  select-network = lib.getExe args.select-network;
  op-deployer = lib.getExe args.op-deployer;
  dasel = lib.getExe pkgs.dasel;
in
  pkgs.writeShellScriptBin "deploy-network" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Configuration
    PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    CHAIN_IDS_FILE="''${CHAIN_IDS_FILE:-$PRJ_ROOT/deployments/chain-ids.json}"

    PROTOCOL_VERSION="0x0000000000000000000000000000000000000009000000000000000000000000"

    L1_ARTIFACTS_LOCATOR="tag://op-contracts/v2.0.0-rc.1"
    L2_ARTIFACTS_LOCATOR="tag://op-contracts/v1.7.0-beta.1+l2-contracts"

    i=1
    while [ $i -le $# ]; do
      arg="''${!i}"
      case "$arg" in
        --l1-artifacts-locator)
          if [ $i -lt $# ]; then
            i=$((i+1))
            L1_ARTIFACTS_LOCATOR="''${!i}"
          else
            echo "Error: --l1-artifacts-locator requires a value" >&2
            exit 1
          fi
          ;;
        --l2-artifacts-locator)
          if [ $i -lt $# ]; then
            i=$((i+1))
            L2_ARTIFACTS_LOCATOR="''${!i}"
          else
            echo "Error: --l2-artifacts-locator requires a value" >&2
            exit 1
          fi
          ;;
        --l1-artifacts-locator=*)
          L1_ARTIFACTS_LOCATOR="''${arg#*=}"
          ;;
        --l2-artifacts-locator=*)
          L2_ARTIFACTS_LOCATOR="''${arg#*=}"
          ;;
        *)
          echo "Unknown argument: $arg" >&2
          exit 1
          ;;
      esac
      i=$((i+1))
    done


    if [ ! -f "$CHAIN_IDS_FILE" ]; then
        echo "Error: chain-ids.json not found at $CHAIN_IDS_FILE"
        exit 1
    fi

    NETWORK=$(${select-network} --skip-l1 --show-full-path)

    L1_NAME="";
    L2_NAME=""
    L3_NAME=""

    if [[ "$NETWORK" == */*/* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      remaining="''${NETWORK#*/}"
      L2_NAME="''${remaining%%/*}"
      L3_NAME="''${remaining#*/}"
    elif [[ "$NETWORK" == */* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      L2_NAME="''${NETWORK#*/}"
    else
      echo "Can't deploy a L1 network: $NETWORK, exiting doing nothing..."
      exit 1
    fi

    WORK_DIR=""

    if [[ -z "$L3_NAME" ]]; then
      WORK_DIR="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME"
    else
      WORK_DIR="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME/$L3_NAME"
    fi

    INTENT_FILE="$WORK_DIR/intent.toml"
    STATE_FILE="$WORK_DIR/state.json"
    USER_ADDRESSES_FILE="$WORK_DIR/user-addresses.json"
    USER_PRIVATE_KEYS_FILE="$WORK_DIR/user-private-keys.json"

    # ${dasel} put -f $INTENT_FILE -r toml -t string -v "$L1_ARTIFACTS_LOCATOR" "l1ContractsLocator"
    # ${dasel} put -f $INTENT_FILE -r toml -t string -v "$L2_ARTIFACTS_LOCATOR" "l2ContractsLocator"
  ''
