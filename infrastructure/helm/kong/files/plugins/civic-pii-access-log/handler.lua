-- Civic Commons civic-pii-access-log handler.
--
-- SECURITY CHECKPOINT (Task 4.2): Kong OSS 3.8's file-log/http-log plugins do
-- not expose a `log_serializer` field (verified against the 3.8 schema), so
-- this small custom plugin replaces the access log entirely:
--
--   * in the `log` phase it serializes the standard Kong log entry,
--   * scrubs PII via `civic.pii_scrubber` (phones, IPs, e-mails, blind hash
--     ids, URL-encoded phones),
--   * writes one JSON line to stdout (container logs -> Loki).
--
-- Request/response bodies and the Authorization header are never logged.
-- The default nginx access log must be disabled (KONG_PROXY_ACCESS_LOG=off)
-- so raw PII cannot leak through it instead.
local cjson = require "cjson"
local scrubber = require "civic.pii_scrubber"

local _M = {
  PRIORITY = 100,
  VERSION = "1.0.0",
}

function _M:log(conf)
  local entry = kong.log.serialize()
  local scrubbed = scrubber.serialize(conf, entry)
  io.stdout:write(cjson.encode(scrubbed) .. "\n")
  io.stdout:flush()
end

return _M
