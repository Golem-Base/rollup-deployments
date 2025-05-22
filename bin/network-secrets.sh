#!/usr/bin/env bash
set -euo pipefail

# Variables
DOPPLER_PROJECT="golem-base"
DOPPLER_CONFIG="prd"

# Function to convert string to uppercase
uppercase() {
  echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Generate and upload secrets for a specific bootnode number
generate_bootnode_secrets() {
  local network="$1"
  local bootnode_number="$2"

  echo "Generating bootnode secrets for public-bootnode-${bootnode_number}..."

  # Create temporary directory for storing keys
  TMPDIR=$(mktemp -d -t bootnode-keys.XXXXXXXXXX)
  trap 'find $TMPDIR -type f -exec shred --zero --remove {} \;' EXIT

  # Generate keys
  for key_type in "consensus" "execution"; do
    echo "Generating ${key_type} p2p private key..."
    devp2p key generate "$TMPDIR/${key_type}-key"
    declare "${key_type^^}_KEY=$(cat "$TMPDIR/${key_type}-key")"
  done

  # Upload keys to Doppler
  local network_upper
  network_upper=$(uppercase "$network")
  echo "Uploading keys to Doppler..."
  doppler secrets set \
    "${network_upper}_PUBLIC_BOOTNODE_${bootnode_number}_CONSENSUS_P2P_PRIVATE_KEY=$CONSENSUS_KEY" \
    "${network_upper}_PUBLIC_BOOTNODE_${bootnode_number}_EXECUTION_P2P_PRIVATE_KEY=$EXECUTION_KEY" \
    --project $DOPPLER_PROJECT \
    --config $DOPPLER_CONFIG

  echo "Successfully generated and uploaded bootnode secrets for public-bootnode-${bootnode_number}"
}

# Generate and upload all bootnode secrets (1-4)
generate_all_bootnode_secrets() {
  local network="$1"

  generate_bootnode_secrets "$network" 1
  generate_bootnode_secrets "$network" 2
  generate_bootnode_secrets "$network" 3
  generate_bootnode_secrets "$network" 4
}

# Upload a key from an environment variable
upload_key() {
  local network="$1"
  local role="$2"

  local role_upper
  role_upper=$(uppercase "$role")
  local ENV_VAR="GS_${role_upper}_PRIVATE_KEY"

  if [ -z "${!ENV_VAR:-}" ]; then
    echo "Error: $ENV_VAR environment variable is not set"
    exit 1
  fi

  echo "Uploading ${role} key from environment variable..."
  local network_upper
  network_upper=$(uppercase "$network")
  doppler secrets set \
    "${network_upper}_${role_upper}_PRIVATE_KEY=${!ENV_VAR}" \
    --project $DOPPLER_PROJECT \
    --config $DOPPLER_CONFIG

  echo "Successfully uploaded ${role} key"
}

# Upload specific role keys
upload_proposer_key() {
  local network="$1"
  upload_key "$network" "proposer"
}

upload_batcher_key() {
  local network="$1"
  upload_key "$network" "batcher"
}

upload_sequencer_key() {
  local network="$1"
  upload_key "$network" "sequencer"
}

upload_admin_key() {
  local network="$1"
  upload_key "$network" "admin"
}

# Generate JWT secret
generate_jwt_secret() {
  local network="$1"

  echo "Generating JWT secret..."
  JWT=$(openssl rand -hex 32 | tr -d "\n")

  echo "Setting JWT secret in Doppler..."
  local network_upper
  network_upper=$(uppercase "$network")
  doppler secrets set "${network_upper}_JWT_SECRET=$JWT" \
    --project $DOPPLER_PROJECT \
    --config $DOPPLER_CONFIG

  echo "JWT secret generated and saved successfully!"
}

# Upload all account keys from environment variables
upload_all_account_keys() {
  local network="$1"

  upload_proposer_key "$network"
  upload_batcher_key "$network"
  upload_sequencer_key "$network"
  upload_admin_key "$network"
  echo "All account keys uploaded successfully!"
}

# Generate and upload all keys needed for deployment
generate_all_keys() {
  local network="$1"

  generate_all_bootnode_secrets "$network"
  upload_all_account_keys "$network"
  generate_jwt_secret "$network"
  echo "All keys generated and uploaded successfully!"
}

# Main function to process arguments
main() {
  if [ $# -lt 1 ]; then
    echo "Usage: $0 <command> [arguments...]"
    echo "Commands:"
    echo "  generate-all-bootnode-secrets <network>"
    echo "  generate-bootnode-secrets <network> <bootnode_number>"
    echo "  upload-proposer-key <network>"
    echo "  upload-batcher-key <network>"
    echo "  upload-sequencer-key <network>"
    echo "  generate-jwt-secret <network>"
    echo "  upload-all-account-keys <network>"
    echo "  generate-all-keys <network>"
    exit 1
  fi

  local command="$1"
  shift

  case "$command" in
  generate-all-bootnode-secrets)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 generate-all-bootnode-secrets <network>"
      exit 1
    fi
    generate_all_bootnode_secrets "$1"
    ;;
  generate-bootnode-secrets)
    if [ $# -ne 2 ]; then
      echo "Usage: $0 generate-bootnode-secrets <network> <bootnode_number>"
      exit 1
    fi
    generate_bootnode_secrets "$1" "$2"
    ;;
  upload-proposer-key)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 upload-proposer-key <network>"
      exit 1
    fi
    upload_proposer_key "$1"
    ;;
  upload-batcher-key)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 upload-batcher-key <network>"
      exit 1
    fi
    upload_batcher_key "$1"
    ;;
  upload-sequencer-key)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 upload-sequencer-key <network>"
      exit 1
    fi
    upload_sequencer_key "$1"
    ;;
  upload-admin-key)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 upload-admin-key <network>"
      exit 1
    fi
    upload_admin_key "$1"
    ;;
  generate-jwt-secret)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 generate-jwt-secret <network>"
      exit 1
    fi
    generate_jwt_secret "$1"
    ;;
  upload-all-account-keys)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 upload-all-account-keys <network>"
      exit 1
    fi
    upload_all_account_keys "$1"
    ;;
  generate-all-keys)
    if [ $# -ne 1 ]; then
      echo "Usage: $0 generate-all-keys <network>"
      exit 1
    fi
    generate_all_keys "$1"
    ;;
  *)
    echo "Unknown command: $command"
    echo "Usage: $0 <command> [arguments...]"
    exit 1
    ;;
  esac
}

# Execute main function with all script arguments
main "$@"
