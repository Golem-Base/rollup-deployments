# Configuration and constants
network := ""

# Chain IDs based on network
L1_CHAIN_ID := if network == "holesky" {
  "17000"
} else if network == "sepolia" {
  "11155111"
} else if network == "holesky-l3" {
  "393530"
} else if network == "altai" {
  "393530"
} else if network == "sepolia-l3" {
  "393531"
} else if network == "laika" {
  "393530"
} else if network == "aurora" {
  "17000"
} else if network == "blackhole" {
  "393530"
} else if network == "nova" {
  "393530"
} else if network == "kaolin" {
  "393530"
} else {
  error("Invalid network")
}

L2_CHAIN_ID := if network == "holesky" {
  "393530"
} else if network == "sepolia" {
  "393531"
} else if network == "holesky-l3" {
  "934720"
} else if network == "laika" {
  "934730"
} else if network == "sepolia-l3" {
  "6296375"
} else if network == "aurora" {
  "400000"
} else if network == "blackhole" {
  "500002"
} else if network == "nova" {
  "550001"
} else if network == "kaolin" {
  "600106"
} else if network == "altai" {
  "500002"
} else {
  error("Invalid network")
}

# Deployment constants
L1_CONTRACTS_RELEASE := "op-contracts/v2.0.0-rc.1"

# NOTE: The artifacts checksum is computed using the following script:
# The artifact is calculated on the gb/op-contracts/v2.0.0-rc.1 branch.
# URL: https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/scripts/ops/calculate-checksum.sh
# Using a tag brings in all kinds of side effects (cf. https://github.com/ethereum-optimism/optimism/tree/e1516f01b379868f50fd3610a89daf0a560277f4/gb-deployer/pkg/deployer/pipeline/init.go#L41), so we stick to an artifact.
L1_CHECKSUM := "1e788c684d48232a85cf5f5bd3876e83d6d2240c80588f60e160faca0133eac8"

L1_ARTIFACTS_LOCATOR := "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-" + L1_CHECKSUM + ".tar.gz"
L2_ARTIFACTS_LOCATOR := "tag://op-contracts/v1.7.0-beta.1+l2-contracts"

# NOTE: Cf. https://specs.optimism.io/protocol/superchain-upgrades.html#op-stack-protocol-versions
PROTOCOL_VERSION := "0x0000000000000000000000000000000000000009000000000000000000000000"

# Load required environment variables with validation
GS_ADMIN_ADDRESS := env("GS_ADMIN_ADDRESS")
GS_ADMIN_PRIVATE_KEY := env("GS_ADMIN_PRIVATE_KEY")
GS_BATCHER_ADDRESS := env("GS_BATCHER_ADDRESS")
GS_CHALLENGER_ADDRESS := env("GS_CHALLENGER_ADDRESS")
GS_PROPOSER_ADDRESS := env("GS_PROPOSER_ADDRESS")
GS_SEQUENCER_ADDRESS := env("GS_SEQUENCER_ADDRESS")

L1_RPC_URL := if network == "sepolia" {
  env("L1_RPC_URL")
} else if network == "holesky" {
  env("L1_RPC_URL")
} else if network == "holesky-l3" {
  env("L2_RPC_URL")
} else if network == "sepolia-l3" {
  env("L2_RPC_URL")
} else if network == "laika" {
  env("L2_RPC_URL")
} else if network == "aurora" {
  env("L1_RPC_URL")
} else if network == "blackhole" {
  env("L2_RPC_URL")
} else if network == "nova" {
  env("L2_RPC_URL")
} else if network == "kaolin" {
  env("L2_RPC_URL")
} else if network == "altai" {
  env("L2_RPC_URL")
} else {
  error("Invalid network")
}

L2_RPC_URL := if network == "sepolia" {
  env("L2_RPC_URL")
} else if network == "holesky" {
  env("L2_RPC_URL")
} else if network == "holesky-l3" {
  env("L3_RPC_URL")
} else if network == "sepolia-l3" {
  env("L3_RPC_URL")
} else if network == "laika" {
  env("L3_RPC_URL")
} else if network == "aurora" {
  env("L2_RPC_URL")
} else if network == "blackhole" {
  env("L3_RPC_URL")
} else if network == "nova" {
  env("L3_RPC_URL")
} else if network == "kaolin" {
  env("L3_RPC_URL")
} else if network == "altai" {
  env("L3_RPC_URL")
} else { error("Invalid network") }

# Default recipe shows available commands
[private]
default:
    @just --list

# Show current configuration
[no-exit-message]
config:
    @echo "Current configuration:"
    @echo "  Network:              {{ network }}"
    @echo "  L1 Chain ID:          {{ L1_CHAIN_ID }}"
    @echo "  L2 Chain IDs:         {{ L2_CHAIN_ID }}"
    @echo "  L1 Contracts Release: {{ L1_CONTRACTS_RELEASE }}"
    @echo "  L1 RPC URL:           {{ L1_RPC_URL }}"
    @echo "  Work Directory:       ./deploy/{{ network }}"

# List available networks
list-networks:
    @echo "Available networks:"
    @echo "  - holesky  (L1: 17000)"
    @echo "  - sepolia  (L1: 11155111)"
    @echo "L2 chain network ids: {{ L2_CHAIN_ID }}"

# Clean deployment directory for current network
[confirm("Are you sure you want to delete the deployment directory?")]
[no-exit-message]
clean:
    @if [ -d "./deploy/{{ network }}" ]; then \
        echo "Removing directory: ./deploy/{{ network }}"; \
        rm -rf "./deploy/{{ network }}"; \
    else \
        echo "Directory does not exist: ./deploy/{{ network }}"; \
    fi

_create_workdir:
    mkdir -p ./deploy/{{ network }}

# Initialize deployment configuration
init: _create_workdir
    gb-deployer init \
        --l1-chain-id {{ L1_CHAIN_ID }} \
        --l2-chain-ids {{ L2_CHAIN_ID }} \
        --workdir ./deploy/{{ network }} \
        --intent-config-type custom

    # Set chain constants
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t int "chains.[0].eip1559DenominatorCanyon" -v 250
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t int "chains.[0].eip1559Denominator" -v 50
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t int "chains.[0].eip1559Elasticity" -v 6

    # Set contract locators
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string -v "{{ L1_ARTIFACTS_LOCATOR }}" "l1ContractsLocator"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string -v "{{ L2_ARTIFACTS_LOCATOR }}" "l2ContractsLocator"

# Bootstrap superchain configuration
[no-exit-message]
bootstrap-superchain:
    gb-deployer bootstrap superchain \
        --private-key {{ GS_ADMIN_PRIVATE_KEY }} \
        --l1-rpc-url {{ L1_RPC_URL }} \
        --artifacts-locator {{ L1_ARTIFACTS_LOCATOR }} \
        --guardian {{ GS_ADMIN_ADDRESS }} \
        --recommended-protocol-version {{ PROTOCOL_VERSION }} \
        --required-protocol-version {{ PROTOCOL_VERSION }} \
        --superchain-proxy-admin-owner {{ GS_ADMIN_ADDRESS }} \
        --protocol-versions-owner {{ GS_ADMIN_ADDRESS }} \
        --outfile ./deploy/{{ network }}/superchain.json

    # Set all roles
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "superchainRoles.proxyAdminOwner" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "superchainRoles.protocolVersionsOwner" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "superchainRoles.guardian" -v "{{ GS_ADMIN_ADDRESS }}"

    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].baseFeeVaultRecipient" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].l1FeeVaultRecipient" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].sequencerFeeVaultRecipient" -v "{{ GS_ADMIN_ADDRESS }}"

    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.l1ProxyAdminOwner" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.l2ProxyAdminOwner" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.systemConfigOwner" -v "{{ GS_ADMIN_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.unsafeBlockSigner" -v "{{ GS_ADMIN_ADDRESS }}"

    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.batcher" -v "{{ GS_BATCHER_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.challenger" -v "{{ GS_CHALLENGER_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.sequencer" -v "{{ GS_SEQUENCER_ADDRESS }}"
    dasel put -f ./deploy/{{ network }}/intent.toml -r toml -t string "chains.[0].roles.proposer" -v "{{ GS_PROPOSER_ADDRESS }}"

# Bootstrap implementations
[no-exit-message]
@bootstrap-implementations:
    # NOTE: these addresses end up in the OPCM
    gb-deployer bootstrap implementations \
        --superchain-config-proxy "$(jq -r .SuperchainConfigProxy ./deploy/{{ network }}/superchain.json)" \
        --protocol-versions-proxy "$(jq -r .ProtocolVersionsProxy ./deploy/{{ network }}/superchain.json)" \
        --private-key {{ GS_ADMIN_PRIVATE_KEY }} \
        --l1-rpc-url {{ L1_RPC_URL }} \
        --artifacts-locator {{ L1_ARTIFACTS_LOCATOR }} \
        --l1-contracts-release {{ L1_CONTRACTS_RELEASE }} \
        --upgrade-controller {{ GS_ADMIN_ADDRESS }} \
        --gb-superchain-proxy-admin "$(jq -r .SuperchainProxyAdmin ./deploy/{{ network }}/superchain.json)" \
        --outfile ./deploy/{{ network }}/implementations.json

# Bootstrap proxy configuration
[no-exit-message]
bootstrap-proxy:
    gb-deployer bootstrap proxy \
        --private-key {{ GS_ADMIN_PRIVATE_KEY }} \
        --l1-rpc-url {{ L1_RPC_URL }} \
        --artifacts-locator {{ L1_ARTIFACTS_LOCATOR }} \
        --proxy-owner {{ GS_ADMIN_ADDRESS }} \
        --outfile ./deploy/{{ network }}/proxy.json

# Apply all configurations
[no-exit-message]
apply:
    gb-deployer apply \
        --private-key {{ GS_ADMIN_PRIVATE_KEY }} \
        --l1-rpc-url {{ L1_RPC_URL }} \
        --workdir ./deploy/{{ network }}

# Run complete deployment sequence
deploy: bootstrap-superchain bootstrap-implementations bootstrap-proxy apply
    echo Deployed!

# These steps should not be performed on each deploy, as they create the initial state.
# NOTE: Changes to these two files should usually be deployed in sync, because rollup.json depends on values in genesis.json.
# If you run this with an existing L2 chain running in a node, you probably want to delete op-geth's state directory, so that op-geth-init is run again. Otherwise op-node might refuse to start.
create-genesis:
   gb-deployer inspect genesis \
        --workdir ./deploy/{{ network }}/ {{ L2_CHAIN_ID }} \
        > ./deploy/{{ network }}/genesis.json

   gb-deployer inspect rollup \
        --workdir ./deploy/{{ network }}/ {{ L2_CHAIN_ID }} \
        > ./deploy/{{ network }}/rollup.json

upload-jsons: create-genesis
  mc put ./deploy/{{ network }}/genesis.json gb/golem-base/{{ network }}/genesis.json
  mc put ./deploy/{{ network }}/rollup.json gb/golem-base/{{ network }}/rollup.json
  mc put ./deploy/{{ network }}/state.json gb/golem-base/{{ network }}/state.json

# for how to generate the absolute prestate, see op-program's README.
validate:
  op-validator validate v2.0.0 \
    --l1-rpc-url {{ L1_RPC_URL }} \
    --l2-chain-id {{ L2_CHAIN_ID }} \
    --proxy-admin $(gb-deployer inspect l1  --workdir ./deploy/{{ network }}/ {{ L2_CHAIN_ID }} | jq -r .opChainDeployment.proxyAdminAddress) \
    --absolute-prestate 0x03b357b30095022ecbb44ef00d1de19df39cf69ee92a60683a6be2c6f8fe6a3e \
    --system-config $(gb-deployer inspect l1  --workdir ./deploy/{{ network }}/ {{ L2_CHAIN_ID }} | jq -r .opChainDeployment.systemConfigProxyAddress)

# move some ETH from L admin to L proposer and batcher
fund value:
  #!/usr/bin/env bash
  set -euo pipefail
  set -x

  for var in GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
    address="${!var}"

    cast send \
      --quiet \
      --rpc-url {{ L1_RPC_URL }} \
      --private-key {{ GS_ADMIN_PRIVATE_KEY }} \
      --value {{ value }} \
      $address

    echo "New balance ($var): $(cast balance $recipient --ether --rpc-url {{ L1_RPC_URL }})"
  done


# TODO: should error if balance doesn't update by correct amount
# deposit funds from L to L+1 accounts of admin (for withdrawal testing), batcher, proposer
bridge value:
  #!/usr/bin/env bash
  set -euo pipefail
  set -x

  for var in GS_ADMIN_ADDRESS GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
    address="${!var}"

    cast send \
      --quiet \
      --gas-limit 2000000 \
      --rpc-url {{ L1_RPC_URL }} \
      --private-key {{ GS_ADMIN_PRIVATE_KEY }} \
      --value {{ value }} \
      $(gb-deployer inspect l1  --workdir ./deploy/{{ network }} {{ L2_CHAIN_ID }} | jq -r .opChainDeployment.l1StandardBridgeProxyAddress) \
      "bridgeETHTo(address _to, uint32 _minGasLimit, bytes calldata _extraData)" \
        $address \
        1000000 \
        $(cast to-bytes32 "")
  done

balances:
  #!/usr/bin/env bash
  set -euo pipefail

  echo "### L"
  for var in GS_ADMIN_ADDRESS GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
    address="${!var}"

    echo "$var: $(cast balance $address --ether --rpc-url {{ L1_RPC_URL }})"
  done

  echo
  echo "### L+1"
  for var in GS_ADMIN_ADDRESS GS_BATCHER_ADDRESS GS_PROPOSER_ADDRESS; do
    address="${!var}"

    echo "$var: $(cast balance $address --ether --rpc-url {{ L2_RPC_URL }})"
  done
