-- registry-error: catches container-registry HTTP failures emitted as
--   unexpected status from (POST|GET|HEAD) request to https://<host>/...: <CODE> <reason>
-- mcr.microsoft.com 403 on Windows-base-image manifest HEAD is the dominant
-- case in moby; same shape covers any registry returning a status to a
-- BuildKit / containerd resolver.
--
-- Shares `registry-error:<host>:<key>` namespace with docker-daemon-error
-- (daemon-side variants), docker-pull-blocked (HTML "blocked" body). Numeric
-- status here vs reason tokens elsewhere — no key collision.

overrides = { "go-test-failure" }

-- No failed_steps gate: authoritative registry HTTP-status cause — the real
-- failure wherever it surfaces. Reparse confirmed it spans Build / Validate /
-- Test / Create manifest / Set up Buildx, so any single-step gate loses hits.

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    local op, host, status = line:match(
      "unexpected status from (%S+) request to https?://([^/:?]+).*: (%d+) ")
    if op then
      local test_path = failing_test_near(log, i, 2000)
      local test_tags = {}
      local bare = nil
      if test_path then
        bare, test_tags = extract_tags(test_path, {"worker", "frontend", "slice"})
        if bare == "TestIntegration" or bare == "" then
          bare = nil
        end
      end
      local tags = merge_tags(test_tags, { host = host, status = status })
      if bare then tags.test = bare end

      local k = host .. "|" .. status .. "|" .. (bare or "")
      if not seen[k] then
        seen[k] = true
        table.insert(out, {
          unique_key = "registry-error:" .. host .. ":" .. status,
          name       = "Registry " .. host .. " returned HTTP " .. status,
          category   = "network",
          fields     = { operation = op, host = host, status = status },
          tags       = tags,
          evidence   = { { start_line = i, end_line = i } },
        })
      end
    end
  end
  return out
end
