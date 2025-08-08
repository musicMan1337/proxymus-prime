#!/bin/sh
set -e

# Set default values for environment variables
export RATE_LIMIT_PER_IP=${RATE_LIMIT_PER_IP:-50}
export RATE_LIMIT_BURST=${RATE_LIMIT_BURST:-50}
export RATE_LIMIT_API_PER_IP=${RATE_LIMIT_API_PER_IP:-25}
export RATE_LIMIT_API_BURST=${RATE_LIMIT_API_BURST:-20}
export PROXY_SERVER_NAME=${PROXY_SERVER_NAME:-_}

# Process nginx.conf template with envsubst to a writable location
envsubst '${RATE_LIMIT_PER_IP} ${RATE_LIMIT_BURST} ${RATE_LIMIT_API_PER_IP} ${RATE_LIMIT_API_BURST} ${PROXY_SERVER_NAME}' \
    < /etc/nginx/nginx.conf.template > /tmp/nginx.conf

# Copy to the final location
cp /tmp/nginx.conf /etc/nginx/nginx.conf

# Start nginx
exec nginx -g 'daemon off;'
