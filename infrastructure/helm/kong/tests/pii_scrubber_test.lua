-- Unit tests for the Civic Commons Kong PII scrubber.
-- Runs with a plain `lua` interpreter (no Kong runtime required):
--   cd infrastructure/helm/kong/tests && lua pii_scrubber_test.lua
package.path = "../files/?.lua;" .. package.path

local scrubber = require("pii_scrubber")

local failures = 0
local function expect(name, cond)
  if cond then
    print("PASS  " .. name)
  else
    print("FAIL  " .. name)
    failures = failures + 1
  end
end

local RED = "[REDACTED]"

-- --- PII redaction ---------------------------------------------------------
expect("E.164 phone redacted", scrubber.scrub("call +14155552671 now") == "call " .. RED .. " now")
expect("phone with separators redacted", scrubber.scrub("+91-98765-43210") == RED)
expect("URL-encoded E.164 redacted", scrubber.scrub("tel=%2B14155552671") == "tel=" .. RED)
expect("IPv4 redacted", scrubber.scrub("from 203.0.113.7") == "from " .. RED)
expect("email redacted", scrubber.scrub("mail foo.bar@example.com x") == "mail " .. RED .. " x")
expect("blind hash redacted",
  scrubber.scrub("id " .. string.rep("a1", 32) .. " done") == "id " .. RED .. " done")
expect("benign text untouched", scrubber.scrub("hello world 42") == "hello world 42")
expect("nil passthrough", scrubber.scrub(nil) == nil)

-- --- serializer output -----------------------------------------------------
local entry = {
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
local out = scrubber.serialize({}, entry)

expect("serializer scrubs querystring values", out.querystring.phone == RED)
expect("serializer keeps benign querystring", out.querystring.limit == "10")
expect("serializer scrubs client_ip", out.client_ip == RED)
expect("serializer scrubs uri", out.uri == "/v1/posts?phone=" .. RED)
expect("serializer keeps method", out.method == "GET")
expect("serializer keeps status", out.status == 200)
expect("serializer keeps request_id", out.request_id == "req-123")
expect("serializer keeps consumer username", out.consumer == "blindhash123")
expect("serializer keeps latency", out.latency.request == 12)
expect("serializer emits timestamp", type(out.timestamp) == "string")

print(failures == 0 and "ALL PII SCRUBBER TESTS PASSED" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
