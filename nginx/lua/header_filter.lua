local session_id = ngx.var.session_id
if not session_id then
    return
end

local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(redis_timeout)

local ok = red:connect(redis_host, redis_port)
if ok then
    red:auth(os.getenv("REDIS_PASSWORD"))

    local session_key = "session:" .. session_id

    -- Lack of session data indicates an expired session
    local new_session_data = ngx.header["X-New-Session-Data"]
    if not new_session_data or new_session_data == "{}" or new_session_data == "null" then
        red:expire(session_key, 0)
    else
        red:setex(session_key, 86400, new_session_data)
    end

    red:close()

    -- Remove the header so it's not sent to client
    ngx.header["X-New-Session-Data"] = nil
end
