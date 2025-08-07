--[[
This is the main access handler for the NGINX proxy.
It handles lookup of session data from Redis and sets
variables for use in requests.
]]
local redis = require "resty.redis"

-- Initialize variables
ngx.var.session_id = ""
ngx.var.session_data = ""

local redis_timeout = os.getenv("REDIS_TIMEOUT") or 1000
local redis_host = os.getenv("REDIS_HOST") or "redis"
local redis_port = os.getenv("REDIS_PORT") or 6379
local redis_password = os.getenv("REDIS_PASSWORD") or ""
local redis_keepalive_timeout = os.getenv("REDIS_KEEPALIVE_TIMEOUT") or 10000
local redis_pool_size = os.getenv("REDIS_POOL_SIZE") or 200

local red = redis:new()
red:set_timeout(redis_timeout)

local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return -- Continue without session management
end

if not redis_password then
    red:close()
    return -- No password configured
end

local res, err = red:auth(redis_password)
if not res then
    ngx.log(ngx.ERR, "Failed to authenticate with Redis: ", err)
    red:close()  -- Close on auth error, don't pool bad connection
    return
end

-- Get session from cookie
local session_id = ngx.var.cookie_PHPSESSID
if not session_id then
    local ok, err = red:set_keepalive(redis_keepalive_timeout, redis_pool_size)
    if not ok then
        ngx.log(ngx.ERR, "Failed to set keepalive: ", err)
    end
    return -- No session cookie
end

local session_data, err = red:get("session:" .. session_id)
if err then
    ngx.log(ngx.ERR, "Redis GET error: ", err)
    red:close()  -- Close on Redis error
    return
end

if not session_data or session_data == ngx.null then
    local ok, err = red:set_keepalive(redis_keepalive_timeout, redis_pool_size)
    if not ok then
        ngx.log(ngx.ERR, "Failed to set keepalive: ", err)
    end
    return -- No session data found
end

-- Success path - set session variables
ngx.var.session_id = session_id
ngx.var.session_data = session_data

-- Use connection pooling for successful operations
local ok, err = red:set_keepalive(redis_keepalive_timeout, redis_pool_size)
if not ok then
    ngx.log(ngx.ERR, "Failed to set keepalive: ", err)
    red:close()
end
