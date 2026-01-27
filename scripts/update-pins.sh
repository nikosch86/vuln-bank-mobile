#!/bin/bash
#
# Update SSL Pin Hashes in the shared .env file
#
# This script fetches the current certificate pins from a domain and updates
# the shared .env file with the new hashes.
#
# Level-specific .env.{level} files contain only feature flags.
#
# Usage:
#   ./scripts/update-pins.sh [domain] [port]
#
# Examples:
#   ./scripts/update-pins.sh                    # Uses SSL_PIN_DOMAIN from .env
#   ./scripts/update-pins.sh vulnbank.org       # Specify domain
#   ./scripts/update-pins.sh api.example.com 8443
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

# Get domain from argument or .env
if [ -n "$1" ]; then
    DOMAIN="$1"
else
    # Try to read from .env
    if [ -f "$ENV_FILE" ]; then
        DOMAIN=$(grep "^SSL_PIN_DOMAIN=" "$ENV_FILE" | cut -d'=' -f2)
    fi
fi

PORT="${2:-443}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain> [port]"
    echo ""
    echo "Or set SSL_PIN_DOMAIN in .env"
    exit 1
fi

echo "Fetching pins for $DOMAIN:$PORT..."
echo ""

# Create temp directory for certificates
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Fetch the certificate chain
echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:$PORT" -showcerts 2>/dev/null | \
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{ if(/BEGIN CERTIFICATE/){i++}; out="'$TEMP_DIR'/cert"i".pem"; print > out }'

# Get SPKI hashes
HASH_1=""
HASH_2=""

for cert in "$TEMP_DIR"/*.pem; do
    HASH=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | \
        openssl pkey -pubin -outform DER 2>/dev/null | \
        openssl dgst -sha256 -binary | \
        openssl enc -base64)

    if [ -z "$HASH_1" ]; then
        HASH_1="$HASH"
    elif [ -z "$HASH_2" ]; then
        HASH_2="$HASH"
        break
    fi
done

if [ -z "$HASH_1" ]; then
    echo "Error: Could not fetch certificates from $DOMAIN:$PORT"
    exit 1
fi

# If no second hash, use the first as backup
if [ -z "$HASH_2" ]; then
    HASH_2="$HASH_1"
fi

echo "Leaf certificate pin:     $HASH_1"
echo "Intermediate/backup pin:  $HASH_2"
echo ""

# Update only the shared .env file
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found"
    exit 1
fi

echo "Updating $(basename "$ENV_FILE")..."

# Update or add SSL_PIN_DOMAIN
if grep -q "^SSL_PIN_DOMAIN=" "$ENV_FILE"; then
    sed -i "s|^SSL_PIN_DOMAIN=.*|SSL_PIN_DOMAIN=$DOMAIN|" "$ENV_FILE"
else
    echo "SSL_PIN_DOMAIN=$DOMAIN" >> "$ENV_FILE"
fi

# Update or add SSL_PIN_HASH_1
if grep -q "^SSL_PIN_HASH_1=" "$ENV_FILE"; then
    sed -i "s|^SSL_PIN_HASH_1=.*|SSL_PIN_HASH_1=$HASH_1|" "$ENV_FILE"
else
    echo "SSL_PIN_HASH_1=$HASH_1" >> "$ENV_FILE"
fi

# Update or add SSL_PIN_HASH_2
if grep -q "^SSL_PIN_HASH_2=" "$ENV_FILE"; then
    sed -i "s|^SSL_PIN_HASH_2=.*|SSL_PIN_HASH_2=$HASH_2|" "$ENV_FILE"
else
    echo "SSL_PIN_HASH_2=$HASH_2" >> "$ENV_FILE"
fi

echo ""
echo ".env file updated with new pins."
echo ""
echo "Remember to rebuild the app after updating pins:"
echo "  make build-android"
echo ""
