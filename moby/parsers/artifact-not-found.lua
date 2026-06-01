-- artifact-not-found: actions/download-artifact reports
--   ##[error]Unable to download artifact(s): Artifact not found for name: <name>
-- when the requested artifact was never uploaded. Hit in moby's
-- integration-test-report aggregator jobs that consume an upstream
-- test job's reports — when the upstream test job failed before
-- uploading, the aggregator can't proceed.
--
-- The artifact name is stable across runs (e.g.
-- `windows-2025-graphdriver-unit-reports`); use it as the key suffix
-- so different missing-artifact families stay distinguishable.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)download.*artifact" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local name = line:match(
      "##%[error%]Unable to download artifact%(s%): Artifact not found for name: (%S+)")
    if name then
      return {
        unique_key = "artifact-not-found:" .. name,
        name       = "actions/download-artifact: artifact not found: " .. name,
        category   = "dependency",
        fields     = { artifact_name = name },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
