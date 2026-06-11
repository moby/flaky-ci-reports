-- registry-error: catches container-registry HTTP failures emitted as
--   unexpected status from (HEAD|GET) request to https://<host>/...: <CODE> <reason>
-- Both direct registry requests (HEAD /v2/...) and registry auth-token
-- requests (GET <auth-host>/token?...) follow this pattern, so a single
-- parser covers both. The host + status define the failure shape; the
-- test that was running becomes a tag so multiple tests hitting the same
-- registry issue group together but stay distinguishable.
--
-- Overrides go-test-failure: when the registry is the root cause, the
-- "TestX failed" observation is just the symptom.

overrides = { "go-test-failure" }

function parse(log, ctx)
  local out = {}
  local seen = {}
  for i, line in ipairs(log.lines) do
    do
      local status = line:match("error writing layer blob: failed to parse error response (%d+)")
      if status then
        local dedup_key = "blob-write|" .. status
        if not seen[dedup_key] then
          seen[dedup_key] = true
          table.insert(out, {
            unique_key = "registry-error:blob-write:" .. status,
            name       = "Registry layer blob write returned HTTP " .. status,
            category   = "network",
            fields     = { operation = "blob-write", status = status },
            evidence   = { { start_line = i, end_line = i } },
          })
        end
      end
    end

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
        bare, test_tags = extract_tags(test_path, {"worker", "frontend", "slice"})
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
