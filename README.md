# NGINX Redis Proxy POC

A proof of concept for a generic NGINX load balancer with Redis session management, designed for zero-downtime rolling deployments with comprehensive testing and high availability support.

## Features

- **Load Balancing**: NGINX proxy with configurable upstream servers
- **Session Management**: Redis-backed session storage with automatic session forwarding
- **Zero Downtime Deployments**: Rolling update support with health checks
- **Generic Design**: Easily adaptable for different backend technologies
- **Session Persistence**: Sessions survive server restarts and deployments
- **Health Monitoring**: Built-in health checks and monitoring endpoints
- **SSL/TLS Support**: HTTPS with automatic certificate generation
- **High Availability**: Redis Sentinel and Keepalived support (experimental)
- **Comprehensive Testing**: Automated test suite with HTML reporting
- **Multiple Deployment Modes**: Production, test, and HA configurations

## Architecture

```
[Client] → [NGINX Proxy (HTTPS)] → [Backend Servers]
            ↓       ↓ ↑
            ↓     [Redis] (Session Management)
            Load Balancing
            Health Checks
            SSL Termination
```

## Quick Start

1. **Clone and Setup**

   ```bash
   git clone https://github.com/musicMan1337/proxymus-prime.git
   cd proxymus-prime

   # Create required configuration files
   cp .env.example .env
   cp nginx/servers.conf.example nginx/servers.conf

   # Edit .env with your Redis password
   # Edit nginx/servers.conf with your backend servers
   ```

2. **Generate SSL Certificate (Development)**

   ```bash
   ./generate_ssl.sh
   ```

3. **Start the Proxy Infrastructure**

   ```bash
   # Test deployment (with test backends)
   ./deploy.sh test

   # Production deployment (proxy only)
   ./deploy.sh v1.0.0

   # High Availability deployment (experimental)
   ./deploy.sh ha
   ```

4. **Test the Setup**

   ```bash
   # Check if all services are running
   docker-compose ps

   # Test HTTPS
   curl -k https://localhost

   # Test redirect
   curl -k -L http://localhost

   # Test load balancer - should cycle through each server
   for i in {1..5}; do curl -s -k https://localhost | jq -r .server_id; done

   # Test session management
   curl -k -X POST https://localhost/session \
        -H "Content-Type: application/json" \
        -d '{"username": "test", "data": "session_data"}'

   curl -k https://localhost/session
   ```

## Deployment Modes

### Production Mode (Default)

```bash
./deploy.sh v25.01.001
```

- Starts only NGINX proxy and Redis
- Backend servers managed externally
- Configure your backend servers in `nginx/servers.conf`

### Test Mode

```bash
./deploy.sh test
```

- Includes test PHP backend containers
- Direct access to backends on ports 8081-8083
- Perfect for development and testing

### High Availability Mode (WIP/Experimental)

```bash
./deploy.sh ha
```

- Includes Redis Sentinel for Redis monitoring
- Keepalived for VIP management
- Copy `keepalived/keepalived.example.conf` to `keepalived/keepalived.conf`

## Session Management

### How It Works

1. **Session Creation**: Backend servers create sessions by sending `X-New-Session-Data` header
2. **Session Storage**: Sessions stored in Redis with configurable TTL (default: 24 hours)
3. **Session Forwarding**: NGINX automatically forwards session data via `X-Session-Data` header
4. **Session Updates**: Backend servers can update session data during requests
5. **Session Persistence**: Sessions survive server restarts and deployments

### Session API

- `GET /session?session_id=<id>` - Retrieve session data
- `POST /session` - Create new session
- `PUT /session?session_id=<id>` - Update existing session
- `DELETE /session?session_id=<id>` - Delete session

### Backend Integration Examples

#### PHP Integration

```php
// Get session from NGINX headers
$sessionId = $_SERVER['HTTP_X_SESSION_ID'] ?? null;
$sessionData = $_SERVER['HTTP_X_SESSION_DATA'] ?? null;

if ($sessionData) {
    $session = json_decode($sessionData, true);
}

// Update session (sent back to NGINX)
$newSessionData = ['user_id' => 123, 'last_activity' => time()];
header('X-New-Session-Data: ' . json_encode($newSessionData));
```

#### Other Languages

The session system works with any backend that can:

- Read HTTP headers (`X-Session-ID`, `X-Session-Data`)
- Set HTTP response headers (`X-New-Session-Data`)

## Testing

### Automated Test Suite

```bash
# Run full test suite
./tests/run_tests.sh

# Run specific tests
source tests/setup_env.sh
python -m pytest tests/test_proxy.py -v
```

### Test Reports

- HTML reports generated at `tests/report.html`
- Tests cover load balancing, session management, SSL, and health checks

## Configuration

### Environment Variables (`.env`)

```bash
# Port Configuration
HTTP_PORT=80            # HTTP port (default: 80)
HTTPS_PORT=8443         # HTTPS port (default: 443)
REDIS_PORT=6379         # Redis port (default: 6379)

# Backend Test Ports (for test mode)
BACKEND1_PORT=8081      # Backend 1 direct access
BACKEND2_PORT=8082      # Backend 2 direct access
BACKEND3_PORT=8083      # Backend 3 direct access

# Redis
REDIS_PASSWORD=your_secure_redis_password_here
```

### Backend Servers (`nginx/servers.conf`)

```nginx
# Production servers
server 192.168.1.201:80 max_fails=3 fail_timeout=30s;
server 192.168.1.202:80 max_fails=3 fail_timeout=30s;

# Development servers
server dev-backend-1:8080 max_fails=1 fail_timeout=10s;
```

### SSL Configuration

- Development: Self-signed certificates via `./generate_ssl.sh`
- Production: Replace certificates in `nginx/ssl/`
- HTTP automatically redirects to HTTPS (except `/health` endpoint)

## Rolling Deployments

### For Test Mode

```bash
./deploy.sh test
```

Performs zero-downtime rolling updates of test backend containers.

### For Production Mode

Backend servers should be updated independently on their respective hosts. The proxy infrastructure remains running and will automatically detect healthy/unhealthy backends.

## High Availability (WIP/Experimental)

### Setup

1. Copy `keepalived/keepalived.example.conf` to `keepalived/keepalived.conf`
2. Configure VIP and network settings
3. Deploy: `./deploy.sh ha`

### Components

- **Redis Sentinel**: Monitors Redis health on port 26379
- **Keepalived**: Manages Virtual IP for failover
- **Health Checks**: Automatic failover based on service health

## Security Features

- **SSL/TLS**: HTTPS with configurable certificates
- **Redis Authentication**: Password-protected Redis access
- **Rate Limiting**: Configurable per-IP rate limits
- **Read-only Containers**: Containers run with read-only filesystems
- **Security Options**: `no-new-privileges` and user restrictions
- **Resource Limits**: CPU and memory constraints

## Monitoring

### Health Endpoints

- `GET /health` - Basic health check (HTTP only)
- Redis health monitored via Sentinel (HA mode)

### Logging

- NGINX access logs with session tracking
- Structured logging format includes session IDs and backend servers

### Docker Compose Commands

```bash
# View logs
docker-compose logs -f nginx_proxy
docker-compose logs -f redis

# Check status
docker-compose ps

# Restart services - any value except "down"
./deploy.sh test true

# Stop services
./deploy.sh test down
```

## Development

### Project Structure

```
├── nginx/
│   ├── nginx.conf         # Main NGINX configuration
│   ├── lua/               # Lua scripts for session management
│   ├── servers.conf       # Backend server definitions
│   └── ssl/               # SSL certificates
├── tests/
│   ├── test_proxy.py      # Comprehensive test suite
│   ├── run_tests.sh       # Test runner script
│   └── setup_env.sh       # Python environment setup
├── backend/               # Example PHP backend
├── deploy.sh              # Deployment script
└── docker-compose*.yml    # Docker configurations
```

### Adding New Backend Technologies

1. Update `nginx/servers.conf` with your backend servers
2. Ensure backends can read `X-Session-*` headers
3. Implement `X-New-Session-Data` header for session updates
4. Test with the provided test suite

## Troubleshooting

### Common Issues

1. **SSL Certificate Errors**: Run `./generate_ssl.sh` for development
2. **Redis Connection**: Check `.env` file has correct `REDIS_PASSWORD`
3. **Backend Connectivity**: Verify `nginx/servers.conf` server addresses
4. **Port Conflicts**: Ensure ports 80, 443, 6379 are available

### Debug Commands

```bash
# Check container logs
docker-compose logs nginx_proxy
docker-compose logs redis

# Test Redis connection
docker-compose exec redis redis-cli -a $REDIS_PASSWORD ping

# Validate NGINX config
docker-compose exec nginx_proxy nginx -t
```

## License

This is a proof of concept project. Use at your own risk in production environments.
