local session_id = ngx.ctx.session_id
local new_session_data = ngx.ctx.new_session_data

if not session_id or not new_session_data then
    return
end

local redis_timeout = os.getenv("REDIS_TIMEOUT") or 1000
local redis_host = os.getenv("REDIS_HOST") or "redis"
local redis_port = os.getenv("REDIS_PORT") or 6379
local redis_password = os.getenv("REDIS_PASSWORD") or ""
local redis_keepalive_timeout = os.getenv("REDIS_KEEPALIVE_TIMEOUT") or 10000
local redis_pool_size = os.getenv("REDIS_POOL_SIZE") or 200

local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(redis_timeout)

local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return
end

local res, err = red:auth(redis_password)
if not res then
    ngx.log(ngx.ERR, "Failed to authenticate with Redis: ", err)
    red:close()  -- Close on auth error
    return
end

local session_key = "session:" .. session_id
local ok, err
if new_session_data == "{}" or new_session_data == "null" then
    ok, err = red:expire(session_key, 0)
else
    ok, err = red:setex(session_key, 86400, new_session_data)
end

if not ok then
    ngx.log(ngx.ERR, "Redis operation failed: ", err)
    red:close()  -- Close on Redis error
    return
end

-- Use connection pooling for successful operations
local ok, err = red:set_keepalive(redis_keepalive_timeout, redis_pool_size)
if not ok then
    ngx.log(ngx.ERR, "Failed to set keepalive: ", err)
    red:close()
end
