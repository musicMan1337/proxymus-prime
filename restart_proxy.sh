#!/bin/bash

if docker-compose exec nginx_proxy nginx -s reload; then
    echo "✓ Reloaded nginx configuration"
else
    echo "ERROR: Failed to reload nginx configuration"
    exit 1
fi
