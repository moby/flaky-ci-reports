-- docker-daemon-error: dockerd / docker pull surfaces registry-side
-- failures in four message shapes. All four are *registry-side* causes
-- (registry returned 5xx, auth host timed out, auth required, etc.) —
-- same failure family as BuildKit-side errors, so this parser shares
-- the `registry-error:<host>:<status_or_marker>` key namespace with
-- registry-error.lua and registry-net-error.lua. Parser file is the
-- "how" of extraction; the key is the "what" of the cause.
--
--   A. URL form (full URL + HTTP status):
--      ERROR: Error response from daemon: <OP> "https://<host>/<path>": received unexpected HTTP status: <CODE> <reason>
--      → registry-error:<host>:<code>
--
--   B. Bare HTTP-status form (no URL, just status — daemon swallowed the URL):
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
--   D. Auth-required (no URL, no HTTP status — just a text reason):
--      Error response from daemon: unauthorized: authentication required
--      Hit on `docker pull alpine` (and similar) when Docker Hub
--      transiently demands auth from an anonymous client. Generic
--      key — there's no host or status to discriminate on.
--      → docker-daemon-auth-required
--
-- Declares override of go-test-failure: when the daemon is the root
-- cause of a test failure, the per-test FAIL is downstream noise.

overrides = { "go-test-failure" }

-- No failed_steps gate: authoritative daemon/registry cause — the real failure
-- wherever it surfaces. Reparse spans Set up Buildx / Build / Set up QEMU / Test.

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

    -- B. Bare HTTP-status form (no URL).
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
  end
  return nil
end
