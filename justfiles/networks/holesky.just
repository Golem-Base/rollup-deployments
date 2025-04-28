# Holesky network configuration and recipes
import "../modules/config.just"
import "../modules/deployment.just"
import "../modules/utils.just"
import "../modules/validation.just"

# Set network-specific configuration
export NETWORK := "holesky"
export L1_CHAIN_ID := "17000"
export L2_CHAIN_ID := "393530"
export WORK_DIR := "./" + NETWORK

# Load required environment variables with validation
GS_ADMIN_ADDRESS := env("GS_ADMIN_ADDRESS")
GS_ADMIN_PRIVATE_KEY := env("GS_ADMIN_PRIVATE_KEY")
GS_BATCHER_ADDRESS := env("GS_BATCHER_ADDRESS")
GS_CHALLENGER_ADDRESS := env("GS_CHALLENGER_ADDRESS")
GS_PROPOSER_ADDRESS := env("GS_PROPOSER_ADDRESS")
GS_SEQUENCER_ADDRESS := env("GS_SEQUENCER_ADDRESS")
L1_RPC_URL := env("L1_RPC_URL")
L2_RPC_URL := env("L2_RPC_URL")

# Show current configuration
config:
    @echo "Current configuration:"
    @echo "  Network:              {{NETWORK}}"
    @echo "  L1 Chain ID:          {{L1_CHAIN_ID}}"
    @echo "  L2 Chain ID:          {{L2_CHAIN_ID}}"
    @echo "  L1 RPC URL:           {{L1_RPC_URL}}"
    @echo "  Work Directory:       {{WORK_DIR}}"

# Network-specific deployment wrapper
deploy: modules::deployment::prepare modules::deployment::execute
    @echo "{{NETWORK}} successfully deployed!"

# Initialize deployment configuration
init: modules::deployment::init
    @echo "{{NETWORK}} initialization complete"
