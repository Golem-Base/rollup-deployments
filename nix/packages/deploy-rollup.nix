{
  pkgs,
  lib,
  ...
} @ args: let
  select-rollup = lib.getExe args.select-rollup;
  op-deployer = lib.getExe args.op-deployer;
  dasel = lib.getExe pkgs.dasel;
  cast = lib.getExe' pkgs.foundry-bin "cast";
  sops = lib.getExe pkgs.sops;
  jq = lib.getExe pkgs.jq;
  openssl = lib.getExe pkgs.openssl;
in
  pkgs.writeShellScriptBin "deploy-rollup" ''
    #!/usr/bin/env bash
    set -euo pipefail

    [[ -z "$SOPS_AGE_KEY" ]] && echo "Error: SOPS_AGE_KEY environment variable not set" && exit 1
    [[ -z "$ETH_RPC_URL" ]] && echo "Error: ETH_RPC_URL environment variable not set" && exit 1

    # Configuration
    PRJ_ROOT="''${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
    CHAIN_IDS_FILE="''${CHAIN_IDS_FILE:-$PRJ_ROOT/deployments/chain-ids.json}"
    SECRETS_FILE="$PRJ_ROOT/sops/secrets.json"

    # TODO This should be improved upon, with better args
    PROTOCOL_VERSION="0x0000000000000000000000000000000000000009000000000000000000000000"
    L1_CONTRACTS_RELEASE="op-contracts/v2.0.0-rc.1";
    L1_ARTIFACTS_LOCATOR="tag://op-contracts/v2.0.0-rc.1"
    L2_ARTIFACTS_LOCATOR="tag://op-contracts/v1.7.0-beta.1+l2-contracts"

    if [ ! -f "$CHAIN_IDS_FILE" ]; then
        echo "Error: chain-ids.json not found at $CHAIN_IDS_FILE"
        exit 1
    fi

    NETWORK=$(${select-rollup} --skip-l1 --show-full-path)

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
      echo "no selection, exiting..."
      exit 1
    fi

    WORK_DIR=""

    if [[ -z "$L3_NAME" ]]; then
      WORK_DIR="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME"
    else
      WORK_DIR="$PRJ_ROOT/deployments/$L1_NAME/$L2_NAME/$L3_NAME"
    fi

    INTENT_FILE="$WORK_DIR/intent.toml"
    NEW_CHAIN_ID_FILE="$WORK_DIR/chain-id"
    STATE_FILE="$WORK_DIR/state.json"
    USER_ADDRESSES_FILE="$WORK_DIR/user-addresses.json"
    USER_PRIVATE_KEYS_FILE="$WORK_DIR/user-private-keys.json"

    SUPERCHAIN_FILE="$WORK_DIR/superchain.json"
    IMPLEMENTATIONS_FILE="$WORK_DIR/implementations.json"
    PROXY_FILE="$WORK_DIR/proxy.json"
    GENESIS_FILE="$WORK_DIR/genesis.json"
    ROLLUP_FILE="$WORK_DIR/rollup.json"
    L1_ADDRESSES_FILE="$WORK_DIR/l1_addresses.json"

    ADMIN_ADDR=$(${jq} -r '.admin' $USER_ADDRESSES_FILE)
    SEQUENCER_ADDR=$(${jq} -r '.seqeuencer' $USER_ADDRESSES_FILE)
    BATCHER_ADDR=$(${jq} -r '.batcher' $USER_ADDRESSES_FILE)
    PROPOSER_ADDR=$(${jq} -r '.proposer' $USER_ADDRESSES_FILE)
    CHALLENGER_ADDR=$(${jq} -r '.challenger' $USER_ADDRESSES_FILE)
    GUARDIAN_ADDR=$(${jq} -r '.guardian' $USER_ADDRESSES_FILE)
    FEE_RECIPIENT_ADDR=$(${jq} -r '.fee_recipient' $USER_ADDRESSES_FILE)

    FUND_WALLET_PRIVATE_KEY=$(${sops} decrypt $SECRETS_FILE | ${jq} '.fund_wallet_private_key' | tr -d '"')
    FUND_WALLET_ACCOUNT=$(${cast} wallet address --private-key $FUND_WALLET_PRIVATE_KEY)
    FUND_WALLET_BALANCE=$(${cast} balance $FUND_WALLET_ACCOUNT --rpc-url $ETH_RPC_URL)
    echo "Fund wallet balance: $(${cast} fw $FUND_WALLET_BALANCE) "

    export IMPL_SALT=$(${openssl} rand -hex 32)

    CHAIN_ID=$(${cast} chain-id --rpc-url $ETH_RPC_URL)

    if [ ! -f $SUPERCHAIN_FILE ]; then
      echo "No superchain file detected..."
      echo -e "Will set artifact locators as:\n\tl1ContractsLocator: $L1_ARTIFACTS_LOCATOR\n\tl2ContractsLocator: $L2_ARTIFACTS_LOCATOR"
      read -p "Proceed deploying superchain contracts? (y/n): " confirm
      if [[ "$confirm" != [yY]* ]]; then
        echo "Aborting. No changes made."; exit 0
      fi

      echo "Bootstrapping Superchain"
      ${dasel} put -f $INTENT_FILE -r toml -t string -v "$L1_ARTIFACTS_LOCATOR" "l1ContractsLocator"
      ${dasel} put -f $INTENT_FILE -r toml -t string -v "$L2_ARTIFACTS_LOCATOR" "l2ContractsLocator"

      ${op-deployer} bootstrap superchain \
          --private-key=$FUND_WALLET_PRIVATE_KEY \
          --l1-rpc-url=$ETH_RPC_URL \
          --artifacts-locator=$L1_ARTIFACTS_LOCATOR \
          --guardian=$GUARDIAN_ADDR \
          --recommended-protocol-version=$PROTOCOL_VERSION \
          --required-protocol-version=$PROTOCOL_VERSION \
          --superchain-proxy-admin-owner=$ADMIN_ADDR \
          --protocol-versions-owner=$ADMIN_ADDR \
          --outfile=$SUPERCHAIN_FILE
    else
      echo "Superchain contracts already deployed..."
    fi

    # TODO This changes in later versions
    SUPERCHAIN_CONFIG_PROXY=$(${dasel} select -f $SUPERCHAIN_FILE -s ".SuperchainConfigProxy" -w plain)
    SUPERCHAIN_PROXY_ADMIN=$(${dasel} select -f $SUPERCHAIN_FILE -s ".SuperchainProxyAdmin" -w plain)
    PROTOCOL_VERSIONS_PROXY=$(${dasel} select -f $SUPERCHAIN_FILE -s ".ProtocolVersionsProxy" -w plain)

    if [ ! -f $IMPLEMENTATIONS_FILE ]; then
      echo "No implementations file detected..."
      read -p "Proceed deploying implementations contracts? (y/n): " confirm
      if [[ "$confirm" != [yY]* ]]; then
        echo "Aborting. No changes made."; exit 0
      fi
      ${op-deployer} bootstrap implementations \
          --gb-superchain-proxy-admin=$SUPERCHAIN_PROXY_ADMIN \
          --superchain-config-proxy=$SUPERCHAIN_CONFIG_PROXY \
          --protocol-versions-proxy=$PROTOCOL_VERSIONS_PROXY \
          --private-key=$FUND_WALLET_PRIVATE_KEY \
          --l1-rpc-url=$ETH_RPC_URL \
          --artifacts-locator=$L1_ARTIFACTS_LOCATOR \
          --l1-contracts-release=$L1_CONTRACTS_RELEASE \
          --upgrade-controller=$ADMIN_ADDR \
          --outfile=$IMPLEMENTATIONS_FILE
    else
      echo "Implementation contracts already deployed..."
    fi

    if [ ! -f $PROXY_FILE ]; then
      echo "No proxy file detected..."
      read -p "Proceed deploying proxy contracts? (y/n): " confirm
      if [[ "$confirm" != [yY]* ]]; then
        echo "Aborting. No changes made."; exit 0
      fi
      ${op-deployer} bootstrap proxy \
          --private-key=$FUND_WALLET_PRIVATE_KEY \
          --l1-rpc-url=$ETH_RPC_URL  \
          --artifacts-locator=$L1_ARTIFACTS_LOCATOR \
          --proxy-owner=$ADMIN_ADDR \
          --outfile=$PROXY_FILE
    else
      echo "Proxy contracts already deployed..."
    fi

    APPLIED_INTENT=$(jq '.appliedIntent != null' $STATE_FILE)

    if [[ $APPLIED_INTENT == false ]]; then
      echo "Detected intent has not been applied ..."
      read -p "Proceed applying intent? (y/n): " confirm
      if [[ "$confirm" != [yY]* ]]; then
        echo "Aborting. No changes made."; exit 0
      fi
      ${op-deployer} apply \
          --private-key=$FUND_WALLET_PRIVATE_KEY \
          --l1-rpc-url=$ETH_RPC_URL \
          --workdir=$WORK_DIR
    else
      echo "Intent already applied"
    fi

    NEW_CHAIN_ID=$(cat $NEW_CHAIN_ID_FILE)

    if [ ! -f $GENESIS_FILE ]; then
      ${op-deployer} inspect genesis \
        --workdir $WORK_DIR $NEW_CHAIN_ID \
        > $GENESIS_FILE
    fi

    if [ ! -f $ROLLUP_FILE ]; then
      ${op-deployer} inspect rollup \
        --workdir $WORK_DIR $NEW_CHAIN_ID \
        > $ROLLUP_FILE
    fi

    if [ ! -f $L1_ADDRESSES_FILE ]; then
      ${op-deployer} inspect l1 \
        --workdir $WORK_DIR $NEW_CHAIN_ID \
        > $L1_ADDRESSES_FILE
    fi
  ''
