local redis = require "resty.redis"
local cjson = require "cjson"

-------------------------------------------
-- Redis helpers
-------------------------------------------
local function connect_redis()
  local red = redis:new()
  red:set_timeout(1000) -- 1 second

  local ok, err = red:connect("redis", 6379)
  if not ok then
    ngx.log(ngx.ERR, "Failed to connect to Redis: ", err)
    return nil, err
  end

  return red, nil
end

local function generate_session_id()
  local random = ngx.var.request_time .. ngx.var.remote_addr .. math.random(1000000)
  return ngx.md5(random)
end

-------------------------------------------
-- Result helpers
-------------------------------------------
local function send_error(status, message)
    ngx.status = status
    ngx.say(cjson.encode({error = message}))
end

local function send_success(data)
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(data))
end

-------------------------------------------
-- Endpoint handlers
-------------------------------------------
-- GET with session_id
local function get_session()
    local session_id = ngx.var.arg_session_id or ngx.var.cookie_PHPSESSID

    if not session_id then
        send_error(400, "No session ID provided")
        return
    end

    local red = connect_redis()
    if not red then
        send_error(500, "Redis connection failed")
        return
    end

    local session_data = red:get("session:" .. session_id)
    red:close()

    if session_data == ngx.null then
        send_error(404, "Session not found")
        return
    end

    send_success({
        session_id = session_id,
        data = session_data,
        timestamp = ngx.time()
    })
end

-- POST
local function create_session()
    local session_id = generate_session_id()
    local session_data = ngx.var.request_body or "{}"

    -- Parse JSON body if provided
    if ngx.var.request_body then
        local ok, parsed = pcall(cjson.decode, ngx.var.request_body)
        if ok then
            session_data = cjson.encode(parsed)
        end
    end

    local red = connect_redis()
    if not red then
        send_error(500, "Redis connection failed")
        return
    end

    -- Store session with 24 hour TTL
    local ok = red:setex("session:" .. session_id, 86400, session_data)
    red:close()

    if not ok then
        send_error(500, "Failed to create session")
        return
    end

    send_success({
        session_id = session_id,
        data = session_data,
        expires_in = 86400,
        timestamp = ngx.time()
    })
end

-- PUT
local function update_session()
    local session_id = ngx.var.arg_session_id
    local session_data = ngx.var.request_body

    if not session_id then
        send_error(400, "No session ID provided")
        return
    end

    if not session_data then
        send_error(400, "No session data provided")
        return
    end

    local red = connect_redis()
    if not red then
        send_error(500, "Redis connection failed")
        return
    end

    -- Check if session exists
    local exists = red:exists("session:" .. session_id)
    if exists == 0 then
        red:close()
        send_error(404, "Session not found")
        return
    end

    -- Update session with new TTL
    local ok = red:setex("session:" .. session_id, 86400, session_data)
    red:close()

    if not ok then
        send_error(500, "Failed to update session")
        return
    end

    send_success({
        session_id = session_id,
        data = session_data,
        updated = true,
        timestamp = ngx.time()
    })
end

-- DELETE
local function delete_session()
    local session_id = ngx.var.arg_session_id

    if not session_id then
        send_error(400, "No session ID provided")
        return
    end

    local red = connect_redis()
    if not red then
        send_error(500, "Redis connection failed")
        return
    end

    local result = red:del("session:" .. session_id)
    red:close()

    if result ~= 1 then
        send_error(404, "Session not found")
        return
    end

    send_success({
        session_id = session_id,
        deleted = true,
        timestamp = ngx.time()
    })
end

-- GET no session_id
local function list_sessions()
    local red = connect_redis()
    if not red then
        send_error(500, "Redis connection failed")
        return
    end

    local keys = red:keys("session:*")
    if not keys then
        red:close()
        send_error(500, "Failed to retrieve sessions")
        return
    end

    local sessions = {}
    for _, key in ipairs(keys) do
        local session_id = string.gsub(key, "session:", "")
        local ttl = red:ttl(key)
        local data = red:get(key)

        sessions[session_id] = {
            expires_in = ttl,
            data = data
        }
    end

    red:close()

    send_success({
        sessions = sessions,
        count = #keys,
        timestamp = ngx.time()
    })
end

-- Main request handler
ngx.req.read_body()

local method = ngx.var.request_method

if method == "GET" then
    if ngx.var.arg_session_id then
        get_session()
    else
        list_sessions()
    end
elseif method == "POST" then
    create_session()
elseif method == "PUT" then
    update_session()
elseif method == "DELETE" then
    delete_session()
else
    send_error(405, "Method not allowed")
end