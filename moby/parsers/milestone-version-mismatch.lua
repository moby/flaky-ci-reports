-- milestone-version-mismatch: the `validate-milestone` job checks that the
-- PR's milestone matches the "docker next version" derived from the branch.
-- When they diverge, the validation script calls core.setFailed, surfaced as
-- a runner annotation with the concrete versions:
--   ##[error]Milestone '29.6.0' does not match docker next version '29.5.3'
--
-- Anchored on the `##[error]` prefix so it matches the *rendered* annotation,
-- not the workflow's inline JS source (`core.setFailed(\`Milestone
-- '${milestone}' does not match ...\`)`) which is echoed earlier in the log
-- with the literal `${...}` placeholders.
--
-- A real release-process gate (the milestone metadata is wrong), not a flake
-- and not test/network/dependency -> other. The two versions change every
-- release, so they stay out of the key and live in fields.

-- failed_steps: only fire when the milestone-validation step is the one that failed.
failed_steps = { "(?i)milestone" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local milestone, expected = line:match(
      "##%[error%]Milestone '([^']+)' does not match docker next version '([^']+)'")
    if milestone then
      return {
        unique_key = "milestone-version-mismatch",
        name       = "validate-milestone: milestone " .. milestone ..
                     " != next version " .. expected,
        category   = "other",
        fields     = { milestone = milestone, expected = expected },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
