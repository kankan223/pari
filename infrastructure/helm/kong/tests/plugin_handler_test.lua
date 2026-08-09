-- Unit tests for the civic-pii-access-log plugin handler.
-- Runs with a plain `lua` interpreter (no Kong runtime required):
--   cd infrastructure/helm/kong/tests && lua plugin_handler_test.lua
-- Stubs the `kong` global and the `cjson` module, then captures io.stdout.
package.path = "../files/?.lua;../files/plugins/civic-pii-access-log/?.lua;" .. package.path

local failures = 0
local function expect(name, cond)
  if cond then
    print("PASS  " .. name)
  else
    print("FAIL  " .. name)
    failures = failures + 1
  end
end

-- Stub cjson BEFORE the handler is required (handler.lua does require "cjson").
package.preload["cjson"] = function()
  return {
    encode = function(t)
      return "uri=" .. tostring(t.uri)
          .. " ip=" .. tostring(t.client_ip)
          .. " qs=" .. tostring(t.querystring and t.querystring.phone or "?")
    end,
  }
end

-- Stub the kong global BEFORE the handler is required.
kong = {
  log = {
    serialize = function()
      return {
        started_at = 0,
        request = {
          method = "GET",
          uri = "/v1/posts?phone=%2B14155552671",
          path = "/v1/posts",
          querystring = { phone = "+14155552671", limit = "10" },
          headers = { ["kong-request-id"] = "req-123" },
        },
        response = { status = 200 },
        client_ip = "198.51.100.9",
        service = { name = "civic-api" },
        route = { name = "civic-api-route" },
        consumer = { username = "blindhash123" },
        latencies = { request = 12, kong = 3, proxy = 9 },
      }
    end,
  },
}

-- Stub the module name the handler requires (civic.pii_scrubber) so it
-- resolves to the real scrubber module in files/pii_scrubber.lua.
package.preload["civic.pii_scrubber"] = function() return require("pii_scrubber") end

-- Capture io.stdout writes.
local lines = {}
local real_stdout = io.stdout
io.stdout = {
  write = function(_, s) lines[#lines + 1] = s end,
  flush = function() end,
}

local handler = require "handler"
local inst = setmetatable({}, { __index = handler })
inst:log({})

io.stdout = real_stdout
local out = table.concat(lines, "")

expect("handler wrote a log line", #lines >= 1)
expect("handler scrubbed URL-encoded phone in uri", out:find("uri=/v1/posts?phone=[REDACTED]", 1, true) ~= nil)
expect("handler scrubbed decoded phone in querystring", out:find("qs=[REDACTED]", 1, true) ~= nil)
expect("handler scrubbed client_ip", out:find("ip=[REDACTED]", 1, true) ~= nil)

print("handler output: " .. out)

print(failures == 0 and "ALL PLUGIN HANDLER TESTS PASSED" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
