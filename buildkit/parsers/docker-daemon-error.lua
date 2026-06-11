-- docker-daemon-error: dockerd / docker pull surfaces registry-side
-- failures in four message shapes. All four are *registry-side*
-- causes (registry returned 5xx, auth host timed out, etc.) — same
-- failure family as BuildKit-side errors, so this parser shares the
-- `registry-error:<host>:<status_or_marker>` key namespace with
-- registry-error.lua. Parser file is the "how" of extraction; the
-- key is the "what" of the cause.
--
--   A. URL form (full URL + HTTP status):
--      ERROR: Error response from daemon: <OP> "https://<host>/<path>": received unexpected HTTP status: <CODE> <reason>
--      → registry-error:<host>:<code>
--
--   B. Bare form (no URL, just status — daemon swallowed the URL):
--      Error response from daemon: received unexpected HTTP status: <CODE> <reason>
--      → registry-error:<code>
--
--   C. Nested-Get timeout (registry probe + auth/token fetch):
--      Error response from daemon: <op1> "<u1>": <op2> "https://<inner_host>/<path>": <suffix>
--      <suffix> is either "context deadline exceeded" (server-side
--      deadline) or "net/http: ...Client.Timeout exceeded ..."
--      (client-side timeout). Both unify to ':timeout' — the inner
--      host is the one that didn't respond in time, the surface to
--      the user is the same.
--      → registry-error:<inner_host>:timeout
--
--   D. Single-Get timeout (registry probe times out before the auth
--      fetch is even reached — only one URL on the line):
--      Error response from daemon: <op> "https://<host>/<path>": <suffix>
--      <suffix> is "context deadline exceeded" or a
--      "net/http: ...Client.Timeout exceeded ..." client-side timeout.
--      Same ':timeout' unification as C, but here <host> is the single
--      URL's host (e.g. registry-1.docker.io — the registry endpoint
--      itself died, not the auth/token host). Recurs across "Set up
--      QEMU" (binfmt pull) and "Set up Docker Buildx" runs. Checked
--      after C so the two-URL nested form still keys on its inner host.
--      → registry-error:<host>:timeout
--
-- Declares override of go-test-failure for consistency with
-- registry-error.lua; in practice these patterns rarely fire inside
-- Go-test log contexts.

overrides = { "go-test-failure" }

-- No failed_steps gate: a registry/daemon HTTP error is an authoritative,
-- step-agnostic network cause — it's the real failure whether it surfaces in
-- "Set up Docker Buildx", "Build", "Set up QEMU", or inside a "Test" step
-- pulling an image. (See `flakie parser steps`: every matched step was a
-- genuine registry failure.)

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- C. Nested form — checked first so the leading `Head`/`Get` op
    -- token doesn't get matched as an opcode by form A.
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

    -- D. Single-URL timeout — only one URL on the line (form C's
    -- two-URL match already returned above for the nested case). Gated
    -- on the same timeout suffixes as C so it never steals form A
    -- (whose suffix is "received unexpected HTTP status: <code>").
    do
      local host, suffix = line:match(
        'Error response from daemon: %S+ "https?://([^/"]+)[^"]*": (.+)$')
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

    -- B. Bare form (no URL).
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
  end
  return nil
end
