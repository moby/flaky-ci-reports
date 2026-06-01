-- buildx-bake-build-failed: buildx-bake reports
--   buildx bake failed with: ERROR: failed to solve: process "<cmd>" did not complete successfully: exit code: <N>
-- The failing inner process command identifies WHAT failed during the
-- bake build (e.g., "/bin/sh -c go mod download" vs "/bin/sh -c apk add").
-- Different commands failing are different causes; group by the command.
-- Exit code is omitted from the key — "exit code 1" is not the failure,
-- it's just what an exit code looks like.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build", "(?i)validate" }

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
