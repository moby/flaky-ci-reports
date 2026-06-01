-- codecov-upload-failed: the codecov uploader prints
--   ==> Failed to run upload-coverage
-- when its upload script fails. The pattern doesn't produce a GitHub
-- ##[error] annotation, so it needs a dedicated parser. Keyed on the
-- specific upload-coverage tool name, not the generic "wrapper failed"
-- shape — a different tool failing with the same wrapper convention is a
-- different cause and should get its own parser.
--
-- failed_steps gate: this "Failed to run upload-coverage" line is often
-- non-fatal (the coverage upload is allowed to fail and a LATER step — e.g.
-- "Download artifacts" — is the step that actually failed the job). Only fire
-- when the failed step is the coverage/codecov step itself. Patterns are Go
-- RE2, matched against ctx.failing_steps names. Verify against the real step
-- names in your `flakie unknown export` output / job metadata.

failed_steps = { "(?i)coverage", "(?i)codecov" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    -- Strip ANSI colour codes before matching.
    local clean = line:gsub("\27%[[0-9;]*m", "")
    if clean:match("==> Failed to run upload%-coverage") then
      return {
        unique_key = "codecov-upload-failed",
        name       = "codecov: upload-coverage script failed",
        category   = "network",
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
