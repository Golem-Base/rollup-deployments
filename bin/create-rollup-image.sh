#!/usr/bin/env bash
# rollup-deployments/bin/create-rollup-image.sh

set -euo pipefail

# Constants
REGISTRY="quay.io"
REGISTRY_ORG="golemnetwork"
REPOSITORY="rollup-deployment"
IMAGE_NAME=${IMAGE_NAME:-"golem-base-init"}

PRJ_ROOT=${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}
TEMP_IMAGE_LIST="/tmp/rollup-image-${DEPLOYMENT_NAME:-}.txt"

# Helper function to print a separator line
function print_separator {
  echo "==================================================="
}

# Help function
function show_help {
  echo "Usage: $0 [OPTIONS] COMMAND"
  echo ""
  echo "Commands:"
  echo "  build           Build the Docker image"
  echo "  push            Push the Docker image to the registry"
  echo "  all             Build and push the Docker image"
  echo ""
  echo "Options:"
  echo "  -d, --deployment-dir DIR  Deployment directory to package"
  echo "  -v, --version VERSION     Version tag for the image (default: latest)"
  echo "  -o, --output-dir DIR      Specify output directory for build artifacts (default: temp directory)"
  echo "  -h, --help               Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  QUAY_USERNAME   Username for Quay.io registry (required for push)"
  echo "  QUAY_TOKEN      Token for Quay.io registry (required for push)"
  echo ""
  echo "Examples:"
  echo "  $0 --deployment-dir kaolin build"
  echo "  $0 --deployment-dir kaolin --version v1.0.0 build"
  echo "  $0 --deployment-dir kaolin --output-dir /tmp/build-output build"
  echo "  $0 --deployment-dir kaolin push"
  echo "  $0 --deployment-dir kaolin all"
}

# Parse arguments
DEPLOYMENT_DIR=""
COMMAND=""
VERSION="latest"
OUTPUT_DIR=""

# Parse options using getopt
TEMP=$(getopt -o "d:v:o:h" --long "deployment-dir:,version:,output-dir:,help" -n "$0" -- "$@")
if [ $? -ne 0 ]; then
  echo "Error parsing arguments" >&2
  show_help
  exit 1
fi

eval set -- "$TEMP"

while true; do
  case "$1" in
  -d | --deployment-dir)
    DEPLOYMENT_DIR="$2"
    shift 2
    ;;
  -v | --version)
    VERSION="$2"
    shift 2
    ;;
  -o | --output-dir)
    OUTPUT_DIR="$2"
    shift 2
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Internal error!"
    exit 1
    ;;
  esac
done

# Get the command (must be the last argument)
if [ $# -eq 1 ]; then
  COMMAND="$1"
else
  echo "Error: Command required (build, push, or all)"
  show_help
  exit 1
fi

# Validate command
if [[ ! $COMMAND =~ ^(build|push|all)$ ]]; then
  echo "Error: Invalid command. Use build, push, or all."
  show_help
  exit 1
fi

# Check for required deployment directory
if [ -z "$DEPLOYMENT_DIR" ]; then
  echo "Error: Deployment directory must be specified with --deployment-dir"
  show_help
  exit 1
fi

# Verify the deployment directory exists
FULL_DEPLOYMENT_PATH="$PRJ_ROOT/deploy/$DEPLOYMENT_DIR"
if [ ! -d "$FULL_DEPLOYMENT_PATH" ]; then
  echo "Error: Deployment directory not found: $FULL_DEPLOYMENT_PATH"
  exit 1
fi

# Extract the deployment name (last component of the path)
DEPLOYMENT_NAME=$(basename "$DEPLOYMENT_DIR")
TEMP_IMAGE_LIST="/tmp/rollup-image-${DEPLOYMENT_NAME}.txt"

# Create image tags
if [ "$VERSION" = "latest" ]; then
  # Create a timestamp for the image tag if using latest
  TIMESTAMP=$(date '+%Y%m%d%H%M%S')
  IMAGE_TAG="$DEPLOYMENT_NAME-$TIMESTAMP"
else
  # Use the specified version
  IMAGE_TAG="$DEPLOYMENT_NAME-$VERSION"
fi

FULL_IMAGE_NAME="${REGISTRY}/${REGISTRY_ORG}/${REPOSITORY}:${IMAGE_TAG}"
LATEST_IMAGE_NAME="${REGISTRY}/${REGISTRY_ORG}/${REPOSITORY}:${DEPLOYMENT_NAME}-latest"

# Function to build the Docker image
function build_image {
  echo "Creating Docker image for deployment: $DEPLOYMENT_NAME (version: $VERSION)"
  echo "Target image: $FULL_IMAGE_NAME"

  if [ "$VERSION" != "latest" ]; then
    echo "Additional tag: $LATEST_IMAGE_NAME"
  fi

  # Create build directory - either user-specified or temporary
  local USING_TEMP=false
  local DOCKER_DIR

  if [ -z "$OUTPUT_DIR" ]; then
    DOCKER_DIR=$(mktemp -d)
    USING_TEMP=true
    echo "Using temporary build directory: $DOCKER_DIR"
  else
    # Ensure the output directory exists
    mkdir -p "$OUTPUT_DIR"
    DOCKER_DIR="$OUTPUT_DIR"
    echo "Using specified build directory: $DOCKER_DIR"
  fi

  # Create required subdirectories
  mkdir -p "$DOCKER_DIR/scripts" "$DOCKER_DIR/artifacts"

  # Copy the required files
  cp "$PRJ_ROOT/docker/Dockerfile" "$DOCKER_DIR/"
  cp -r "$PRJ_ROOT/docker/scripts/"* "$DOCKER_DIR/scripts/"

  # Get chain ID from genesis.json if it exists
  if [ -f "$FULL_DEPLOYMENT_PATH/genesis.json" ]; then
    CHAIN_ID=$(jq -r '.config.chainId' "$FULL_DEPLOYMENT_PATH/genesis.json")
    echo "$CHAIN_ID" >"$DOCKER_DIR/artifacts/chain-id"
    echo "Using chain ID: $CHAIN_ID"
  else
    echo "Warning: genesis.json not found, chain-id will not be available"
  fi

  # Copy all deployment files to artifacts
  for file in "$FULL_DEPLOYMENT_PATH"/*; do
    if [ -f "$file" ]; then
      cp "$file" "$DOCKER_DIR/artifacts/"
      echo "Copied $(basename "$file") to artifacts"
    fi
  done

  # Build the Docker image
  echo "Building Docker image..."
  if ! docker build -t "$FULL_IMAGE_NAME" "$DOCKER_DIR"; then
    echo "Error: Failed to build Docker image"
    [ "$USING_TEMP" = "true" ] && rm -rf "$DOCKER_DIR"
    exit 1
  fi

  # Tag as latest for this deployment if version was specified
  if [ "$VERSION" != "latest" ]; then
    echo "Tagging image as ${DEPLOYMENT_NAME}-latest..."
    docker tag "$FULL_IMAGE_NAME" "$LATEST_IMAGE_NAME"
  fi

  # Handle build directory cleanup or retention
  if [ "$USING_TEMP" = "true" ]; then
    rm -rf "$DOCKER_DIR"
    echo "Temporary build directory removed"
  else
    print_separator
    echo "Build artifacts preserved in: $DOCKER_DIR"
  fi

  print_separator
  echo "Docker image creation complete!"
  echo "Image: ${FULL_IMAGE_NAME}"
  [ "$VERSION" != "latest" ] && echo "Latest tag: ${LATEST_IMAGE_NAME}"
  print_separator

  # Save image names for later use by push
  echo "${FULL_IMAGE_NAME}" >"$TEMP_IMAGE_LIST"
  [ "$VERSION" != "latest" ] && echo "${LATEST_IMAGE_NAME}" >>"$TEMP_IMAGE_LIST"
}

# Function to push the Docker image to the registry
function push_image {
  # Determine which images to push
  local IMAGES_TO_PUSH

  if [ -f "$TEMP_IMAGE_LIST" ]; then
    IMAGES_TO_PUSH=$(cat "$TEMP_IMAGE_LIST")
  else
    echo "Warning: Image reference not found. Using generated name: ${FULL_IMAGE_NAME}"
    echo "If this is not correct, please build the image first."
    IMAGES_TO_PUSH="$FULL_IMAGE_NAME"
  fi

  print_separator
  echo "Starting image push to registry"
  print_separator

  # Push each image
  for image in $IMAGES_TO_PUSH; do
    echo "Pushing image: $image"
    if ! docker push "$image"; then
      echo "Error: Failed to push image $image to $REGISTRY"
      docker logout "$REGISTRY"
      exit 1
    fi
    echo "Successfully pushed: $image"
  done

  print_separator
  echo "Success! All images uploaded to $REGISTRY"
  echo "Images:"
  for image in $IMAGES_TO_PUSH; do
    echo "  - $image"
  done
  print_separator

  docker logout "$REGISTRY"
}

# Execute the requested command
case "$COMMAND" in
build)
  build_image
  ;;
push)
  push_image
  ;;
all)
  build_image
  push_image
  ;;
esac

exit 0
