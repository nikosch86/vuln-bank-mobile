#!/bin/bash
# Update SSL pins from backend_certificates/cert.pem
# Run this whenever the backend certificate changes
#
# This script updates ONLY the shared .env file.
# Level-specific .env.{level} files contain only feature flags.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERT_FILE="$PROJECT_DIR/backend_certificates/cert.pem"
ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$CERT_FILE" ]; then
    echo "Error: Certificate not found at $CERT_FILE"
    exit 1
fi

echo "Extracting SPKI hash from $CERT_FILE..."

# Extract SPKI hash
HASH=$(openssl x509 -in "$CERT_FILE" -pubkey -noout 2>/dev/null | \
    openssl pkey -pubin -outform der 2>/dev/null | \
    openssl dgst -sha256 -binary | \
    openssl enc -base64)

if [ -z "$HASH" ]; then
    echo "Error: Failed to extract SPKI hash"
    exit 1
fi

echo "SPKI Hash: $HASH"
echo ""

# Update only the shared .env file
if [ -f "$ENV_FILE" ]; then
    echo "Updating $ENV_FILE..."
    sed -i "s|^SSL_PIN_HASH_1=.*|SSL_PIN_HASH_1=$HASH|" "$ENV_FILE"
    sed -i "s|^SSL_PIN_HASH_2=.*|SSL_PIN_HASH_2=$HASH|" "$ENV_FILE"
else
    echo "Error: $ENV_FILE not found"
    exit 1
fi

# Copy cert to Android resources
echo ""
echo "Copying certificate to Android resources..."
mkdir -p "$PROJECT_DIR/android/app/src/main/res/raw"
mkdir -p "$PROJECT_DIR/android/app/src/debug/res/raw"
cp "$CERT_FILE" "$PROJECT_DIR/android/app/src/main/res/raw/backend_cert.pem"
cp "$CERT_FILE" "$PROJECT_DIR/android/app/src/debug/res/raw/backend_cert.pem"

echo ""
echo "Done! Updated pins in .env and copied cert to Android resources."
echo ""
echo "Remember to rebuild the app: make clean && make build-android"
