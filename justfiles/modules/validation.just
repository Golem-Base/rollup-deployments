# Validation and genesis creation recipes

# Create genesis and rollup files
create_genesis:
    op-deployer inspect genesis \
        --workdir {{WORK_DIR}} {{L2_CHAIN_ID}} \
        > {{WORK_DIR}}/genesis.json

    op-deployer inspect rollup \
        --workdir {{WORK_DIR}} {{L2_CHAIN_ID}} \
        > {{WORK_DIR}}/rollup.json

# Push JSON files to remote storage
push_jsons: create_genesis
    mc put {{WORK_DIR}}/genesis.json gb/golem-base/{{NETWORK}}-l2/genesis.json
    mc put {{WORK_DIR}}/rollup.json gb/golem-base/{{NETWORK}}-l2/rollup.json
    mc put {{WORK_DIR}}/state.json gb/golem-base/{{NETWORK}}-l2/state.json

# Validate the deployment
validate:
    op-validator validate v2.0.0 \
        --l1-rpc-url {{L1_RPC_URL}} \
        --l2-chain-id {{L2_CHAIN_ID}} \
        --proxy-admin $(op-deployer inspect l1 --workdir {{WORK_DIR}} {{L2_CHAIN_ID}} | jq -r .opChainDeployment.proxyAdminAddress) \
        --absolute-prestate 0x03b357b30095022ecbb44ef00d1de19df39cf69ee92a60683a6be2c6f8fe6a3e \
        --system-config $(op-deployer inspect l1 --workdir {{WORK_DIR}} {{L2_CHAIN_ID}} | jq -r .opChainDeployment.systemConfigProxyAddress)
