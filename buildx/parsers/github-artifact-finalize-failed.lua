-- github-artifact-finalize-failed: actions/upload-artifact uploads the
-- blob successfully, then the *finalize* API call to GitHub's artifact
-- service returns non-2xx and the action gives up:
--   ##[error]Failed to FinalizeArtifact: Received non-retryable error: Failed request: (<CODE>) <reason>: Error from intermediary with HTTP status code <CODE> "<reason>"
--
-- The status code is the cause shape (403 = permission/scope, 5xx =
-- backend flake). Sister to github-artifact-upload-failed (the
-- buildkit-specific parser for `##[error]The server is busy.` during
-- the upload phase) — different phase, different surface, different
-- key family.
--
-- Does NOT override go-test-failure: this fires in the post-job
-- cleanup step, after tests have already run. For jobs where tests
-- failed AND finalize also failed, both observations are independently
-- informative and should not be merged.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)upload" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local status = line:match(
      "##%[error%]Failed to FinalizeArtifact:.-Failed request: %((%d+)%)")
    if status then
      return {
        unique_key = "github-artifact-finalize-failed:" .. status,
        name       = "actions/upload-artifact: FinalizeArtifact returned HTTP " .. status,
        category   = "network",
        fields     = { status = status },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
