local session_id = ngx.var.session_id
if not session_id then
    return
end

-- capture the session data
local new_session_data = ngx.header["X-New-Session-Data"]
if new_session_data then
    ngx.ctx.session_id = session_id
    ngx.ctx.new_session_data = new_session_data
end

-- Remove the header so it's not sent to client
ngx.header["X-New-Session-Data"] = nil
