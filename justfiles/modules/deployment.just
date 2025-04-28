# Deployment recipes and logic
import "config.just"

# Prepare deployment (initialize and bootstrap)
prepare: init bootstrap_superchain bootstrap_implementations bootstrap_proxy

# Execute deployment
execute: apply
    @echo "Deployment executed successfully!"

# Initialize deployment configuration
init: config::create_work_dir
    op-deployer init \
        --l1-chain-id {{L1_CHAIN_ID}} \
        --l2-chain-ids {{L2_CHAIN_ID}} \
        --workdir {{WORK_DIR}} \
        --intent-config-type custom

    # Set chain parameters (with these constants)
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t int "chains.[0].eip1559DenominatorCanyon" -v 250
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t int "chains.[0].eip1559Denominator" -v 50
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t int "chains.[0].eip1559Elasticity" -v 6

    # Set contract locators
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t string -v "{{L1_ARTIFACTS_LOCATOR}}" "l1ContractsLocator"
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t string -v "{{L2_ARTIFACTS_LOCATOR}}" "l2ContractsLocator"

# Bootstrap superchain configuration
[no-exit-message]
bootstrap_superchain:
    op-deployer bootstrap superchain \
        --private-key {{GS_ADMIN_PRIVATE_KEY}} \
        --l1-rpc-url {{L1_RPC_URL}} \
        --artifacts-locator {{L1_ARTIFACTS_LOCATOR}} \
        --guardian {{GS_ADMIN_ADDRESS}} \
        --recommended-protocol-version {{PROTOCOL_VERSION}} \
        --required-protocol-version {{PROTOCOL_VERSION}} \
        --superchain-proxy-admin-owner {{GS_ADMIN_ADDRESS}} \
        --protocol-versions-owner {{GS_ADMIN_ADDRESS}} \
        --outfile {{WORK_DIR}}/superchain.json

    # Set all roles
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t string "superchainRoles.proxyAdminOwner" -v "{{GS_ADMIN_ADDRESS}}"
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t string "superchainRoles.protocolVersionsOwner" -v "{{GS_ADMIN_ADDRESS}}"
    dasel put -f {{WORK_DIR}}/intent.toml -r toml -t string "superchainRoles.guardian" -v "{{GS_ADMIN_ADDRESS}}"

    # Additional settings omitted for brevity - see original file for full list

# Bootstrap implementations
[no-exit-message]
@bootstrap_implementations:
    op-deployer bootstrap implementations \
        --superchain-config-proxy "$(jq -r .SuperchainConfigProxy {{WORK_DIR}}/superchain.json)" \
        --protocol-versions-proxy "$(jq -r .ProtocolVersionsProxy {{WORK_DIR}}/superchain.json)" \
        --private-key {{GS_ADMIN_PRIVATE_KEY}} \
        --l1-rpc-url {{L1_RPC_URL}} \
        --artifacts-locator {{L1_ARTIFACTS_LOCATOR}} \
        --l1-contracts-release {{L1_CONTRACTS_RELEASE}} \
        --upgrade-controller {{GS_ADMIN_ADDRESS}} \
        --gb-superchain-proxy-admin "$(jq -r .SuperchainProxyAdmin {{WORK_DIR}}/superchain.json)" \
        --outfile {{WORK_DIR}}/implementations.json

# Bootstrap proxy configuration
[no-exit-message]
bootstrap_proxy:
    op-deployer bootstrap proxy \
        --private-key {{GS_ADMIN_PRIVATE_KEY}} \
        --l1-rpc-url {{L1_RPC_URL}} \
        --artifacts-locator {{L1_ARTIFACTS_LOCATOR}} \
        --proxy-owner {{GS_ADMIN_ADDRESS}} \
        --outfile {{WORK_DIR}}/proxy.json

# Apply all configurations
[no-exit-message]
apply:
    op-deployer apply \
        --private-key {{GS_ADMIN_PRIVATE_KEY}} \
        --l1-rpc-url {{L1_RPC_URL}} \
        --workdir {{WORK_DIR}}
