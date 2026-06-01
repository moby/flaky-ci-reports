-- gha-cache-miss: the actions/cache step in moby's validate workflow is
-- configured with `fail-on-cache-miss: true` (each validate job consumes
-- a `dev-image-<runid>` cache produced by an upstream build job). When
-- the upstream build hasn't completed yet (or failed silently), the
-- cache restore fails with:
--   ##[error]Failed to restore cache entry. Exiting as fail-on-cache-miss is set. Input key: <KEY>
--
-- Different validates (vendor, golangci-lint, pkg-imports, ...) all
-- consume the same per-run cache, so the same run produces N parallel
-- cache-miss errors. The run-id varies per run; normalize() strips it
-- so all `dev-image-*` misses across runs share one key.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)restore" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local key = line:match(
      "##%[error%]Failed to restore cache entry%. Exiting as fail%-on%-cache%-miss is set%. Input key: (%S+)")
    if key then
      local fam = normalize(key):gsub("[%-_]+$", "")
      return {
        unique_key = "gha-cache-miss:" .. fam,
        name       = "GHA cache miss with fail-on-cache-miss: " .. key,
        category   = "dependency",
        fields     = { cache_key = key, cache_key_family = fam },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
