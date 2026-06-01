-- docker-daemon-error: dockerd / docker pull surfaces registry-side
-- failures in five message shapes. All are *registry-side* causes;
-- shares `registry-error:<host>:<status_or_marker>` key namespace with
-- registry-error.lua and docker-pull-blocked.lua.
--
--   A. URL form (full URL + HTTP status):
--      Error response from daemon: <OP> "https://<host>/<path>": received unexpected HTTP status: <CODE> <reason>
--      → registry-error:<host>:<code>
--
--   B. Bare HTTP-status form (no URL):
--      Error response from daemon: received unexpected HTTP status: <CODE> <reason>
--      → registry-error:<code>
--
--   C. Nested-Get timeout (registry probe + auth/token fetch):
--      Error response from daemon: <op1> "<u1>": <op2> "https://<inner_host>/<path>": (context deadline exceeded | net/http: ...Client.Timeout)
--      Both suffixes unify to `:timeout`.
--      → registry-error:<inner_host>:timeout
--
--   D. Auth-required form (no URL, no HTTP status — just a text reason):
--      Error response from daemon: unauthorized: authentication required
--      → docker-daemon-auth-required
--
--   E. Single-level Get timeout (no nested URL):
--      Error response from daemon: <OP> "https://<host>/<path>": (context deadline exceeded | net/http: ...Client.Timeout)
--      Hit when `docker pull` or `docker buildx setup-qemu` itself times
--      out the very first request (no inner auth fetch needed yet).
--      → registry-error:<host>:timeout — same key as C, since the
--      user-facing surface is identical.
--
-- Overrides go-test-failure: when the daemon is the root cause of a
-- test failure, the per-test FAIL is downstream noise.

overrides = { "go-test-failure" }

-- No failed_steps gate: authoritative daemon/registry cause — the real failure
-- wherever it surfaces. Reparse spans Set up Buildx / Build / Set up QEMU / Test.

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- C. Nested form first so its leading op token doesn't get matched by A.
    do
      local host, suffix = line:match(
        'Error response from daemon: %S+ "https?://[^"]+": %S+ "https?://([^/"]+)[^"]*": (.+)$')
      if host and (suffix:match("context deadline exceeded") or suffix:match("Client%.Timeout")) then
        return {
          unique_key = "registry-error:" .. host .. ":timeout",
          name       = "Registry " .. host .. " timeout",
          category   = "network",
          fields     = { host = host, reason = "timeout" },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end

    -- A. URL form with HTTP status.
    do
      local op, host, status = line:match(
        'Error response from daemon: (%S+) "https?://([^/"]+)[^"]*": received unexpected HTTP status: (%d+)')
      if op and op ~= "received" then
        return {
          unique_key = "registry-error:" .. host .. ":" .. status,
          name       = "Registry " .. host .. " returned HTTP " .. status,
          category   = "network",
          fields     = { operation = op, host = host, status = status },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end

    -- B. Bare HTTP-status form.
    do
      local status = line:match(
        "Error response from daemon: received unexpected HTTP status: (%d+)")
      if status then
        return {
          unique_key = "registry-error:" .. status,
          name       = "Registry returned HTTP " .. status,
          category   = "network",
          fields     = { status = status },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end

    -- D. Auth-required form.
    do
      if line:match("Error response from daemon: unauthorized: authentication required") then
        return {
          unique_key = "docker-daemon-auth-required",
          name       = "docker daemon: unauthorized (authentication required)",
          category   = "network",
          fields     = { reason = "unauthorized" },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end

    -- E. Single-level Get timeout (no nested URL — must come AFTER C, which
    -- matches the two-URL form. The op pattern `%S+` lets either match in
    -- principle, but C's middle `%S+ "https?://[^"]+":` segment is what
    -- distinguishes them).
    do
      local op, host, suffix = line:match(
        'Error response from daemon: (%S+) "https?://([^/"]+)[^"]*": (.+)$')
      if op and op ~= "received" and host and
         (suffix:match("context deadline exceeded") or suffix:match("Client%.Timeout")) then
        return {
          unique_key = "registry-error:" .. host .. ":timeout",
          name       = "Registry " .. host .. " timeout (single request)",
          category   = "network",
          fields     = { operation = op, host = host, reason = "timeout" },
          evidence   = { { start_line = i, end_line = i } },
        }
      end
    end
  end
  return nil
end
