{
  pkgs,
  lib,
  ...
} @ args: let
  select-rollup = lib.getExe args.select-rollup;
  cast = lib.getExe' pkgs.foundry-bin "cast";
  sops = lib.getExe pkgs.sops;
  jq = lib.getExe pkgs.jq;
in
  pkgs.writeShellScriptBin "fund-rollup" ''
    #!/usr/bin/env bash
    set -euo pipefail

    [[ -z "$SOPS_AGE_KEY" ]] && echo "Error: SOPS_AGE_KEY environment variable not set" && exit 1
    [[ -z "$ETH_RPC_URL" ]] && echo "Error: ETH_RPC_URL environment variable not set" && exit 1

    # Configuration
    PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    SECRETS_FILE="$PRJ_ROOT/sops/secrets.json"

    NETWORK=$(${select-rollup} --skip-l1 --show-full-path)

    L1_NAME="";
    L2_NAME=""
    L3_NAME=""

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
      exit 1
    fi

    NETWORK_PATH=""
    if [[ -z "$L3_NAME" ]]; then
      NETWORK_PATH="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME"
    else
      NETWORK_PATH="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME/$L3_NAME"
    fi

    ADDRESSES_FILE=$NETWORK_PATH/user-addresses.json

    FUND_WALLET_PRIVATE_KEY=$(${sops} decrypt $SECRETS_FILE | ${jq} -r '.fund_wallet_private_key')
    FUND_WALLET_ACCOUNT=$(${cast} wallet address --private-key $FUND_WALLET_PRIVATE_KEY)
    FUND_WALLET_BALANCE=$(${cast} balance $FUND_WALLET_ACCOUNT --rpc-url $ETH_RPC_URL)

    echo "Fund wallet balance: $(${cast} fw $FUND_WALLET_BALANCE) "

    BATCHER_ADDRESS=$(${jq} -r '.batcher' $ADDRESSES_FILE)
    BATCHER_BALANCE=$(${cast} balance $BATCHER_ADDRESS --rpc-url $ETH_RPC_URL)
    PROPOSER_ADDRESS=$(${jq} -r '.proposer' $ADDRESSES_FILE)
    PROPOSER_BALANCE=$(${cast} balance $PROPOSER_ADDRESS --rpc-url $ETH_RPC_URL)

    echo "Proposer($PROPOSER_ADDRESS) balance: $(${cast} fw $PROPOSER_BALANCE)"

    read -p "Send Proposer ($PROPOSER_ADDRESS) 1 ETH? (y/n): " confirm
    if [[ "$confirm" == [yY]* ]]; then
      ${cast} send $PROPOSER_ADDRESS --value=$(cast 2w 1) --rpc-url $ETH_RPC_URL --private-key $FUND_WALLET_PRIVATE_KEY
      PROPOSER_BALANCE=$(${cast} balance $PROPOSER_ADDRESS --rpc-url $ETH_RPC_URL)
      echo "New proposer balance: $PROPOSER_BALANCE"
    fi

    echo "Batcher($BATCHER_ADDRESS) balance: $(${cast} fw $BATCHER_BALANCE)"

    read -p "Send Batcher ($BATCHER_ADDRESS) 1 ETH? (y/n): " confirm
    if [[ "$confirm" == [yY]* ]]; then
      ${cast} send $BATCHER_ADDRESS --value=$(cast 2w 1) --rpc-url $ETH_RPC_URL --private-key $FUND_WALLET_PRIVATE_KEY
      BATCHER_BALANCE=$(${cast} balance $BATCHER_ADDRESS --rpc-url $ETH_RPC_URL)
      echo "New batcher balance: $BATCHER_BALANCE"
    fi
  ''
