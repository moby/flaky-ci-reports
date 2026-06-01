-- registry-net-error: TCP/TLS-level failures against a container registry
-- host where no HTTP status was returned. Surfaces in buildx bake / BuildKit
-- solve output, two shapes:
--
--   (a) `<OP> "https://<host>/...": read tcp <local>-><remote>: read: connection reset by peer`
--       (e.g. `failed to fetch oauth token: Post "https://auth.docker.io/token": read tcp ...`)
--       → registry-error:<host>:connection-reset
--
--   (b) `<OP> "https://<host>/...": net/http: TLS handshake timeout`
--       → registry-error:<host>:tls-handshake-timeout
--
-- Shares the `registry-error:<host>:<key>` namespace with registry-error.lua
-- (HTTP-status form) and docker-daemon-error.lua — same failure family, reports
-- group together; the reason token vs numeric status disambiguates the key.
--
-- No failed_steps gate: an authoritative, step-agnostic network cause (it's the
-- failure wherever the registry was hit). Overrides go-test-failure — a network
-- failure against the registry is the root cause; the per-test FAIL is noise.

overrides = { "go-test-failure" }

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    -- (a) connection-reset / read errors on a TCP socket. The "read tcp
    -- <addr>-><addr>" anchor disambiguates from generic "read: ...".
    do
      local host, reason = line:match(
        '%S+ "https?://([^/"]+)[^"]*": read tcp [%d.:%-> ]+: read: (.+)$')
      if host and reason then
        local token = "connection-reset"
        if not reason:match("connection reset by peer") then
          token = reason:gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
        end
        local k = host .. "|" .. token
        if not seen[k] then
          seen[k] = true
          table.insert(out, {
            unique_key = "registry-error:" .. host .. ":" .. token,
            name       = "Registry " .. host .. " network error: " .. reason,
            category   = "network",
            fields     = { host = host, reason = reason },
            evidence   = { { start_line = i, end_line = i } },
          })
        end
        goto continue
      end
    end

    -- (b) TLS handshake timeout.
    do
      local host = line:match(
        '%S+ "https?://([^/"]+)[^"]*": net/http: TLS handshake timeout')
      if host then
        local k = host .. "|tls-handshake-timeout"
        if not seen[k] then
          seen[k] = true
          table.insert(out, {
            unique_key = "registry-error:" .. host .. ":tls-handshake-timeout",
            name       = "Registry " .. host .. " TLS handshake timeout",
            category   = "network",
            fields     = { host = host, reason = "tls-handshake-timeout" },
            evidence   = { { start_line = i, end_line = i } },
          })
        end
      end
    end

    ::continue::
  end
  return out
end
