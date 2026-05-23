#!/usr/bin/env bash
set -e

echo ""
echo "=== Build ONLYOFFICE Mobile-Unblocked Image ==="
echo ""

# Detect version from DocumentServer
cd "$(dirname "$0")"

COMMIT_HASH=$(git rev-parse --short HEAD)
BASE_VERSION="9.2.1"  # The official ONLYOFFICE version we're based on
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)

# The Dockerfile's grunt-inline step needs sdkjs/common/device_scale.js
# available as a sibling of web-apps at build time. We fetch it from upstream
# pinned at the exact SHA that the superproject's sdkjs submodule points to,
# so it stays in sync automatically on version bumps.
SDKJS_COMMIT=$(git ls-tree HEAD sdkjs 2>/dev/null | awk '{print $3}')
if [ -z "$SDKJS_COMMIT" ]; then
    echo "ERROR: Could not resolve sdkjs submodule SHA from superproject."
    echo "Run this script from the DocumentServer-unblocked repo root."
    exit 1
fi
echo "sdkjs pinned at: $SDKJS_COMMIT"

echo "Base ONLYOFFICE version: $BASE_VERSION"
echo "Commit: $COMMIT_HASH"
[ -n "$LATEST_TAG" ] && echo "Latest tag: $LATEST_TAG"

echo ""
echo "Choose version tag:"
echo "  1) Base version + commit ($BASE_VERSION-mobile-$COMMIT_HASH)"
[ -n "$LATEST_TAG" ] && echo "  2) Custom tag ($LATEST_TAG-mobile)"
echo "  3) Manual entry"
read -p "Enter choice [1/2/3]: " CHOICE

case "$CHOICE" in
    2)
        if [ -n "$LATEST_TAG" ]; then
            VERSION="$LATEST_TAG-mobile"
        else
            VERSION="$BASE_VERSION-mobile-$COMMIT_HASH"
        fi
        ;;
    3)
        read -p "Enter version tag: " CUSTOM_VERSION
        VERSION="$CUSTOM_VERSION"
        ;;
    *)
        VERSION="$BASE_VERSION-mobile-$COMMIT_HASH"
        ;;
esac

IMAGE_NAME="onlyoffice-mobile-unblocked"
FULL_TAG="$IMAGE_NAME:$VERSION"

echo ""
echo "Building image: $FULL_TAG"
echo ""

# Build the Docker image
docker build --build-arg "SDKJS_COMMIT=$SDKJS_COMMIT" -t "$FULL_TAG" .

# Tag as latest
docker tag "$FULL_TAG" "$IMAGE_NAME:latest"

echo ""
echo "Saving image to images/ directory..."
mkdir -p images
TAR_NAME="$IMAGE_NAME-$VERSION.tar"
docker save "$FULL_TAG" -o "images/$TAR_NAME"

# Compress it (optional but saves transfer time)
echo "Compressing image..."
gzip -f "images/$TAR_NAME"

echo ""
echo "Build complete."
echo "Image saved as: images/$TAR_NAME.gz"
echo ""
echo "To transfer to NAS, run:"
echo "  scp images/$TAR_NAME.gz user@nas-ip:/volume1/docker/onlyoffice/images/"
echo ""
