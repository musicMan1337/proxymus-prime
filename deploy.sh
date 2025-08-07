#!/bin/bash

set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

VERSION=${1:-"latest"}
RESTART=${2:-"false"}
SERVERS=("backend1" "backend2" "backend3")
TEST_SERVERS=("backend1" "backend2" "backend3")
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_DELAY=5

# Determine if this is a test deployment
if [ "$VERSION" = "test" ]; then
    IS_TEST=true
    VERSION="latest"
    COMPOSE_FILE="-f docker-compose.test.yml"
    CURRENT_SERVERS=("${TEST_SERVERS[@]}")
elif [ "$VERSION" = "ha" ]; then
    IS_HA=true
    VERSION="latest"
    COMPOSE_FILE="-f docker-compose.ha.yml"
    CURRENT_SERVERS=("${SERVERS[@]}")
else
    IS_TEST=false
    IS_HA=false
    COMPOSE_FILE="-f docker-compose.yml"
    CURRENT_SERVERS=("${SERVERS[@]}")
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

if [ "$RESTART" = "true" ]; then
    log "Restarting services..."

    if docker-compose $COMPOSE_FILE down; then
        log "✓ Stopped services"
    else
        log "ERROR: Failed to stop services"
        exit 1
    fi

    if docker-compose $COMPOSE_FILE up -d; then
        log "✓ Reloaded nginx configuration"
        exit 0
    else
        log "ERROR: Failed to reload nginx configuration"
        exit 1
    fi
fi

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

check_ha_services() {
    log "Checking HA services..."

    # Check Redis Sentinel
    if ! docker-compose $COMPOSE_FILE ps redis_sentinel | grep -q "Up"; then
        log "WARNING: Redis Sentinel is not running"
        return 1
    fi

    # Check Keepalived
    if ! docker-compose $COMPOSE_FILE ps keepalived | grep -q "Up"; then
        log "WARNING: Keepalived is not running"
        return 1
    fi

    # Check Sentinel can see Redis
    if ! docker-compose $COMPOSE_FILE exec -T redis_sentinel redis-cli -p 26379 sentinel masters >/dev/null 2>&1; then
        log "WARNING: Sentinel cannot communicate with Redis"
        return 1
    fi

    log "✓ All HA services are healthy"
    return 0
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
            # docker network create proxy_network
        fi

        # Start the entire test environment
        log "Starting complete test environment..."
        docker-compose $COMPOSE_FILE up -d

        # Wait for services to initialize
        log "Waiting for services to initialize..."
        sleep 30

        # Verify critical services
        if ! docker-compose $COMPOSE_FILE ps redis | grep -q "Up"; then
            log "ERROR: Redis is not running"
            exit 1
        fi

        if ! docker-compose $COMPOSE_FILE ps nginx_proxy | grep -q "Up"; then
            log "ERROR: nginx_proxy is not running. Checking logs..."
            docker-compose $COMPOSE_FILE logs nginx_proxy
            exit 1
        fi

        log "All core services are running"

    elif [ "$IS_HA" = true ]; then
        log "Starting HA deployment with high availability services"

        # Create proxy network if it doesn't exist
        if ! docker network ls | grep -q proxy_network; then
            log "Creating proxy_network..."
            docker network create proxy_network
        fi

        # Check if keepalived.conf exists
        if [ ! -f "keepalived/keepalived.conf" ]; then
            log "ERROR: keepalived/keepalived.conf not found"
            log "Please copy keepalived/keepalived.conf.example to keepalived/keepalived.conf and configure it"
            exit 1
        fi

        # Start HA environment
        log "Starting HA environment (redis, nginx_proxy, sentinel, keepalived)..."
        docker-compose $COMPOSE_FILE up -d

        # Wait longer for HA services to initialize
        log "Waiting for HA services to initialize..."
        sleep 45

        # Verify core services
        if ! docker-compose $COMPOSE_FILE ps redis | grep -q "Up"; then
            log "ERROR: Redis is not running"
            exit 1
        fi

        if ! docker-compose $COMPOSE_FILE ps nginx_proxy | grep -q "Up"; then
            log "ERROR: nginx_proxy is not running. Checking logs..."
            docker-compose $COMPOSE_FILE logs nginx_proxy
            exit 1
        fi

        # Check HA services
        if ! check_ha_services; then
            log "ERROR: HA services are not healthy"
            exit 1
        fi

        log "All HA services are running and healthy"

    else
        log "Starting proxy-only deployment with version: $VERSION"

        # For normal deployments, only manage the proxy infrastructure
        log "Starting proxy infrastructure..."
        docker-compose $COMPOSE_FILE up -d --remove-orphans

        # Wait for services to initialize
        log "Waiting for proxy services to initialize..."
        sleep 15

        # Verify proxy services
        if ! docker-compose $COMPOSE_FILE ps redis | grep -q "Up"; then
            log "ERROR: Redis is not running"
            exit 1
        fi

        if ! docker-compose $COMPOSE_FILE ps nginx_proxy | grep -q "Up"; then
            log "ERROR: nginx_proxy is not running. Checking logs..."
            docker-compose $COMPOSE_FILE logs nginx_proxy
            exit 1
        fi

        log "Proxy infrastructure is running"
        log "Backend servers should be managed separately on their respective hosts"

        # Skip the rolling update section for normal deployments
        log "=== Proxy deployment completed successfully ==="
        log "NGINX proxy is ready to handle requests to external backend servers"
        log "Backend servers listed in nginx/servers.conf should be updated independently"
        return 0
    fi

    # Update each server (only for test mode now)
    if [ "$IS_TEST" = true ]; then
        for server in "${CURRENT_SERVERS[@]}"; do
            log "=== Updating $server ==="

            if update_server $server; then
                log "$server update completed successfully"
                sleep 30
            else
                log "ERROR: Failed to update $server. Stopping deployment."
                exit 1
            fi
        done
    fi

    # Final status
    if [ "$IS_TEST" = true ]; then
        log "=== Test deployment completed successfully ==="
        log "Test environment is running:"
        log "- Load balancer: http://localhost:${HTTP_PORT:-80}"
        log "- Redis: localhost:${REDIS_PORT:-6379}"
        log "- Direct test server access:"
        log "  - backend1: http://localhost:${BACKEND1_PORT:-8081}"
        log "  - backend2: http://localhost:${BACKEND2_PORT:-8082}"
        log "  - backend3: http://localhost:${BACKEND3_PORT:-8083}"
        log ""
        log "Run 'docker-compose -f docker-compose.yml -f docker-compose.test.yml down' to cleanup"
    elif [ "$IS_HA" = true ]; then
        log "=== HA deployment completed successfully ==="
        log "High Availability environment is running:"
        log "- Load balancer: http://localhost:${HTTP_PORT:-80} (and VIP if configured)"
        log "- Redis: localhost:${REDIS_PORT:-6379}"
        log "- Redis Sentinel: localhost:26379"
        log "- HA Status: docker-compose -f docker-compose.yml -f docker-compose.ha.yml ps"
        log ""
        log "Run 'docker-compose -f docker-compose.yml -f docker-compose.ha.yml down' to cleanup"
    else
        log "=== Proxy deployment completed successfully ==="
        log "NGINX proxy is ready to handle requests to external backend servers"
        log "Backend servers listed in nginx/servers.conf should be updated independently"
    fi
}

# Script usage
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <version>"
    echo "Examples:"
    echo "  $0 v25.01.001    # Production deployment"
    echo "  $0 test          # Test deployment using test servers"
    echo "  $0 ha            # HA deployment with sentinel and keepalived"
    exit 1
fi

main "$@"



