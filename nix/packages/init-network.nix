{
  pkgs,
  lib,
  ...
} @ args: let
  petname = lib.getExe pkgs.rust-petname;
  cast = lib.getExe' pkgs.foundry-bin "cast";
  op-deployer = lib.getExe args.op-deployer;
  dasel = lib.getExe pkgs.dasel;
  jq = lib.getExe pkgs.jq;
  select-network = lib.getExe args.select-network;
in
  pkgs.writeShellScriptBin "init-network" ''
      set -euo pipefail

      [[ -z "$SOPS_AGE_KEY" ]] && echo "Error: SOPS_AGE_KEY environment variable not set" && exit 1

      DEPLOYMENTS_DIR="$PRJ_ROOT/deployments"
      CHAIN_IDS_FILE="$DEPLOYMENTS_DIR/chain-ids.json"

      # Seed chain-ids.json if missing
      if [ ! -f "$CHAIN_IDS_FILE" ]; then
        echo "Initializing $CHAIN_IDS_FILE with L1 networks..."
        mkdir -p "$DEPLOYMENTS_DIR"
        cat > "$CHAIN_IDS_FILE" <<EOF
    {
      "mainnet": { "id": 1 },
      "sepolia": { "id": 11155111 },
      "holesky": { "id": 17000 }
    }
    EOF
      fi

      NETWORK=$(${select-network} --skip-l3 --show-full-path)
      DEPLOYMENT_LAYER="";
      L1_NAME="";
      L2_NAME=""
      CHAIN_ID=""

      if [[ "$NETWORK" == */* ]]; then
        L1_NAME="''${NETWORK%%/*}"
        L2_NAME="''${NETWORK#*/}"
        DEPLOYMENT_LAYER="L3"
        CHAIN_ID=$(jq -r --arg l1 $L1_NAME --arg l2 $L2_NAME '.[$l1][$l2].id' $CHAIN_IDS_FILE)
        echo "Initialising a new $DEPLOYMENT_LAYER rollup on $L2_NAME"
      else
        L1_NAME="$NETWORK"
        DEPLOYMENT_LAYER="L2"
        CHAIN_ID=$(jq -r --arg l1 $L1_NAME '.[$l1].id' $CHAIN_IDS_FILE)
        echo "Initialising a new $DEPLOYMENT_LAYER rollup on $L1_NAME"
      fi

      if [ -z "$CHAIN_ID" ] || [ "$CHAIN_ID" == null ]; then
        echo "❌ Chain ID $CHAIN_ID not recognized."; exit 1
      fi

      # Deployment name
      if [ $# -eq 0 ]; then
        wc=$([[ "$DEPLOYMENT_LAYER" == "L2" ]] && echo 2 || echo 3)
        DEPLOYMENT_NAME=$(${petname} -w $wc -s _ -a -c large)
        echo "Generated name: $DEPLOYMENT_NAME"
      else
        DEPLOYMENT_NAME="$1"; echo "Using name: $DEPLOYMENT_NAME"
      fi

      # Compute new chainID & timestamp
      NEW_CHAIN_ID=$((16#$(${cast} keccak "$DEPLOYMENT_NAME" | cut -c$([ "$DEPLOYMENT_LAYER" == "L2" ] && echo "3-7" || echo "3-9"))))
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

      # Prepare chain-ids.json update in TMP
      TMP_CHAIN=$(mktemp)
      cp "$CHAIN_IDS_FILE" "$TMP_CHAIN"
      if [[ "$DEPLOYMENT_LAYER" == "L2" ]]; then
        ${jq} --arg p "$L1_NAME" --arg n "$DEPLOYMENT_NAME" --arg id "$NEW_CHAIN_ID" --arg ts "$TIMESTAMP" \
          '.[$p][$n] = {id:($id|tonumber),created_at:$ts}' "$CHAIN_IDS_FILE" > "$TMP_CHAIN"
      else
        ${jq} --arg p "$L1_NAME" --arg l2 "$L2_NAME" --arg n "$DEPLOYMENT_NAME" --arg id "$NEW_CHAIN_ID" --arg ts "$TIMESTAMP" \
          '.[$p][$l2][$n] = {id:($id|tonumber),created_at:$ts}' "$CHAIN_IDS_FILE" > "$TMP_CHAIN"
      fi
      echo; echo "Proposed changes to $CHAIN_IDS_FILE:"; diff --color -u "$CHAIN_IDS_FILE" "$TMP_CHAIN" || true
      read -p "Apply these updates and proceed? (y/n): " confirm
      if [[ "$confirm" != [yY]* ]]; then
        echo "Aborting. No changes made."; exit 0
      fi
      mv "$TMP_CHAIN" "$CHAIN_IDS_FILE"

      # Determine L1/L2 IDs for op-deployer
      if [[ "$DEPLOYMENT_LAYER" == "L2" ]]; then
        L1_ID="$CHAIN_ID"; L2_ID="$NEW_CHAIN_ID"
      else
        L1_ID=$(${jq} -r --arg p "$L1_NAME" --arg l2 "$L2_NAME" '.[$p][$l2].id' "$CHAIN_IDS_FILE")
        L2_ID="$NEW_CHAIN_ID"
      fi

      # Final target directory and init
      if [[ "$DEPLOYMENT_LAYER" == "L2" ]]; then
        TARGET_DIR="$DEPLOYMENTS_DIR/$L1_NAME/$DEPLOYMENT_NAME"
      else
        TARGET_DIR="$DEPLOYMENTS_DIR/$L1_NAME/$L2_NAME/$DEPLOYMENT_NAME"
      fi
      mkdir -p "$TARGET_DIR"
      echo "Initializing op-deployer in $TARGET_DIR..."
      ${op-deployer} init \
        --l1-chain-id "$L1_ID" \
        --l2-chain-ids "$L2_ID" \
        --workdir "$TARGET_DIR" \
        --intent-config-type custom

      KEYS_JSON=$(${cast} wallet new --json -n 7)

      # Extract addresses and private keys for each role
      ADMIN_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[0].address')
      SEQUENCER_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[1].address')
      BATCHER_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[2].address')
      PROPOSER_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[3].address')
      CHALLENGER_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[4].address')
      GUARDIAN_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[5].address')
      FEE_RECIPIENT_ADDR=$(echo "$KEYS_JSON" | ${jq} -r '.[6].address')

      ADMIN_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[0].private_key')
      SEQUENCER_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[1].private_key')
      BATCHER_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[2].private_key')
      PROPOSER_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[3].private_key')
      CHALLENGER_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[4].private_key')
      GUARDIAN_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[5].private_key')
      FEE_RECIPIENT_PRIV=$(echo "$KEYS_JSON" | ${jq} -r '.[6].private_key')

      # Write plain user-addresses.json
      cat > "$TARGET_DIR/user-addresses.json" <<EOF
    {
      "admin": "$ADMIN_ADDR",
      "sequencer": "$SEQUENCER_ADDR",
      "batcher": "$BATCHER_ADDR",
      "proposer": "$PROPOSER_ADDR",
      "challenger": "$CHALLENGER_ADDR",
      "guardian": "$GUARDIAN_ADDR",
      "fee_recipient": "$FEE_RECIPIENT_ADDR"
    }
    EOF

    cat > "$TARGET_DIR/user-private-keys.json" <<EOF
    {
      "admin": "$ADMIN_PRIV",
      "sequencer": "$SEQUENCER_PRIV",
      "batcher": "$BATCHER_PRIV",
      "proposer": "$PROPOSER_PRIV",
      "challeneger": "$CHALLENGER_PRIV",
      "guardian": "$GUARDIAN_PRIV",
      "fee_recipient": "$FEE_RECIPIENT_PRIV"
    }
    EOF
      # Encrypt the file in-place
      sops --config "$PRJ_ROOT/sops/config.yaml" --encrypt --in-place "$TARGET_DIR/user-private-keys.json"

      INTENT_FILE="$TARGET_DIR/intent.toml"
      echo "Modifying $INTENT_FILE settings..."
      ${dasel} put -f "$INTENT_FILE" -r toml -t int "chains.[0].eip1559DenominatorCanyon" -v 250
      ${dasel} put -f "$INTENT_FILE" -r toml -t int "chains.[0].eip1559Denominator" -v 50
      ${dasel} put -f "$INTENT_FILE" -r toml -t int "chains.[0].eip1559Elasticity" -v 6

      echo "Setting superchain roles"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "superchainRoles.proxyAdminOwner" -v "$ADMIN_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "superchainRoles.protocolVersionsOwner" -v "$ADMIN_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "superchainRoles.guardian" -v "$GUARDIAN_ADDR"

      echo "Setting vault, L1 fee and sequencer fee vault address recipient"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].baseFeeVaultRecipient" -v "$FEE_RECIPIENT_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].l1FeeVaultRecipient" -v "$FEE_RECIPIENT_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].sequencerFeeVaultRecipient" -v "$FEE_RECIPIENT_ADDR"

      echo "Setting proxy owners"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.l1ProxyAdminOwner" -v "$ADMIN_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.l2ProxyAdminOwner" -v "$ADMIN_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.systemConfigOwner" -v "$ADMIN_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.unsafeBlockSigner" -v "$SEQUENCER_ADDR"

      echo "Setting batcher, challenger, sequencer and proposer addresses"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.batcher" -v "$BATCHER_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.challenger" -v "$CHALLENGER_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.sequencer" -v "$SEQUENCER_ADDR"
      ${dasel} put -f "$INTENT_FILE" -r toml -t string "chains.[0].roles.proposer" -v "$PROPOSER_ADDR"

      echo "✅ Deployment complete — artifacts in $TARGET_DIR"
  ''
