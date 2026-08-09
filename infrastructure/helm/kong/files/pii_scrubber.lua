-- Civic Commons PII-scrubbing log serializer for Kong access logs.
--
-- SECURITY CHECKPOINT (Task 4.2): every access-log entry written by the
-- file-log plugin is passed through this serializer, which redacts E.164
-- phone numbers, IPv4/IPv6 addresses, e-mail addresses and 64-character hex
-- blind_hash_id values before the line reaches the sink (stdout -> Loki).
-- Request and response BODIES are never logged.
--
-- Mounted at /usr/local/share/lua/5.1/civic/pii_scrubber.lua and enabled via
-- `config.log_serializer: civic.pii_scrubber` on the file-log plugin.
--
-- The module is dependency-free (no `require("kong")`) so it can be unit
-- tested with a plain `lua` interpreter (see ../tests/pii_scrubber_test.lua).

local _M = {}

local REDACTED = "[REDACTED]"

-- Lua patterns (not regular expressions). Most-specific matchers first so a
-- value is consumed by the correct rule.
local PII_PATTERNS = {
  -- 64-hex-character blind_hash_id (Argon2id output, hex-encoded)
  { "%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x", REDACTED },
  -- E.164 phone numbers: '+' prefix followed by digits and separators.
  -- (Canonical E.164 contains no spaces; `{n,m}` quantifiers are avoided for
  -- LuaJIT compatibility. May also match version-like strings such as
  -- "+1.2.3" — acceptable over-redaction for a PII scrubber.)
  { "%+[%d%-%.%(%)]+", REDACTED },
  -- URL-encoded E.164 (e.g. %2B14155552671 in raw URIs/querystrings;
  -- '+' is 0x2B, so the encoded form is '%2B')
  { "%%2[bB][%d%-%.%(%)]+", REDACTED },
  -- IPv4 addresses
  { "%d+%.%d+%.%d+%.%d+", REDACTED },
  -- IPv6 addresses (hex groups joined by colons). May also match clock
  -- times like "12:30:45" — intentional over-redaction for a PII scrubber.
  { "[%x:]+:[%x:]+:[%x:]+", REDACTED },
  -- E-mail addresses
  { "[%w%.%%%+%-_]+@[%w%.%-_]+%.[%a][%a]+", REDACTED },
}

-- Redacts every PII pattern found in `value`.
function _M.scrub(value)
  if value == nil then
    return nil
  end
  local s = tostring(value)
  for i = 1, #PII_PATTERNS do
    s = (s:gsub(PII_PATTERNS[i][1], PII_PATTERNS[i][2]))
  end
  return s
end

local function scrub_value(v)
  if type(v) == "string" then
    return _M.scrub(v)
  elseif type(v) == "table" then
    local out = {}
    for k, val in pairs(v) do
      out[k] = scrub_value(val)
    end
    return out
  end
  return v
end

-- Kong invokes serialize(conf, entry) on the standard log-entry table.
-- Only minimal, PII-scrubbed fields are emitted — never request/response
-- bodies, and never the Authorization header.
function _M.serialize(conf, entry)
  local req = entry.request or {}
  local res = entry.response or {}
  local lat = entry.latencies or {}

  return {
    timestamp  = os.date("!%Y-%m-%dT%H:%M:%SZ", entry.started_at or os.time()),
    request_id = req.headers and (req.headers["kong-request-id"] or req.headers["Kong-Request-ID"]),
    method     = req.method,
    uri        = _M.scrub(req.uri),
    path       = _M.scrub(req.path),
    querystring = scrub_value(req.querystring),
    status     = res.status,
    latency    = { request = lat.request, kong = lat.kong, proxy = lat.proxy },
    client_ip  = _M.scrub(entry.client_ip),
    service    = entry.service and entry.service.name,
    route      = entry.route and entry.route.name,
    consumer   = entry.consumer and entry.consumer.username,
  }
end

return _M
