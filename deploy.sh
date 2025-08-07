#!/bin/bash

set -e

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

VERSION=${1:-"latest"}
RESTART=${2:-""} # Optional: "down" to stop services only
SERVERS=("backend1" "backend2" "backend3")
TEST_SERVERS=("backend1" "backend2" "backend3")
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_DELAY=5

# Determine if this is a test deployment
if [ "$VERSION" = "test" ]; then
    IS_TEST=true
    VERSION="latest"
    COMPOSE_FILE="-f docker-compose.test.yml"
elif [ "$VERSION" = "ha" ]; then
    IS_HA=true
    VERSION="latest"
    COMPOSE_FILE="-f docker-compose.ha.yml"
else
    IS_TEST=false
    IS_HA=false
    COMPOSE_FILE="-f docker-compose.yml"
fi

DOCKER_COMPOSE_CMD="MSYS_NO_PATHCONV=1 docker-compose $COMPOSE_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

docker_compose() {
    MSYS_NO_PATHCONV=1 docker-compose $COMPOSE_FILE "$@"
}

# Restart mode
if [ -n "$RESTART" ]; then
    log "Restarting services..."

    if docker_compose down; then
        log "✓ Stopped services successfully"
        if [ "$RESTART" = "down" ]; then
            exit 0
        fi
    else
        log "ERROR: Failed to stop services"
        exit 1
    fi

    if docker_compose up -d --remove-orphans; then
        log "✓ Reloaded nginx configuration"
    else
        log "ERROR: Failed to reload nginx configuration"
        exit 1
    fi

    exit 0
fi

check_health() {
    local server=$1
    local retries=$HEALTH_CHECK_RETRIES

    log "Checking health of $server..."

    while [ $retries -gt 0 ]; do
        # Check if Apache is running by looking for the process
        if docker_compose exec -T $server sh -c "ps aux | grep apache2 | grep -v grep" >/dev/null 2>&1; then
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

wait_for_services() {
    local check_command="$1"
    local service_description="${2:-services}"
    local max_wait="${3:-120}"
    local check_interval="${4:-10}"

    local wait_time=0

    log "Waiting for ${service_description} to initialize..."

    while [ $wait_time -lt $max_wait ]; do
        log "Checking ${service_description} status... (${wait_time}s elapsed)"

        if eval "$check_command"; then
            log "✓ All ${service_description} are running"
            return 0
        fi

        log "Services still starting, waiting ${check_interval}s..."
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    log "WARNING: Timeout waiting for ${service_description} to start"
    return 1
}

check_ha_services() {
    log "Checking HA services..."

    # Check Redis Sentinel
    if ! docker_compose ps redis_sentinel | grep -q "Up"; then
        log "WARNING: Redis Sentinel is not running"
        return 1
    fi

    # Check Keepalived
    if ! docker_compose ps keepalived | grep -q "Up"; then
        log "WARNING: Keepalived is not running"
        return 1
    fi

    # Check Sentinel can see Redis
    if ! docker_compose exec -T redis_sentinel redis-cli -p 26379 sentinel masters >/dev/null 2>&1; then
        log "WARNING: Sentinel cannot communicate with Redis"
        return 1
    fi

    log "✓ All HA services are healthy"
    return 0
}

deploy_test() {
    log "Starting TEST deployment with test servers"

    # Start the entire test environment
    log "Starting complete test environment..."
    docker_compose up -d --remove-orphans

    # Wait for services to initialize
    test_check="\
        docker_compose ps redis | grep -q 'Up' && \
        docker_compose ps nginx_proxy | grep -q 'Up' && \
        docker_compose ps backend1 | grep -q 'Up' && \
        docker_compose ps backend2 | grep -q 'Up' && \
        docker_compose ps backend3 | grep -q 'Up'"

    wait_for_services "$test_check" "test services"

    # Verify critical services
    if ! docker_compose ps redis | grep -q "Up"; then
        log "ERROR: Redis is not running"
        exit 1
    fi

    if ! docker_compose ps nginx_proxy | grep -q "Up"; then
        log "ERROR: nginx_proxy is not running. Checking logs..."
        docker_compose logs nginx_proxy
        exit 1
    fi

    log "All core services are running"

    # Final status
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
    exit 0
}

deploy_ha() {
    log "Starting HA deployment with high availability services"

    # Check if keepalived.conf exists
    if [ ! -f "keepalived/keepalived.conf" ]; then
        log "ERROR: keepalived/keepalived.conf not found"
        log "Please copy keepalived/keepalived.conf.example to keepalived/keepalived.conf and configure it"
        exit 1
    fi

    # Start HA environment
    log "Starting HA environment (redis, nginx_proxy, sentinel, keepalived)..."
    docker_compose up -d --remove-orphans

    # Wait longer for HA services to initialize
    ha_check="\
        docker_compose ps redis | grep -q 'Up' && \
        docker_compose ps nginx_proxy | grep -q 'Up' && \
        docker_compose ps redis_sentinel | grep -q 'Up' && \
        docker_compose ps keepalived | grep -q 'Up'"

    wait_for_services "$ha_check" "HA services"

    # Verify core services
    if ! docker_compose ps redis | grep -q "Up"; then
        log "ERROR: Redis is not running"
        docker_compose logs redis
        exit 1
    fi

    if ! docker_compose ps nginx_proxy | grep -q "Up"; then
        log "ERROR: nginx_proxy is not running. Checking logs..."
        docker_compose logs nginx_proxy
        exit 1
    fi

    # Check HA services
    if ! check_ha_services; then
        log "ERROR: HA services are not healthy"
        exit 1
    fi

    log "All HA services are running and healthy"

    # Final status
    log "=== HA deployment completed successfully ==="
    log "High Availability environment is running:"
    log "- Load balancer: http://localhost:${HTTP_PORT:-80} (and VIP if configured)"
    log "- Redis: localhost:${REDIS_PORT:-6379}"
    log "- Redis Sentinel: localhost:26379"
    log "- HA Status: docker-compose -f docker-compose.yml -f docker-compose.ha.yml ps"
    log ""
    log "Run 'docker-compose -f docker-compose.yml -f docker-compose.ha.yml down' to cleanup"
    exit 0
}

deploy_proxy() {
    log "Starting proxy-only deployment with version: $VERSION"

    # For normal deployments, only manage the proxy infrastructure
    log "Starting proxy infrastructure..."
    docker_compose up -d --remove-orphans

    # Wait for services to initialize
    proxy_check="\
        docker_compose ps redis | grep -q 'Up' && \
        docker_compose ps nginx_proxy | grep -q 'Up'"

    wait_for_services "$proxy_check" "proxy services"

    # Verify proxy services
    if ! docker_compose ps redis | grep -q "Up"; then
        log "ERROR: Redis is not running"
        exit 1
    fi

    if ! docker_compose ps nginx_proxy | grep -q "Up"; then
        log "ERROR: nginx_proxy is not running. Checking logs..."
        docker_compose logs nginx_proxy
        exit 1
    fi

    log "Proxy infrastructure is running"
    log "Backend servers should be managed separately on their respective hosts"

    # Skip the rolling update section for normal deployments
    log "=== Proxy deployment completed successfully ==="
    log "NGINX proxy is ready to handle requests to external backend servers"
    log "Backend servers listed in nginx/servers.conf should be updated independently"

    # Final status
    log "=== Proxy deployment completed successfully ==="
    log "NGINX proxy is ready to handle requests to external backend servers"
    log "Backend servers listed in nginx/servers.conf should be updated independently"
    exit 0
}

# Script usage
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <version>"
    echo "Examples:"
    echo "  $0 v25.01.001    # Production deployment"
    echo "  $0 test          # Test deployment using test servers"
    echo "  $0 ha            # HA deployment with sentinel and keepalived"
    echo ""
    echo "For restart modes:"
    echo "  $0 test true        # Restart services"
    echo "  $0 test down        # Stop services"
    exit 1
fi

if [ "$IS_TEST" = true ]; then
    deploy_test
elif [ "$IS_HA" = true ]; then
    deploy_ha
else
    deploy_proxy
fi



