--[[
This is the main access handler for the NGINX proxy.
It handles lookup of session data from Redis and sets
variables for use in requests.
]]
local redis = require "resty.redis"

-- Initialize variables
ngx.var.session_id = ""
ngx.var.session_data = ""

local red = redis:new()
red:set_timeout(1000)

local ok, err = red:connect("redis", 6379)
if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return -- Continue without session management
end

local redis_password = os.getenv("REDIS_PASSWORD")
if not redis_password then
    red:close()
    return -- No password configured
end

local res, err = red:auth(redis_password)
if not res then
    ngx.log(ngx.ERR, "Failed to authenticate with Redis: ", err)
    red:close()
    return
end

-- Get session from cookie
local session_id = ngx.var.cookie_PHPSESSID
if not session_id then
    red:close()
    return -- No session cookie
end

local session_data, err = red:get("session:" .. session_id)
if not session_data or session_data == ngx.null then
    red:close()
    return -- No session data found
end

-- Success path - set session variables
ngx.var.session_id = session_id
ngx.var.session_data = session_data

red:close()
