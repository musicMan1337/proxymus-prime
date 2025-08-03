local redis = require "resty.redis"
local red = redis:new()

-- Set timeout
red:set_timeout(redis_timeout)

-- Connect to Redis
local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return
end

-- Get session ID from cookie or header
local session_id = ngx.var.cookie_PHPSESSID or ngx.var.http_x_session_id

if session_id then
    ngx.var.session_id = session_id

    -- Get session data from Redis
    local session_data = red:get("session:" .. session_id)
    if session_data and session_data ~= ngx.null then
        ngx.var.session_data = session_data

        -- Set headers with session data for backend
        ngx.req.set_header("X-Session-Id", session_id)
        ngx.req.set_header("X-Session-Data", session_data)
    end
end

-- Close Redis connection
red:close()