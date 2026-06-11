-- registry-net-error: TCP/TLS-level failures against a container
-- registry host where no HTTP status was returned. Surfaces in two
-- shapes inside buildx bake / BuildKit pull output:
--
--   (a) `failed to fetch oauth token: <OP> "https://<host>/...": read tcp <local>-><remote>: read: connection reset by peer`
--       → registry-error:<host>:connection-reset
--
--   (b) `<OP> "https://<host>/...": net/http: TLS handshake timeout`
--       → registry-error:<host>:tls-handshake-timeout
--
--   (c) `<OP> "https://<host>/...": dial tcp: lookup <host> on <resolver>:
--       ... connection refused` — DNS resolution failed (e.g. the in-cluster
--       CoreDNS resolver refusing the lookup during a kubernetes-driver test).
--       → registry-error:<host>:dns-lookup-failed
--
-- Shares the `registry-error:<host>:<key>` namespace with
-- registry-error.lua (HTTP-status form) and docker-daemon-error.lua
-- on purpose — same failure family, reports group together. The
-- reason token vs numeric status disambiguates without key collision.
--
-- Overrides go-test-failure: a network failure against the registry
-- is the root cause; the per-test FAIL is downstream noise.

overrides = { "go-test-failure" }

-- No failed_steps gate: authoritative registry TCP/TLS network cause — the real
-- failure wherever it surfaces. Reparse spans Build / signing / Set up QEMU.

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    -- (a) connection-reset / read errors on a TCP socket. Gate on a cheap
    -- plain find first — the `%S+ "https..."` pattern backtracks badly on long
    -- lines, and "read tcp " is a necessary literal so matches are unchanged.
    if line:find("read tcp ", 1, true) then
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

    -- (b) TLS handshake timeout (same plain-find gate; necessary literal).
    if line:find("TLS handshake timeout", 1, true) then
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

    -- (c) DNS resolution failure (cheap plain-find gate first).
    if line:find("dial tcp: lookup ", 1, true) then
      local host = line:match('dial tcp: lookup ([%w%.%-]+) on ')
      if host then
        local k = host .. "|dns-lookup-failed"
        if not seen[k] then
          seen[k] = true
          table.insert(out, {
            unique_key = "registry-error:" .. host .. ":dns-lookup-failed",
            name       = "Registry " .. host .. " DNS lookup failed",
            category   = "network",
            fields     = { host = host, reason = "dns-lookup-failed" },
            evidence   = { { start_line = i, end_line = i } },
          })
        end
        goto continue
      end
    end

    ::continue::
  end
  return out
end
