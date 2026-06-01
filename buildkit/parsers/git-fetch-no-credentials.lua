-- git-fetch-no-credentials: git reports
--   fatal: could not read Username for '<host>': terminal prompts disabled
-- when a non-interactive context (CI, BuildKit's runc sandbox) tries to
-- fetch a repository it can't authenticate to. The host is part of the
-- key so failures against different remotes stay separate.
--
-- The downstream symptom is often "cannot parse bake definitions" or a
-- buildx bake failure — those are not the cause and shouldn't get their
-- own parsers; the cause is here.

-- failed_steps: only fire when the actually-failed step matches (see DESIGN.md §Failed-step gating).
failed_steps = { "(?i)build" }

function parse(log, ctx)
  for i, line in ipairs(log.lines) do
    local host = line:match("fatal: could not read Username for '([^']+)': terminal prompts disabled")
    if host then
      return {
        unique_key = "git-fetch-no-credentials:" .. host,
        name       = "git fetch failed: no credentials for " .. host,
        category   = "other",
        fields     = { remote = host },
        evidence   = { { start_line = i, end_line = i } },
      }
    end
  end
  return nil
end
