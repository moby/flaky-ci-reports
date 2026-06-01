-- registry-error: catches container-registry HTTP failures emitted as
--   unexpected status from (POST|GET|HEAD) request to https://<host>/...: <CODE> <reason>
-- Both direct registry requests (HEAD /v2/...) and registry auth-token
-- requests (POST <auth-host>/token) follow this pattern; one parser
-- covers both. The host + status define the cause shape; the test that
-- was running becomes a tag so multiple tests hitting the same registry
-- issue group together but stay distinguishable.
--
-- Shares the `registry-error:<host>:<key>` namespace with
-- registry-net-error (TCP/TLS failures with no HTTP status) and
-- docker-daemon-error (daemon-side variants). Numeric status here
-- vs reason tokens elsewhere — no key collision.

overrides = { "go-test-failure" }

-- No failed_steps gate: authoritative registry HTTP-status cause — the real
-- failure wherever it surfaces. Reparse confirmed it spans Build / Validate /
-- Test / Create manifest / Set up Buildx, so any single-step gate loses hits.

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    -- Greedy `.*` on the path so URLs whose path contains `:` (e.g.
    -- /v2/foo/manifests/sha256:abcdef...) anchor to the final ": <status> "
    -- at end of line rather than the inline colon.
    local op, host, status = line:match(
      "unexpected status from (%S+) request to https?://([^/:?]+).*: (%d+) ")
    if op then
      local test_path = failing_test_near(log, i, 2000)
      local test_tags = {}
      local bare = nil
      if test_path then
        bare, test_tags = extract_tags(test_path, {"worker"})
        if bare == "TestIntegration" or bare == "" then
          bare = nil
        end
      end
      local tags = merge_tags(test_tags, { host = host, status = status })
      if bare then tags.test = bare end

      local dedup_key = host .. "|" .. status .. "|" .. (bare or "")
      if not seen[dedup_key] then
        seen[dedup_key] = true
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
