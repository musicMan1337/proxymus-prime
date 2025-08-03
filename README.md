# NGINX Redis Proxy POC

A proof of concept for a generic NGINX load balancer with Redis session management, designed for zero-downtime rolling deployments.

## Features

- **Load Balancing**: NGINX proxy with configurable upstream servers
- **Session Management**: Redis-backed session storage with automatic session forwarding
- **Zero Downtime Deployments**: Rolling update support with health checks
- **Generic Design**: Easily adaptable for different backend technologies
- **Session Persistence**: Sessions survive server restarts and deployments
- **Health Monitoring**: Built-in health checks and monitoring endpoints

## Architecture

```
[Client] → [NGINX Proxy] → [Redis] → [Backend Servers]
                ↓
         Session Management
         Load Balancing
         Health Checks
```

## Quick Start

1. **Clone and Setup**

   ```bash
   git clone <this-repo>
   cd nginx-redis-proxy

   # Create required directories
   mkdir -p nginx/conf.d nginx/lua logs backend
   ```

2. **Start the Stack**

   ```bash
   docker-compose up -d
   ```

3. **Test the Setup**

   ```bash
   # Check if all services are running
   docker-compose ps

   # Test load balancer
   curl http://localhost/

   # Test session management
   curl -X POST http://localhost/session \
        -H "Content-Type: application/json" \
        -d '{"username": "test", "data": "session_data"}'
   ```

## Session Management

### How It Works

1. **Session Creation**: Backend servers can create sessions by sending `X-New-Session-Data` header
2. **Session Storage**: Sessions are stored in Redis with configurable TTL (default: 24 hours)
3. **Session Forwarding**: NGINX automatically forwards session data to backend servers
4. **Session Updates**: Backend servers can update session data during requests

### Session API

- `GET /session?session_id=<id>` - Retrieve session data
- `POST /session` - Create new session
- `PUT /session?session_id=<id>` - Update existing session
- `DELETE /session?session_id=<id>` - Delete session

### PHP Integration Example

```php
// Get session from NGINX headers
$sessionId = $_SERVER['HTTP_X_SESSION_ID'] ?? null;
$sessionData = $_SERVER['HTTP_X_SESSION_DATA'] ?? null;

// Update session (sent back to NGINX)
header('X-New-Session-Data: ' . json_encode($newSessionData));
```

## Rolling Deployments

### Deployment Process

```bash
# Run rolling deployment
./deploy.sh v1.2.3
```

The deployment script:

1. Removes one server from load balancer
2. Updates the server
3. Performs health checks
4. Adds server back to load balancer
5. Repeats for all servers

### Zero Downtime Features

- **Load Balancer Management**: Automatically removes/adds servers during updates
- **Health Checks**: Ensures servers are healthy before adding back to rotation
- **Connection Draining**: Waits
