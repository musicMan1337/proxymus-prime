#!/bin/bash

# check if ssl is already generated
if [ -f "nginx/ssl/server.crt" ]; then
    echo "SSL certificate already exists, skipping generation"
    exit 0
fi

echo "Generating SSL certificate..."

# Create ssl directory if it doesn't exist
mkdir -p nginx/ssl
cd nginx/ssl

# Generate self-signed certificate for development
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout server.key \
    -out server.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

echo "SSL certificate generated successfully"

cd ../..
