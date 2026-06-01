-- missing-test-reports: moby's integration-test-report aggregator job
-- runs `find /tmp/reports -type f -name '*-go-test-report.json' ...`
-- after downloading the upstream test job's artifact. When the
-- upstream test job died early and the artifact contents are empty
-- (or the expected path layout differs), `find` complains:
--   find: '/tmp/reports': No such file or directory
--   ##[error]Process completed with exit code 1.
--
-- Sister to artifact-not-found.lua (different surface, same root-cause
-- family: upstream test job didn't produce reports). Job-level — there
-- is no specific test or matrix dim to attribute.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)summary" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- The runner sometimes renders UTF-8 fancy single quotes (‘’) around
    -- the path; the bytes are multi-byte and won't match a Lua char class.
    -- Use a permissive `.-` to span either ASCII or fancy quotes.
    if line:match("find: .-/tmp/reports.-: No such file or directory") then
      return {
        unique_key = "missing-test-reports:tmp-reports",
        name       = "integration-test-report: /tmp/reports missing after artifact download",
        category   = "dependency",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
