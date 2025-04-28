

# Generate Optimism environment configuration
gen-optimism-envrc:
    #!/usr/bin/env bash
    set -euo pipefail

    # Generate wallets using cast
    wallets=()
    for i in {1..5}; do
        wallets+=("$(cast wallet new)")
    done

    # Extract addresses and keys
    {
        echo "# Configuration for Optimism on {{NETWORK}}"
        echo
        echo "# Admin account"
        echo "export GS_ADMIN_ADDRESS=$(echo "${wallets[0]}" | awk '/Address/ { print $2 }')"
        echo "export GS_ADMIN_PRIVATE_KEY=$(echo "${wallets[0]}" | awk '/Private key/ { print $3 }')"
        echo
        echo "# Batcher account"
        echo "export GS_BATCHER_ADDRESS=$(echo "${wallets[1]}" | awk '/Address/ { print $2 }')"
        echo "export GS_BATCHER_PRIVATE_KEY=$(echo "${wallets[1]}" | awk '/Private key/ { print $3 }')"
        echo
        echo "# Proposer account"
        echo "export GS_PROPOSER_ADDRESS=$(echo "${wallets[2]}" | awk '/Address/ { print $2 }')"
        echo "export GS_PROPOSER_PRIVATE_KEY=$(echo "${wallets[2]}" | awk '/Private key/ { print $3 }')"
        echo
        echo "# Sequencer account"
        echo "export GS_SEQUENCER_ADDRESS=$(echo "${wallets[3]}" | awk '/Address/ { print $2 }')"
        echo
        echo "# Challenger account"
        echo "export GS_CHALLENGER_ADDRESS=$(echo "${wallets[4]}" | awk '/Address/ { print $2 }')"
        echo "export GS_CHALLENGER_PRIVATE_KEY=$(echo "${wallets[4]}" | awk '/Private key/ { print $3 }')"
        echo
        echo "# RPC configuration"
        echo "export RPC_URL="
        echo "export L1_RPC_KIND="
    } > .envrc.optimism-{{NETWORK}}
    echo ".envrc.optimism-{{NETWORK}} file has been created"

# Clean deployment directory for current network
[confirm("Are you sure you want to delete the deployment directory?")]
[no-exit-message]
clean:
    @if [ -d "{{WORK_DIR}}" ]; then \
        echo "Removing directory: {{WORK_DIR}}"; \
        rm -rf "{{WORK_DIR}}"; \
    else \
        echo "Directory does not exist: {{WORK_DIR}}"; \
    fi

# Fund accounts - move ETH from admin to proposer and batcher
fund value:
    #!/usr/bin/env bash
    set -euo pipefail
    set -x

    for var in GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
        address="${!var}"

        cast send \
            --quiet \
            --rpc-url {{L1_RPC_URL}} \
            --private-key {{GS_ADMIN_PRIVATE_KEY}} \
            --value {{value}} \
            $address

        echo "New balance ($var): $(cast balance $address --ether --rpc-url {{L1_RPC_URL}})"
    done

# Bridge funds from L1 to L2
bridge value:
    #!/usr/bin/env bash
    set -euo pipefail
    set -x

    for var in GS_ADMIN_ADDRESS GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
        address="${!var}"

        cast send \
            --quiet \
            --gas-limit 2000000 \
            --rpc-url {{L1_RPC_URL}} \
            --private-key {{GS_ADMIN_PRIVATE_KEY}} \
            --value {{value}} \
            $(op-deployer inspect l1 --workdir {{WORK_DIR}} {{L2_CHAIN_ID}} | jq -r .opChainDeployment.l1StandardBridgeProxyAddress) \
            "bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData)" \
            $address \
            1000000 \
            $(cast to-bytes32 "")
    done

# Display balances for admin, batcher, and proposer on L1 and L2
balances:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "### L1"
    for var in GS_ADMIN_ADDRESS GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
        address="${!var}"
        echo "$var: $(cast balance $address --ether --rpc-url {{L1_RPC_URL}})"
    done

    echo
    echo "### L2"
    for var in GS_ADMIN_ADDRESS GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
        address="${!var}"
        echo "$var: $(cast balance $address --ether --rpc-url {{L2_RPC_URL}})"
    done
