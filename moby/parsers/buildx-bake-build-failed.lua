-- buildx-bake-build-failed: buildx bake reports
--   buildx bake failed with: ERROR: failed to solve: process "<cmd>" did not complete successfully: exit code: <N>
-- Different commands failing are different causes; group by the command
-- (e.g., curl plugins.tgz vs wget nydus-static). Exit code is omitted
-- from the key — "exit code 1" is not the failure, it's just what an
-- exit code looks like.
--
-- Only matches the `process "<cmd>" did not complete successfully:` shape.
-- Other `buildx bake failed with:` umbrellas (oauth token, source metadata,
-- push) are caught by registry-error / docker-resolve-source-failed /
-- docker-push-failed.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build", "(?i)test" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local cmd = line:match(
      'buildx bake failed with: ERROR: failed to solve: process "(.-)" did not complete successfully:')
    if cmd then
      return {
        unique_key = "buildx-bake-process-failed:" .. normalize(cmd),
        name       = "buildx bake: process '" .. cmd .. "' failed",
        category   = "test",
        fields     = { command = cmd },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
