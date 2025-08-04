local redis = require "resty.redis"
local red = redis:new()

red:set_timeout(redis_timeout)

local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return
end

-- Authenticate with Redis
local res, err = red:auth(os.getenv("REDIS_PASSWORD"))
if not res then
    ngx.log(ngx.ERR, "Failed to authenticate with Redis: ", err)
    return
end

-- Validate session ID format (64 hex characters)
local function validate_session_id(sid)
    if not sid then return false end
    if string.len(sid) ~= 64 then return false end
    if not string.match(sid, "^[a-fA-F0-9]+$") then return false end
    return true
end

-- Get session ID from cookie or header
local session_id = ngx.var.cookie_PHPSESSID or ngx.var.http_x_session_id

if session_id and validate_session_id(session_id) then
    ngx.var.session_id = session_id

    -- Sanitize session data before setting headers
    local session_data = red:get("session:" .. session_id)
    if session_data and session_data ~= ngx.null then
        -- Basic sanitization - remove control characters
        session_data = string.gsub(session_data, "[\r\n\t]", "")
        ngx.var.session_data = session_data

        ngx.req.set_header("X-Session-Id", session_id)
        ngx.req.set_header("X-Session-Data", session_data)
    end
end

-- Close Redis connection
red:close()
