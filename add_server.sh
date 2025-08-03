#!/bin/bash
SERVER_NAME=$1
SERVER_PORT=${2:-80}

if [ -z "$SERVER_NAME" ]; then
    echo "Usage: $0 <server_name> [port]"
    exit 1
fi

echo "Checking if $SERVER_NAME:$SERVER_PORT is reachable..."

# Check if server is reachable
if command -v nc >/dev/null 2>&1; then
    # Use netcat if available
    if ! nc -z -w5 "$SERVER_NAME" "$SERVER_PORT" 2>/dev/null; then
        echo "ERROR: Cannot reach $SERVER_NAME:$SERVER_PORT"
        echo "Please ensure the server is running and accessible"
        exit 1
    fi
elif command -v telnet >/dev/null 2>&1; then
    # Fallback to telnet
    if ! timeout 5 telnet "$SERVER_NAME" "$SERVER_PORT" </dev/null >/dev/null 2>&1; then
        echo "ERROR: Cannot reach $SERVER_NAME:$SERVER_PORT"
        exit 1
    fi
else
    # Fallback to curl/wget for HTTP servers
    if command -v curl >/dev/null 2>&1; then
        if ! curl -s --connect-timeout 5 "http://$SERVER_NAME:$SERVER_PORT/health" >/dev/null 2>&1; then
            echo "WARNING: HTTP health check failed for $SERVER_NAME:$SERVER_PORT"
            echo "Server may not be ready or doesn't have /health endpoint"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        echo "WARNING: Cannot verify server connectivity (no nc, telnet, or curl available)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo "✓ Server $SERVER_NAME:$SERVER_PORT is reachable"

# Check if server already exists
if grep -q "server $SERVER_NAME:$SERVER_PORT" nginx/servers.conf 2>/dev/null; then
    echo "WARNING: Server $SERVER_NAME:$SERVER_PORT already exists in configuration"
    exit 1
fi

# Add server to config
echo "server $SERVER_NAME:$SERVER_PORT max_fails=3 fail_timeout=30s;" >> nginx/servers.conf

# Reload nginx
if docker-compose exec nginx_proxy nginx -s reload; then
    echo "✓ Added $SERVER_NAME:$SERVER_PORT to load balancer"
else
    echo "ERROR: Failed to reload nginx configuration"
    # Remove the added line on failure
    sed -i "/server $SERVER_NAME:$SERVER_PORT/d" nginx/servers.conf
    exit 1
fi
