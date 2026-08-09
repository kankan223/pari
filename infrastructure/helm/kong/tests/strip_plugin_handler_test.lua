-- Unit tests for the civic-strip-peer-ip plugin handler.
-- Runs with a plain `lua` interpreter (no Kong runtime required):
--   cd infrastructure/helm/kong/tests && lua strip_plugin_handler_test.lua
package.path = "../files/plugins/civic-strip-peer-ip/?.lua;" .. package.path

local failures = 0
local function expect(name, cond)
  if cond then
    print("PASS  " .. name)
  else
    print("FAIL  " .. name)
    failures = failures + 1
  end
end

-- Stub ngx: capture writes to ngx.var (the runloop-seeded forwarded vars).
local var = {}
ngx = {
  var = var,
  log = function() end,
  ERR = 8,
}

local handler = require "handler"

expect("handler PRIORITY lower than runloop (1000)", handler.PRIORITY == 10)
expect("handler exposes VERSION", type(handler.VERSION) == "string")

local inst = setmetatable({}, { __index = handler })

-- Seed the vars exactly as Kong's runloop would (untrusted-peer case).
var.upstream_x_forwarded_for = "203.0.113.66, 172.17.0.1"
var.upstream_x_forwarded_proto = "https"
var.upstream_x_forwarded_host = "civic.example"
var.upstream_x_forwarded_port = "443"
var.upstream_x_forwarded_path = "/v1"
var.upstream_x_forwarded_prefix = "/v1"

inst:access()

expect("access clears upstream_x_forwarded_for", var.upstream_x_forwarded_for == "")
expect("access clears upstream_x_forwarded_proto", var.upstream_x_forwarded_proto == "")
expect("access clears upstream_x_forwarded_host", var.upstream_x_forwarded_host == "")
expect("access clears upstream_x_forwarded_port", var.upstream_x_forwarded_port == "")
expect("access clears upstream_x_forwarded_path", var.upstream_x_forwarded_path == "")
expect("access clears upstream_x_forwarded_prefix", var.upstream_x_forwarded_prefix == "")

-- Balancer safety net must re-clear if the runloop recomputed the values.
var.upstream_x_forwarded_for = "172.17.0.1"
var.upstream_x_forwarded_proto = "http"
inst:balancer()
expect("balancer re-clears upstream_x_forwarded_for", var.upstream_x_forwarded_for == "")
expect("balancer re-clears upstream_x_forwarded_proto", var.upstream_x_forwarded_proto == "")

print(failures == 0 and "ALL STRIP PLUGIN TESTS PASSED" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
