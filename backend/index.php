<?php
// Example backend server that works with the NGINX proxy

header('Content-Type: application/json');

// Get server information
$serverId = $_ENV['SERVER_ID'] ?? 'unknown';
$redisHost = $_ENV['REDIS_HOST'] ?? 'redis';

// Function to connect to Redis
function connectRedis($host = 'redis', $port = 6379)
{
    try {
        $redis = new Redis();
        $redis->connect($host, $port);
        return $redis;
    } catch (Exception $e) {
        return null;
    }
}

// Get session data from NGINX headers
$sessionId = $_SERVER['HTTP_X_SESSION_ID'] ?? null;
$sessionData = $_SERVER['HTTP_X_SESSION_DATA'] ?? null;

// Parse session data if available
$session = [];
if ($sessionData && $sessionData !== 'nil') {
    $session = json_decode($sessionData, true) ?: [];
}

// Handle different endpoints
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

switch ($path) {
    case '/':
    case '/info':
        // Basic server info
        echo json_encode([
            'server_id' => $serverId,
            'timestamp' => time(),
            'session_id' => $sessionId,
            'session_data' => $session,
            'method' => $method,
            'headers' => getallheaders()
        ], JSON_PRETTY_PRINT);
        break;

    case '/health':
        // Health check endpoint
        http_response_code(200);
        echo json_encode(['status' => 'healthy', 'server_id' => $serverId]);
        break;

    case '/session':
        handleSession($sessionId, $session, $serverId, $redisHost);
        break;

    case '/login':
        handleLogin($sessionId, $serverId, $redisHost);
        break;

    case '/logout':
        handleLogout($sessionId, $serverId, $redisHost);
        break;

    default:
        http_response_code(404);
        echo json_encode(['error' => 'Endpoint not found']);
        break;
}

function handleSession($sessionId, $session, $serverId, $redisHost)
{
    global $method;

    if ($method === 'POST') {
        // Create or update session
        $input = json_decode(file_get_contents('php://input'), true);

        if (!$sessionId) {
            // Generate new session ID
            $sessionId = md5(uniqid(rand(), true));
            setcookie('PHPSESSID', $sessionId, time() + 86400, '/');
        }

        // Merge new data with existing session
        $newSession = array_merge($session, $input ?: []);
        $newSession['last_updated'] = time();
        $newSession['server_id'] = $serverId;

        // Send new session data back to NGINX via header
        header('X-New-Session-Data: ' . json_encode($newSession));

        echo json_encode([
            'session_id' => $sessionId,
            'session_data' => $newSession,
            'action' => 'updated',
            'server_id' => $serverId
        ], JSON_PRETTY_PRINT);
    } else {
        // Return current session
        echo json_encode([
            'session_id' => $sessionId,
            'session_data' => $session,
            'server_id' => $serverId
        ], JSON_PRETTY_PRINT);
    }
}

function handleLogin($sessionId, $serverId, $redisHost)
{
    $input = json_decode(file_get_contents('php://input'), true);
    $username = $input['username'] ?? '';
    $password = $input['password'] ?? '';

    // Simple authentication (in real app, check against database)
    if ($username && $password) {
        if (!$sessionId) {
            $sessionId = md5(uniqid(rand(), true));
            setcookie('PHPSESSID', $sessionId, time() + 86400, '/');
        }

        $sessionData = [
            'user_id' => $username,
            'logged_in' => true,
            'login_time' => time(),
            'server_id' => $serverId
        ];

        // Send session data to NGINX
        header('X-New-Session-Data: ' . json_encode($sessionData));

        echo json_encode([
            'success' => true,
            'message' => 'Logged in successfully',
            'session_id' => $sessionId,
            'user_id' => $username,
            'server_id' => $serverId
        ], JSON_PRETTY_PRINT);
    } else {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Username and password required'
        ]);
    }
}

function handleLogout($sessionId, $serverId, $redisHost)
{
    if ($sessionId) {
        // Clear session
        header('X-New-Session-Data: {}');
        setcookie('PHPSESSID', '', time() - 3600, '/');

        echo json_encode([
            'success' => true,
            'message' => 'Logged out successfully',
            'server_id' => $serverId
        ], JSON_PRETTY_PRINT);
    } else {
        echo json_encode([
            'success' => false,
            'message' => 'No active session',
            'server_id' => $serverId
        ]);
    }
}

// Add visit counter to demonstrate session persistence
if ($sessionId && $path === '/') {
    $visits = ($session['visit_count'] ?? 0) + 1;
    $newSession = array_merge($session, [
        'visit_count' => $visits,
        'last_visit' => time(),
        'server_id' => $serverId
    ]);

    header('X-New-Session-Data: ' . json_encode($newSession));
}
