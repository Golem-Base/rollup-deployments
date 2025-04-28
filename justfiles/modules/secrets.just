# Variables
DOPPLER_PROJECT := "golem-base"
DOPPLER_CONFIG := "prd"

# Helper function to generate and save keys
_gen-key key_type secret_name:
    #!/usr/bin/env bash
    set -euo pipefail

    TEMP_DIR=$(mktemp -d -t l3-keys.XXXXXXXXXX)
    cd "$TEMP_DIR"

    echo "Generating {{key_type}} private key..."
    op-node p2p genkey > {{key_type}}-key.txt

    KEY=$(cat {{key_type}}-key.txt)

    echo "Setting key in Doppler..."
    doppler secrets set "{{secret_name}}=$KEY" --project {{DOPPLER_PROJECT}} --config {{DOPPLER_CONFIG}}

    echo "Cleaning up..."
    rm -rf "$TEMP_DIR"

    echo "{{key_type}} key generated and saved successfully!"

# Generate bootnode consensus and execution keys
gen-bootnode-key number:
    #!/usr/bin/env bash
    set -euo pipefail

    TEMP_DIR=$(mktemp -d -t l3-keys.XXXXXXXXXX)
    cd "$TEMP_DIR"

    echo "Generating consensus private key using op-node..."
    op-node p2p genkey > consensus-private-key.txt

    echo "Generating execution private key..."
    op-node p2p genkey > execution-private-key.txt

    CONSENSUS_KEY=$(cat consensus-private-key.txt)
    EXECUTION_KEY=$(cat execution-private-key.txt)

    echo "Setting keys in Doppler..."
    doppler secrets set "HOLESKY_L3_PUBLIC_BOOTNODE_{{number}}_CONSENSUS_P2P_PRIVATE_KEY=$CONSENSUS_KEY" --project {{DOPPLER_PROJECT}} --config {{DOPPLER_CONFIG}}
    doppler secrets set "HOLESKY_L3_PUBLIC_BOOTNODE_{{number}}_EXECUTION_P2P_PRIVATE_KEY=$EXECUTION_KEY" --project {{DOPPLER_PROJECT}} --config {{DOPPLER_CONFIG}}

    echo "Cleaning up..."
    rm -rf "$TEMP_DIR"

    echo "Bootnode {{number}} keys generated and saved successfully!"

# Generate keys for all 3 bootnodes
gen-bootnode-keys:
    @just gen-bootnode-key 1
    @just gen-bootnode-key 2
    @just gen-bootnode-key 3

# Generate and save sequencer key
gen-sequencer-key:
    @just _gen-key "sequencer" "HOLESKY_L3_SEQUENCER_PRIVATE_KEY"

# Generate and save proposer key
gen-proposer-key:
    @just _gen-key "proposer" "HOLESKY_L3_PROPOSER_PRIVATE_KEY"

# Generate and save batcher key
gen-batcher-key:
    @just _gen-key "batcher" "HOLESKY_L3_BATCHER_PRIVATE_KEY"

# Generate JWT secret for L3
gen-jwt-secret:
    #!/usr/bin/env bash
    set -euo pipefail

    TEMP_DIR=$(mktemp -d -t l3-keys.XXXXXXXXXX)
    cd "$TEMP_DIR"

    echo "Generating JWT secret..."
    openssl rand -hex 32 | tr -d "\n" > jwt-secret.txt

    JWT=$(cat jwt-secret.txt)

    echo "Setting JWT secret in Doppler..."
    doppler secrets set "HOLESKY_L3_JWT_SECRET=$JWT" --project {{DOPPLER_PROJECT}} --config {{DOPPLER_CONFIG}}

    echo "Cleaning up..."
    rm -rf "$TEMP_DIR"

    echo "JWT secret generated and saved successfully!"

# Generate all keys needed for L3 deployment
gen-all-keys:
    just gen-bootnode-keys
    just gen-sequencer-key
    just gen-proposer-key
    just gen-batcher-key
    just gen-jwt-secret
    echo "All keys generated and saved successfully!"
