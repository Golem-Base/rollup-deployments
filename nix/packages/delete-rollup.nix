{
  pkgs,
  lib,
  ...
} @ args: let
  select-rollup = lib.getExe args.select-rollup;
in
  pkgs.writeShellScriptBin "delete-rollup" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Configuration
    PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    CHAIN_IDS_FILE="''${CHAIN_IDS_FILE:-$PRJ_ROOT/deployments/chain-ids.json}"

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
      jq --arg l1 $L1_NAME --arg l2 $L2_NAME --arg l3 $L3_NAME 'del(.[$l1][$l2][$l3])' $CHAIN_IDS_FILE > $TMP_CHAIN
    elif [[ "$NETWORK" == */* ]]; then
      L1_NAME="''${NETWORK%%/*}"
      L2_NAME="''${NETWORK#*/}"
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
    echo
    echo "Proposed changes to $CHAIN_IDS_FILE:"
    diff --color -u "$CHAIN_IDS_FILE" "$TMP_CHAIN" || true
    echo -e "Will additionally delete all data contained under:\n> $NETWORK_PATH_FILES"

    # Fixed confirmation prompt
    read -p "Apply these updates and proceed? (y/n): " confirm
    if [[ "$confirm" != [yY]* ]]; then
      echo "Aborting. No changes made."
      exit 0
    fi

    mv "$TMP_CHAIN" "$CHAIN_IDS_FILE"
    rm -rf $NETWORK_PATH

    echo "Done"
  ''
