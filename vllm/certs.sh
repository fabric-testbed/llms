#!/bin/bash

# Define the directory name
SSL_DIR="./ssl"

# Create the directory if it doesn't exist
mkdir -p "$SSL_DIR"

echo "Generating self-signed certificates in $SSL_DIR..."

# Generate the certificates
# public.pem (The Certificate)
# private.pem (The Private Key)
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
  -keyout "$SSL_DIR/private.pem" \
  -out "$SSL_DIR/public.pem" \
  -subj "/CN=localhost"

# Set restrictive permissions
# 600: Owner can read/write (needed for the private key)
# 644: Owner can read/write, others can only read (for the public cert)
chmod 600 "$SSL_DIR/private.pem"
chmod 644 "$SSL_DIR/public.pem"

echo "------------------------------------------"
echo "Success! Files created:"
ls -l "$SSL_DIR"
echo "------------------------------------------"