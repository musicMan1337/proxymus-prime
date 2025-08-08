<?php
// Example backend server that works with the NGINX proxy

// Configure PHP to use Redis for session storage
ini_set('session.save_handler', 'redis');
ini_set('session.save_path', 'tcp://' . ($_ENV['REDIS_HOST'] ?? 'redis') . ':' . ($_ENV['REDIS_PORT'] ?? '6379') . '?auth=' . ($_ENV['REDIS_PASSWORD'] ?? ''));
ini_set('session.gc_maxlifetime', 86400); // 24 hours
ini_set('session.cookie_lifetime', 86400);
ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_secure', isset($_SERVER['HTTPS']) ? 1 : 0);
ini_set('session.cookie_samesite', 'Strict');

// Start session
session_start();

header('Content-Type: application/json');

// Get server information
$serverId = $_ENV['SERVER_ID'] ?? 'unknown';

// Handle different endpoints
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

switch ($path) {
    case '/':
        touchSession($serverId);

        // Basic server info with session data
        echo json_encode([
            'server_id' => $serverId,
            'timestamp' => time(),
            'session_id' => session_id(),
            'session_data' => $_SESSION,
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
        touchSession($serverId);
        handleSession($serverId);
        break;

    case '/login':
        handleLogin($serverId);
        break;

    case '/logout':
        handleLogout($serverId);
        break;

    case '/echo':
        // Echo endpoint for testing request forwarding
        $body = file_get_contents('php://input');
        echo json_encode([
            'method' => $method,
            'body' => $body,
            'server_id' => $serverId,
            'headers' => getallheaders()
        ], JSON_PRETTY_PRINT);
        break;

    case '/nonexistent':
        // Explicit 404 for testing
        http_response_code(404);
        echo json_encode(['error' => 'Endpoint not found']);
        break;

    default:
        // For unknown paths, return 404 instead of 200
        http_response_code(404);
        echo json_encode(['error' => 'Endpoint not found']);
        break;
}

function touchSession($serverId)
{
    $_SESSION['counter'] = ($_SESSION['counter'] ?? 0) + 1;
    $_SESSION['last_access'] = time();
    $_SESSION['server_id'] = $serverId;
}

function handleSession($serverId)
{
    global $method;

    if ($method === 'POST') {
        // Update session with new data
        $input = json_decode(file_get_contents('php://input'), true);

        if ($input) {
            foreach ($input as $key => $value) {
                $_SESSION[$key] = $value;
            }
        }

        $_SESSION['last_updated'] = time();

        echo json_encode([
            'session_id' => session_id(),
            'session_data' => $_SESSION,
            'action' => 'updated',
            'server_id' => $serverId
        ], JSON_PRETTY_PRINT);
    } else {
        // Return current session
        echo json_encode([
            'session_id' => session_id(),
            'session_data' => $_SESSION,
            'server_id' => $serverId
        ], JSON_PRETTY_PRINT);
    }
}

function handleLogin($serverId)
{
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';

    if ($username && $password) {
        // Store user data in session
        $_SESSION['user_id'] = $username;
        $_SESSION['logged_in'] = true;
        $_SESSION['login_time'] = time();
        $_SESSION['server_id'] = $serverId;

        echo json_encode([
            'success' => true,
            'message' => 'Logged in successfully',
            'session_id' => session_id(),
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

function handleLogout($serverId)
{
    if (session_id()) {
        // Clear session data
        session_destroy();

        // Clear the cookie
        setcookie(session_name(), '', time() - 3600, '/');

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
