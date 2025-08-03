#!/bin/bash

set -e

VERSION=${1:-"latest"}
SERVERS=("backend1" "backend2" "backend3")
TEST_SERVERS=("backend1" "backend2" "backend3")
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_DELAY=5

# Determine if this is a test deployment
if [ "$VERSION" = "test" ]; then
    IS_TEST=true
    VERSION="latest"
    COMPOSE_FILE="-f docker-compose.yml -f docker-compose.test.yml"
    CURRENT_SERVERS=("${TEST_SERVERS[@]}")
else
    IS_TEST=false
    COMPOSE_FILE="-f docker-compose.yml"
    CURRENT_SERVERS=("${SERVERS[@]}")
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_health() {
    local server=$1
    local retries=$HEALTH_CHECK_RETRIES

    log "Checking health of $server..."

    while [ $retries -gt 0 ]; do
        # Check if Apache is running by looking for the process
        if docker-compose $COMPOSE_FILE exec -T $server sh -c "ps aux | grep apache2 | grep -v grep" >/dev/null 2>&1; then
            log "$server is healthy"
            return 0
        fi

        log "Health check failed for $server, retrying in ${HEALTH_CHECK_DELAY}s... ($retries retries left)"
        sleep $HEALTH_CHECK_DELAY
        retries=$((retries - 1))
    done

    log "ERROR: $server failed health check"
    return 1
}

remove_from_load_balancer() {
    local server=$1

    # Skip load balancer operations in test mode
    if [ "$IS_TEST" = true ]; then
        log "Skipping load balancer removal for test deployment"
        return 0
    fi

    log "Removing $server from load balancer..."

    # Check if nginx_proxy is running
    if ! docker-compose $COMPOSE_FILE ps nginx_proxy | grep -q "Up"; then
        log "WARNING: nginx_proxy is not running, skipping load balancer removal"
        return 0
    fi

    # Comment out the server line in place
    docker-compose $COMPOSE_FILE exec nginx_proxy sh -c "
        sed -i '/server $server:80/s/^/#/' /etc/nginx/nginx.conf &&
        nginx -s reload
    "
}

add_to_load_balancer() {
    local server=$1

    # Skip load balancer operations in test mode
    if [ "$IS_TEST" = true ]; then
        log "Skipping load balancer addition for test deployment"
        return 0
    fi

    log "Adding $server back to load balancer..."

    # Check if nginx_proxy is running
    if ! docker-compose $COMPOSE_FILE ps nginx_proxy | grep -q "Up"; then
        log "WARNING: nginx_proxy is not running, skipping load balancer addition"
        return 0
    fi

    # Uncomment the server line in place
    docker-compose $COMPOSE_FILE exec nginx_proxy sh -c "
        sed -i '/server $server:80/s/^#//' /etc/nginx/nginx.conf &&
        nginx -s reload
    "
}

update_server() {
    local server=$1
    log "Starting update for $server..."

    # Remove from load balancer
    remove_from_load_balancer $server

    # Wait for connections to drain
    sleep 10

    # Stop the server
    log "Stopping $server..."
    docker-compose $COMPOSE_FILE stop $server

    # Update the server (pull new image)
    log "Updating $server to version $VERSION..."
    docker-compose $COMPOSE_FILE pull $server

    # Start the server
    log "Starting $server..."
    docker-compose $COMPOSE_FILE up -d $server

    # Wait for startup
    sleep 15

    # Health check
    if check_health $server; then
        # Add back to load balancer
        add_to_load_balancer $server
        log "$server updated successfully"
        return 0
    else
        log "ERROR: $server failed health check after update"
        return 1
    fi
}

main() {
    if [ "$IS_TEST" = true ]; then
        log "Starting TEST deployment with test servers"

        # Create proxy network if it doesn't exist
        if ! docker network ls | grep -q proxy_network; then
            log "Creating proxy_network..."
            docker network create proxy_network
        fi

        # Start the entire test environment including load balancer and redis
        log "Starting complete test environment (redis, nginx_proxy, test servers)..."
        docker-compose $COMPOSE_FILE up -d

        # Wait longer for all services to initialize
        log "Waiting for services to initialize..."
        sleep 30

        # Verify critical services are running
        if ! docker-compose $COMPOSE_FILE ps redis | grep -q "Up"; then
            log "ERROR: Redis is not running"
            exit 1
        fi

        # Check nginx_proxy status and logs if it's not running
        if ! docker-compose $COMPOSE_FILE ps nginx_proxy | grep -q "Up"; then
            log "ERROR: nginx_proxy is not running. Checking logs..."
            docker-compose $COMPOSE_FILE logs nginx_proxy
            exit 1
        fi

        log "All core services (redis, nginx_proxy) are running"
    else
        log "Starting rolling deployment with version: $VERSION"
    fi

    # Check if services are running
    if ! docker-compose $COMPOSE_FILE ps | grep -q "Up"; then
        log "ERROR: Some services are not running. Please start the stack first."
        exit 1
    fi

    # Update each server
    for server in "${CURRENT_SERVERS[@]}"; do
        log "=== Updating $server ==="

        if update_server $server; then
            log "$server update completed successfully"
            # Wait before next server
            sleep 30
        else
            log "ERROR: Failed to update $server. Stopping deployment."
            exit 1
        fi
    done

    if [ "$IS_TEST" = true ]; then
        log "=== Test deployment completed successfully ==="
        log "Test environment is running:"
        log "- Load balancer: http://localhost"
        log "- Redis: localhost:6379"
        log "- Direct test server access:"
        log "  - backend1: http://localhost:9081"
        log "  - backend2: http://localhost:9082"
        log "  - backend3: http://localhost:9083"
        log ""
        log "Run 'docker-compose -f docker-compose.yml -f docker-compose.test.yml down' to cleanup"
    else
        log "=== Deployment completed successfully ==="
        log "All servers have been updated to version: $VERSION"
    fi
}

# Script usage
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <version>"
    echo "Examples:"
    echo "  $0 v25.01.001    # Production deployment"
    echo "  $0 test          # Test deployment using test servers"
    exit 1
fi

main "$@"
