# Shared configuration settings and constants

# Deployment constants
L1_CONTRACTS_RELEASE := "op-contracts/v2.0.0-rc.1"
L1_CHECKSUM := "1e788c684d48232a85cf5f5bd3876e83d6d2240c80588f60e160faca0133eac8"
L1_ARTIFACTS_LOCATOR := "https://storage.googleapis.com/oplabs-contract-artifacts/artifacts-v1-" + L1_CHECKSUM + ".tar.gz"
L2_ARTIFACTS_LOCATOR := "tag://op-contracts/v1.7.0-beta.1+l2-contracts"
PROTOCOL_VERSION := "0x0000000000000000000000000000000000000009000000000000000000000000"

# Create working directory for current network
create_work_dir:
    mkdir -p {{WORK_DIR}}
