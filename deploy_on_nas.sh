#!/usr/bin/env bash
set -e

echo ""
echo "=== Deploy ONLYOFFICE Mobile-Unblocked on NAS ==="
echo ""

cd "$(dirname "$0")"

# Check for images directory
if [ ! -d images ]; then
    echo "Error: images/ directory not found."
    echo "Please build the image first with build_image.sh"
    exit 1
fi

cd images

# Find the most recent tar.gz file
TAR_FILE=$(ls -t onlyoffice-mobile-unblocked-*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$TAR_FILE" ]; then
    # Try uncompressed tar files
    TAR_FILE=$(ls -t onlyoffice-mobile-unblocked-*.tar 2>/dev/null | head -n 1)
fi

if [ -z "$TAR_FILE" ]; then
    echo "No image tar files found in images/."
    exit 1
fi

echo "Found image: $TAR_FILE"

# Decompress if needed
if [[ "$TAR_FILE" == *.gz ]]; then
    echo "Decompressing..."
    gunzip -k "$TAR_FILE"
    TAR_FILE="${TAR_FILE%.gz}"
fi

echo "Loading image: $TAR_FILE"
sudo docker load -i "$TAR_FILE"

# Extract version from tar filename
VERSION="${TAR_FILE#onlyoffice-mobile-unblocked-}"
VERSION="${VERSION%.tar}"

IMAGE_NAME="onlyoffice-mobile-unblocked"

# Tag the image with version and latest
sudo docker tag "$IMAGE_NAME:$VERSION" "$IMAGE_NAME:latest"

echo ""
echo "Image loaded successfully: $IMAGE_NAME:$VERSION"
echo ""

# Ask which environment to deploy to
echo "Which environment do you want to deploy to?"
echo "  1) Test environment (onlyoffice9-unblocked-test)"
echo "  2) Production environment (onlyoffice9-unblocked)"
echo "  3) Custom directory"
read -p "Enter choice [1/2/3]: " ENV_CHOICE

case "$ENV_CHOICE" in
    2)
        COMPOSE_DIR="/volume1/docker/compose-stacks/onlyoffice9-unblocked"
        ;;
    3)
        read -p "Enter full path to compose directory: " CUSTOM_DIR
        COMPOSE_DIR="$CUSTOM_DIR"
        ;;
    *)
        COMPOSE_DIR="/volume1/docker/compose-stacks/onlyoffice9-unblocked-test"
        ;;
esac

echo ""
echo "Deploying to: $COMPOSE_DIR"

# Check if directory exists
if [ ! -d "$COMPOSE_DIR" ]; then
    echo ""
    echo "Directory $COMPOSE_DIR does not exist."
    read -p "Create it now? [y/N]: " CREATE_DIR
    if [[ "$CREATE_DIR" =~ ^[Yy]$ ]]; then
        sudo mkdir -p "$COMPOSE_DIR"
        echo "Created $COMPOSE_DIR"
        echo "Note: You'll need to create docker-compose.yml and set up log directories as needed."
    else
        echo "Deployment cancelled."
        exit 1
    fi
fi

# Check for docker-compose.yml
if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    echo ""
    echo "Warning: docker-compose.yml not found in $COMPOSE_DIR"
    echo "Please create it before deploying."
    echo ""
    echo "You can copy from your onlyoffice9 directory and update the image name."
    exit 1
fi

echo ""
echo "Restarting compose stack..."
cd "$COMPOSE_DIR"

sudo docker compose down
sudo docker compose up -d

echo ""
echo "Deployment complete."
echo ""
echo "Container status:"
sudo docker compose ps
echo ""
echo "To view logs, run:"
echo "  sudo docker compose -f $COMPOSE_DIR/docker-compose.yml logs -f"
echo ""
