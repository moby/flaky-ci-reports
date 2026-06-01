-- buildkitd-no-worker: buildkitd refuses to start when no worker
-- backend is available, printing
--   buildkitd: no worker found, rebuild the buildkit daemon?
-- followed by a Go-style stack trace from cmd/buildkitd. Hit in the
-- vagrant/freebsd CI when the containerd socket isn't where buildkitd
-- expects it. The visible umbrella in the GH log is a generic retry
-- wrapper (`##[error]Final attempt failed. Child_process exited with
-- error code 1`); the actual cause is here.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)smoke test" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    if line:match("buildkitd: no worker found, rebuild the buildkit daemon%?") then
      return {
        unique_key = "buildkitd-no-worker",
        name       = "buildkitd: no worker found",
        category   = "other",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
