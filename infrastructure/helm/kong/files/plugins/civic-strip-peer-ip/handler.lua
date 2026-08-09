-- Civic Commons civic-strip-peer-ip handler.
--
-- SECURITY CHECKPOINT (Task 4.2): Kong's nginx template unconditionally
-- re-injects the request's peer address upstream via
--   proxy_set_header X-Forwarded-For    $upstream_x_forwarded_for;
-- (and X-Forwarded-Proto/Host/Port/Path/Prefix) even after the
-- request-transformer strips client-supplied values. This tiny access-phase
-- plugin zeroes those Kong-managed nginx variables (set by the runloop,
-- PRIORITY 1000) so the upstream receives NO X-Forwarded-* headers at all.
--
-- X-Real-IP is deliberately NOT covered: the template hardcodes
--   proxy_set_header X-Real-IP $remote_addr;
-- which is not a Kong-managed variable. It can therefore only ever carry the
-- immediate trusted peer (load balancer) address — never a client-derived
-- value, because request-transformer strips any client-supplied X-Real-IP.
local _M = {
  -- Lower than the runloop handler (1000) so we run after it in `access`.
  PRIORITY = 10,
  VERSION = "1.0.0",
}

local function clear_forwarded_vars()
  ngx.var.upstream_x_forwarded_for = ""
  ngx.var.upstream_x_forwarded_proto = ""
  ngx.var.upstream_x_forwarded_host = ""
  ngx.var.upstream_x_forwarded_port = ""
  ngx.var.upstream_x_forwarded_path = ""
  ngx.var.upstream_x_forwarded_prefix = ""
end

function _M:access()
  clear_forwarded_vars()
end

-- Safety net: if the runloop ever recomputes the forwarded variables after
-- the access phase, the balancer phase clears them again before proxy_pass.
function _M:balancer()
  clear_forwarded_vars()
end

return _M
