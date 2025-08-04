local session_id = ngx.var.session_id
if not session_id then
    return
end

-- Check if backend sent new session data
local new_session_data = ngx.header["X-New-Session-Data"]
if new_session_data then
    local redis = require "resty.redis"
    local red = redis:new()
    red:set_timeout(redis_timeout)

    local ok = red:connect(redis_host, redis_port)
    if ok then
        -- Authenticate with Redis
        red:auth(os.getenv("REDIS_PASSWORD"))

        red:setex("session:" .. session_id, 86400, new_session_data)
        red:close()
    end

    -- Remove the header so it's not sent to client
    ngx.header["X-New-Session-Data"] = nil
end
