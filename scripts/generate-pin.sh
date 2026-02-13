#!/bin/bash
#
# Generate SSL/TLS Certificate Pin Hashes
#
# This script extracts SPKI (Subject Public Key Info) hashes from a domain's
# certificate chain. These hashes are used for certificate pinning.
#
# Usage:
#   ./scripts/generate-pin.sh <domain> [port]
#
# Examples:
#   ./scripts/generate-pin.sh vulnbank.org
#   ./scripts/generate-pin.sh api.example.com 8443
#
# Output:
#   - SHA-256 SPKI hashes for each certificate in the chain
#   - Ready-to-use values for .env files
#

set -e

DOMAIN="${1:-}"
PORT="${2:-443}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain> [port]"
    echo ""
    echo "Examples:"
    echo "  $0 vulnbank.org"
    echo "  $0 api.example.com 8443"
    exit 1
fi

# Check for required tools
for cmd in openssl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

echo "Fetching certificate chain from $DOMAIN:$PORT..."
echo ""

# Create temp directory for certificates
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Fetch the certificate chain
echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:$PORT" -showcerts 2>/dev/null | \
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{ if(/BEGIN CERTIFICATE/){i++}; out="'$TEMP_DIR'/cert"i".pem"; print > out }'

# Count certificates
CERT_COUNT=$(ls -1 "$TEMP_DIR"/*.pem 2>/dev/null | wc -l)

if [ "$CERT_COUNT" -eq 0 ]; then
    echo "Error: Could not fetch certificates from $DOMAIN:$PORT"
    exit 1
fi

echo "Found $CERT_COUNT certificate(s) in chain"
echo ""
echo "=========================================="
echo "SPKI SHA-256 Hashes (Base64 encoded)"
echo "=========================================="
echo ""

# Process each certificate
HASH_NUM=1
for cert in "$TEMP_DIR"/*.pem; do
    # Get certificate subject
    SUBJECT=$(openssl x509 -in "$cert" -noout -subject 2>/dev/null | sed 's/subject=//')

    # Get certificate issuer
    ISSUER=$(openssl x509 -in "$cert" -noout -issuer 2>/dev/null | sed 's/issuer=//')

    # Get expiry date
    EXPIRY=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | sed 's/notAfter=//')

    # Generate SPKI hash (SHA-256, Base64 encoded)
    SPKI_HASH=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | \
        openssl pkey -pubin -outform DER 2>/dev/null | \
        openssl dgst -sha256 -binary | \
        openssl enc -base64)

    echo "Certificate $HASH_NUM:"
    echo "  Subject: $SUBJECT"
    echo "  Issuer:  $ISSUER"
    echo "  Expires: $EXPIRY"
    echo "  SPKI Hash: $SPKI_HASH"
    echo ""

    # Store hashes for env output
    eval "HASH_$HASH_NUM=\"$SPKI_HASH\""
    HASH_NUM=$((HASH_NUM + 1))
done

echo "=========================================="
echo "Environment Variables for .env files"
echo "=========================================="
echo ""
echo "# Copy these to your .env.* files:"
echo "SSL_PIN_DOMAIN=$DOMAIN"

if [ -n "$HASH_1" ]; then
    echo "SSL_PIN_HASH_1=$HASH_1"
fi

if [ -n "$HASH_2" ]; then
    echo "SSL_PIN_HASH_2=$HASH_2"
else
    # If only one cert, use the same hash as backup
    echo "SSL_PIN_HASH_2=$HASH_1"
fi

echo ""
echo "=========================================="
echo "Usage Notes"
echo "=========================================="
echo ""
echo "1. Pin the LEAF certificate (Certificate 1) for strictest pinning"
echo "2. Pin an INTERMEDIATE certificate for more flexibility during cert rotation"
echo "3. Always include a BACKUP pin (e.g., the intermediate CA)"
echo "4. Update pins BEFORE certificates expire!"
echo ""
echo "For react-native-ssl-pinning, use these hashes in your config."
echo "For OkHttp (Android native), prefix with 'sha256/': sha256/$HASH_1"
echo ""
