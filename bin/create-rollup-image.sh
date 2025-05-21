
#!/usr/bin/env bash
# rollup-deployments/bin/create-rollup-image.sh

set -euo pipefail

# Constants
REGISTRY="quay.io"
REGISTRY_ORG="golemnetwork"
REPOSITORY="rollup-deployments"
IMAGE_NAME=${IMAGE_NAME:-"golem-base-init"}

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PRJ_ROOT=${PRJ_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}

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
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  QUAY_USERNAME   Username for Quay.io registry (required for push)"
    echo "  QUAY_TOKEN      Token for Quay.io registry (required for push)"
    echo ""
    echo "Examples:"
    echo "  $0 --deployment-dir kaolin build"
    echo "  $0 --deployment-dir kaolin --version v1.0.0 build"
    echo "  $0 --deployment-dir kaolin push"
    echo "  $0 --deployment-dir kaolin all"
}

# Parse arguments
DEPLOYMENT_DIR=""
COMMAND=""
VERSION="latest"

# Parse options using getopt
TEMP=$(getopt -o "d:v:h" --long "deployment-dir:,version:,help" -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    echo "Error parsing arguments" >&2
    show_help
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        -d|--deployment-dir)
            DEPLOYMENT_DIR="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
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
if [[ ! "$COMMAND" =~ ^(build|push|all)$ ]]; then
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

    # Create temporary directories for the Docker build
    DOCKER_DIR=$(mktemp -d)
    mkdir -p $DOCKER_DIR/scripts $DOCKER_DIR/artifacts

    # Copy the required files
    cp "$PRJ_ROOT/docker/Dockerfile" "$DOCKER_DIR/"
    cp -r "$PRJ_ROOT/docker/scripts/"* "$DOCKER_DIR/scripts/"

    # Get chain ID from rollup.json
    if [ -f "$FULL_DEPLOYMENT_PATH/rollup.json" ]; then
        CHAIN_ID=$(jq -r '.l2_chain_id' "$FULL_DEPLOYMENT_PATH/rollup.json")
        echo "$CHAIN_ID" > "$DOCKER_DIR/artifacts/chain-id"
        echo "Using chain ID: $CHAIN_ID"
    else
        echo "Warning: rollup.json not found, chain-id will not be available"
    fi

    # Copy all deployment files to artifacts
    for file in "$FULL_DEPLOYMENT_PATH"/*; do
        if [ -f "$file" ]; then
            cp "$file" "$DOCKER_DIR/artifacts/"
            echo "Copied $(basename "$file") to artifacts"
        fi
    done

    # Build the Docker image using standard docker build
    echo "Building Docker image..."
    docker build -t "$FULL_IMAGE_NAME" "$DOCKER_DIR"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to build Docker image"
        rm -rf "$DOCKER_DIR"
        exit 1
    fi

    # Also tag as latest for this deployment if version was specified
    if [ "$VERSION" != "latest" ]; then
        echo "Tagging image as ${DEPLOYMENT_NAME}-latest..."
        docker tag "$FULL_IMAGE_NAME" "$LATEST_IMAGE_NAME"
    fi

    # Clean up
    rm -rf "$DOCKER_DIR"

    echo "==================================================="
    echo "Docker image creation complete!"
    echo "Image: ${FULL_IMAGE_NAME}"
    if [ "$VERSION" != "latest" ]; then
        echo "Latest tag: ${LATEST_IMAGE_NAME}"
    fi
    echo "==================================================="

    # Write the image names to a file for later use by push
    echo "${FULL_IMAGE_NAME}" > "/tmp/rollup-image-${DEPLOYMENT_NAME}.txt"
    if [ "$VERSION" != "latest" ]; then
        echo "${LATEST_IMAGE_NAME}" >> "/tmp/rollup-image-${DEPLOYMENT_NAME}.txt"
    fi
}

# Function to push the Docker image to the registry
function push_image {
    # Check if credentials are available
    if [ -z "${QUAY_USERNAME:-}" ] || [ -z "${QUAY_TOKEN:-}" ]; then
        echo "Error: Registry credentials not found."
        echo "Please set QUAY_USERNAME and QUAY_TOKEN environment variables."
        exit 1
    fi

    # If the image was just built, use the saved names, otherwise try to find it
    if [ -f "/tmp/rollup-image-${DEPLOYMENT_NAME}.txt" ]; then
        IMAGES_TO_PUSH=$(cat "/tmp/rollup-image-${DEPLOYMENT_NAME}.txt")
    else
        echo "Warning: Image reference not found. Using generated name: ${FULL_IMAGE_NAME}"
        echo "If this is not correct, please build the image first."
        IMAGES_TO_PUSH="$FULL_IMAGE_NAME"
    fi

    echo "Logging in to $REGISTRY..."
    echo "$QUAY_TOKEN" | docker login "$REGISTRY" -u "$QUAY_USERNAME" --password-stdin

    echo "==================================================="
    echo "Starting image push to registry"
    echo "==================================================="

    # Push each image
    for image in $IMAGES_TO_PUSH; do
        echo "Pushing image: $image"
        docker push "$image"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to push image $image to $REGISTRY"
            docker logout "$REGISTRY"
            exit 1
        fi
        echo "Successfully pushed: $image"
    done

    echo "==================================================="
    echo "Success! All images uploaded to $REGISTRY"
    echo "Images:"
    for image in $IMAGES_TO_PUSH; do
        echo "  - $image"
    done
    echo "==================================================="

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
